import Foundation
import UIKit
import UserNotifications

public class AegisAPIClient {
    private let baseURL: String
    private let organizationId: String
    
    public init(baseURL: String, organizationId: String) {
        self.baseURL = baseURL
        self.organizationId = organizationId
    }
    
    public func post(_ endpoint: String, payload: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: baseURL + endpoint) else {
            completion(.failure(NSError(domain: "AegisAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(organizationId, forHTTPHeaderField: "X-Organization-Id")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "AegisAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(NSError(domain: "AegisAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

public struct ContactIdentity {
    let contactId: String?
    let shopifyCustomerId: String?
    let email: String?
    
    init(contactId: String? = nil, shopifyCustomerId: String? = nil, email: String? = nil) {
        self.contactId = contactId
        self.shopifyCustomerId = shopifyCustomerId
        self.email = email
    }
}

public class AegisPushManager: NSObject, UNUserNotificationCenterDelegate {
    
    private let apiClient: AegisAPIClient
    private var deviceToken: String?
    private var contactIdentity: ContactIdentity?
    private let appInstalled = true
    
    public init(apiClient: AegisAPIClient) {
        self.apiClient = apiClient
        super.init()
    }
    
    public func initialize() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
        // Phase 2: route through AegisPushTracker so the X-Aegis-Write-Key
        // header is set (drift fixture requires it). The legacy
        // registerDeviceToken path on this class is kept for back-compat
        // but the canonical path is the singleton tracker.
        AegisPushTracker.shared.registerDeviceToken(token)
        registerDeviceToken(token)
    }
    
    private func registerDeviceToken(_ token: String) {
        var payload: [String: Any] = [
            "device_token": token,
            "platform": "ios",
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "app_installed": appInstalled
        ]
        
        if let identity = contactIdentity {
            if let contactId = identity.contactId {
                payload["contact_id"] = contactId
            }
            if let shopifyId = identity.shopifyCustomerId {
                payload["shopify_customer_id"] = shopifyId
            }
            if let email = identity.email {
                payload["email"] = email
            }
        }
        
        apiClient.post("/v1/devices/register", payload: payload) { result in
            switch result {
            case .success(let response):
                print("[Active Reach Push] Device registered: \(response)")
            case .failure(let error):
                print("[Active Reach Push] Registration failed: \(error)")
            }
        }
    }
    
    public func identify(contactId: String? = nil, shopifyCustomerId: String? = nil, email: String? = nil) {
        self.contactIdentity = ContactIdentity(
            contactId: contactId,
            shopifyCustomerId: shopifyCustomerId,
            email: email
        )
        
        if let token = deviceToken {
            registerDeviceToken(token)
        }
    }
    
    public func logout() {
        guard let token = deviceToken else { return }
        
        apiClient.post("/v1/devices/unlink", payload: ["device_token": token]) { result in
            switch result {
            case .success:
                self.contactIdentity = nil
                print("[Active Reach Push] Device unlinked")
            case .failure(let error):
                print("[Active Reach Push] Unlink failed: \(error)")
            }
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      didReceive response: UNNotificationResponse,
                                      withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let campaignId = userInfo["campaign_id"] as? String
        let messageId = userInfo["message_id"] as? String

        // Phase 2 canonical: route through AegisPushTracker so the wire
        // shape matches web v1.12 (POST /v1/push/engagement with
        // event_type "push.clicked"). Pre-Phase-2 we posted to the
        // legacy /v1/devices/push/events endpoint with bare-word
        // "opened" — both are drift-locked OUT now.
        let deepLink = userInfo["deep_link"] as? String
        var metadata: [String: Any] = [:]
        if response.actionIdentifier != UNNotificationDefaultActionIdentifier {
            metadata["action_id"] = response.actionIdentifier
        }
        if let deepLink = deepLink {
            metadata["action_url"] = deepLink
        }
        AegisPushTracker.shared.trackClicked(
            campaignId: campaignId,
            messageId: messageId,
            metadata: metadata
        )

        if let deepLink = deepLink, let url = URL(string: deepLink) {
            handleDeepLink(url)
        }

        completionHandler()
    }

    /// `willPresent` fires when a push arrives while the app is in
    /// foreground. iOS treats this as "delivered to the app" — the
    /// banner/sound is gated by what we pass to `completionHandler`.
    /// We emit `push.delivered` here too so foreground-received
    /// pushes don't escape attribution (the NSE only runs for
    /// background pushes that ask for content-available + alert).
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                      willPresent notification: UNNotification,
                                      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let campaignId = userInfo["campaign_id"] as? String
        let messageId = userInfo["message_id"] as? String
        AegisPushTracker.shared.trackDelivered(
            campaignId: campaignId,
            messageId: messageId
        )
        completionHandler([.banner, .badge, .sound])
    }
    
    private func handleDeepLink(_ url: URL) {
        NotificationCenter.default.post(name: .aegisDeepLink, object: url)
    }
}

extension Notification.Name {
    public static let aegisDeepLink = Notification.Name("aegisDeepLink")
}
