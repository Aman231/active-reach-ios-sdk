import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Push lifecycle tracker for iOS. Parity port of
/// the web SDK source `createBuiltinEventTracker`
/// (web SDK ≥1.12.0) and a mirror of the Android `AegisPushTracker`.
///
/// Posts `push.delivered` / `push.clicked` / `push.dismissed` to
/// `POST /v1/push/engagement` with the canonical wire shape pinned by
/// [the cross-SDK drift contract].
///
/// The tracker is a singleton accessed via `AegisPushTracker.shared`
/// because the NSE (which runs in a separate extension process) and
/// the UN delegate (which runs in the host app) both need to emit
/// engagement events with the same configuration. Configuration is
/// persisted in `UserDefaults(suiteName:)` using an App Group so
/// host app + extension share it.
///
/// Best-effort — POST failures are logged but never thrown back to the
/// caller (the OS already showed the notification; pre-rejecting the
/// completion handler would be UB).
///
/// Phase 2 migration note: pre-Phase-2 the iOS NSE posted to a
/// `/v1/analytics/mobile_sdk_ingest` legacy endpoint with a
/// Segment-style envelope; the UN delegate posted to
/// `/v1/devices/push/events` with bare-word `opened`. Both are
/// drift-locked OUT in the cross-SDK drift contract.
public final class AegisPushTracker {

    /// Singleton — used by both the NSE process and the host app's
    /// UN delegate.
    public static let shared = AegisPushTracker()

    /// Configuration must be persisted in an App Group so the NSE
    /// (separate process) can read it. Customers who ship their NSE
    /// need to enable the same App Group on both targets and pass
    /// the group id via [configure].
    private struct Config: Codable {
        let writeKey: String
        let baseURL: String
        let propertyId: String?
        let organizationId: String?
        let contactId: String?
        let anonymousId: String?
    }

    private var appGroupSuiteName: String?
    private var inMemoryConfig: Config?

    private init() {}

    // MARK: - Configuration

    /// Configure the tracker. Called once from `Aegis.shared.initialize()`.
    /// The `appGroupSuiteName` is REQUIRED when the host app also ships
    /// a Notification Service Extension (NSE) — the NSE runs in a
    /// separate process and can only read configuration from a shared
    /// App Group.
    public func configure(
        writeKey: String,
        baseURL: String = "https://api.active-reach.ai",
        propertyId: String? = nil,
        organizationId: String? = nil,
        anonymousId: String? = nil,
        appGroupSuiteName: String? = nil
    ) {
        let config = Config(
            writeKey: writeKey,
            baseURL: baseURL,
            propertyId: propertyId,
            organizationId: organizationId,
            contactId: nil,
            anonymousId: anonymousId
        )
        self.appGroupSuiteName = appGroupSuiteName
        self.inMemoryConfig = config
        persistConfig(config)
    }

    /// Update the resolved contact id after a successful identify().
    public func setContactId(_ contactId: String?) {
        guard var config = readConfig() else { return }
        config = Config(
            writeKey: config.writeKey,
            baseURL: config.baseURL,
            propertyId: config.propertyId,
            organizationId: config.organizationId,
            contactId: contactId,
            anonymousId: config.anonymousId
        )
        inMemoryConfig = config
        persistConfig(config)
    }

    // MARK: - Canonical lifecycle methods

    public func trackDelivered(
        campaignId: String?,
        messageId: String?,
        metadata: [String: Any] = [:]
    ) {
        postEngagement("push.delivered", campaignId: campaignId, messageId: messageId, metadata: metadata)
    }

    public func trackClicked(
        campaignId: String?,
        messageId: String?,
        metadata: [String: Any] = [:]
    ) {
        postEngagement("push.clicked", campaignId: campaignId, messageId: messageId, metadata: metadata)
    }

    public func trackDismissed(
        campaignId: String?,
        messageId: String?,
        metadata: [String: Any] = [:]
    ) {
        postEngagement("push.dismissed", campaignId: campaignId, messageId: messageId, metadata: metadata)
    }

    /// Register an APNs device token. Mirrors the Android
    /// `reRegisterToken` path. Pass the hex-encoded token; the SDK
    /// records it via `POST /v1/devices/register`.
    public func registerDeviceToken(_ hexToken: String) {
        guard let config = readConfig() else {
            print("[Active Reach Push Tracker] Cannot register token: SDK not configured")
            return
        }
        var payload: [String: Any] = [
            "device_token": hexToken,
            "platform": "ios",
        ]
        if let propertyId = config.propertyId { payload["property_id"] = propertyId }
        if let contactId = config.contactId { payload["contact_id"] = contactId }
        if let anonymousId = config.anonymousId { payload["anonymous_id"] = anonymousId }
        payload["app_version"] = appVersion()
        payload["user_agent"] = userAgent()
        post(endpoint: "/v1/devices/register", config: config, payload: payload)
    }

    // MARK: - Private

    private func postEngagement(
        _ eventType: String,
        campaignId: String?,
        messageId: String?,
        metadata: [String: Any]
    ) {
        guard let config = readConfig() else {
            print("[Active Reach Push Tracker] Cannot post \(eventType): SDK not configured")
            return
        }
        var payload: [String: Any] = [
            "event_type": eventType,
            "platform": "ios",
            "campaign_id": campaignId ?? "",
            "message_id": messageId ?? "",
            "metadata": metadata,
        ]
        if let propertyId = config.propertyId { payload["property_id"] = propertyId }
        if let contactId = config.contactId {
            payload["contact_id"] = contactId
            payload["user_id"] = contactId
        }
        if let anonymousId = config.anonymousId { payload["anonymous_id"] = anonymousId }
        post(endpoint: "/v1/push/engagement", config: config, payload: payload)
    }

    private func post(endpoint: String, config: Config, payload: [String: Any]) {
        guard let url = URL(string: config.baseURL + endpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        if let organizationId = config.organizationId {
            request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        }
        if let propertyId = config.propertyId {
            request.setValue(propertyId, forHTTPHeaderField: "X-Property-Id")
        }
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("[Active Reach Push Tracker] Failed to serialise \(endpoint) payload: \(error)")
            return
        }
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[Active Reach Push Tracker] \(endpoint) → network error: \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[Active Reach Push Tracker] \(endpoint) → HTTP \(http.statusCode)")
            }
        }.resume()
    }

    // MARK: - Config persistence

    private static let storageKey = "ai.aegis.push.tracker.config"

    private func defaults() -> UserDefaults {
        if let suite = appGroupSuiteName, let d = UserDefaults(suiteName: suite) {
            return d
        }
        return .standard
    }

    private func persistConfig(_ config: Config) {
        if let data = try? JSONEncoder().encode(config) {
            defaults().set(data, forKey: Self.storageKey)
        }
    }

    private func readConfig() -> Config? {
        if let config = inMemoryConfig { return config }
        guard let data = defaults().data(forKey: Self.storageKey),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        inMemoryConfig = config
        return config
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func userAgent() -> String {
        #if canImport(UIKit)
        let osVersion = UIDevice.current.systemVersion
        let model = UIDevice.current.model
        return "ActiveReach-iOS-SDK/\(AegisVersion.current) iOS \(osVersion) (\(model)) App/\(appVersion())"
        #else
        return "ActiveReach-iOS-SDK/\(AegisVersion.current) App/\(appVersion())"
        #endif
    }
}
