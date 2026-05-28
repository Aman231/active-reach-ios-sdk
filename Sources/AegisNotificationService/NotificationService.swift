import UserNotifications

public class AegisNotificationService: UNNotificationServiceExtension {
    
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?
    
    public override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }
        
        let userInfo = request.content.userInfo

        // Resolve image URL — check the two locations providers put it in:
        //   1. Top-level `image_url` (our canonical send field)
        //   2. FCM's nested `fcm_options.image` (Firebase Cloud Messaging default)
        //
        // `userInfo[...]` is `Any?`, so we need an explicit cast through
        // `[String: Any]` before we can subscript into the nested map —
        // Swift won't subscript an `Any?`. The previous inline form was a
        // compile error that blocked `swift build` for this target.
        let fcmImage = (userInfo["fcm_options"] as? [String: Any])?["image"] as? String
        let imageUrlString = (userInfo["image_url"] as? String) ?? fcmImage

        if let imageUrlString = imageUrlString,
           let imageUrl = URL(string: imageUrlString) {
            downloadImage(from: imageUrl) { [weak self] attachment in
                if let attachment = attachment {
                    bestAttemptContent.attachments = [attachment]
                }
                
                self?.trackNotificationDelivery(userInfo)
                contentHandler(bestAttemptContent)
            }
        } else {
            trackNotificationDelivery(userInfo)
            contentHandler(bestAttemptContent)
        }
    }
    
    public override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            
            downloadTask?.cancel()
            
            trackNotificationDelivery(bestAttemptContent.userInfo)
            contentHandler(bestAttemptContent)
        }
    }
    
    private func downloadImage(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        let session = URLSession(configuration: .default)
        
        downloadTask = session.downloadTask(with: url) { [weak self] location, response, error in
            guard let self = self else {
                completion(nil)
                return
            }
            
            if let error = error {
                print("[Active Reach NSE] Image download failed: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let location = location else {
                completion(nil)
                return
            }
            
            let fileManager = FileManager.default
            let tmpDirectory = NSTemporaryDirectory()
            let tmpFile = "aegis-notification-image-\(UUID().uuidString)"
            
            let fileExtension = self.getFileExtension(from: response, url: url)
            let tmpFileUrl = URL(fileURLWithPath: tmpDirectory).appendingPathComponent("\(tmpFile).\(fileExtension)")
            
            do {
                try fileManager.moveItem(at: location, to: tmpFileUrl)
                
                let attachment = try UNNotificationAttachment(
                    identifier: "aegis-image",
                    url: tmpFileUrl,
                    options: [UNNotificationAttachmentOptionsTypeHintKey: fileExtension]
                )
                
                completion(attachment)
            } catch {
                print("[Active Reach NSE] Failed to create attachment: \(error)")
                completion(nil)
            }
        }
        
        downloadTask?.resume()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            if self?.downloadTask?.state == .running {
                self?.downloadTask?.cancel()
                print("[Active Reach NSE] Image download timed out after 25s")
                completion(nil)
            }
        }
    }
    
    private func getFileExtension(from response: URLResponse?, url: URL) -> String {
        if let mimeType = response?.mimeType {
            switch mimeType {
            case "image/jpeg", "image/jpg":
                return "jpg"
            case "image/png":
                return "png"
            case "image/gif":
                return "gif"
            case "image/webp":
                return "webp"
            case "video/mp4":
                return "mp4"
            default:
                break
            }
        }
        
        return url.pathExtension.isEmpty ? "jpg" : url.pathExtension
    }
    
    /// Phase 2 (web v1.12 wire shape, 2026-05-27).
    ///
    /// Posts `push.delivered` to `/v1/push/engagement` in the
    /// canonical wire shape (drift-locked by
    /// the cross-SDK drift contract).
    ///
    /// The NSE runs in a SEPARATE process from the host app — it
    /// can't import AegisPush (would drag in UIKit). Configuration
    /// is read from the App Group UserDefaults that the host's
    /// `AegisPushTracker.configure(appGroupSuiteName: ...)` writes.
    /// Customers MUST set the `AegisNotificationServiceAppGroup` key
    /// in this extension's Info.plist OR pass `aegis_app_group` in
    /// the push payload's userInfo for the NSE to resolve config.
    ///
    /// The NSE has ~30s before iOS kills it. We use a fire-and-forget
    /// `URLSession.shared.dataTask`; `contentHandler` is invoked by
    /// the caller regardless of POST completion. Never block.
    ///
    /// Pre-Phase-2 this method posted to `/v1/analytics/mobile_sdk_ingest`
    /// with a Segment-style envelope. Drift-locked OUT.
    private func trackNotificationDelivery(_ userInfo: [AnyHashable: Any]) {
        guard let config = readAppGroupConfig(userInfo) else { return }

        // Phase 4.5 NSE consent gate. If the host app's
        // ConsentManager has `marketing=false` recorded in the App
        // Group UserDefaults under "ai.aegis.consent.preferences",
        // the NSE silently skips the POST. The OS still shows the
        // notification — only the analytics POST is suppressed.
        // Drift contract: the cross-platform parity contract
        // ios_nse_consent_gating.
        if !readMarketingConsent() {
            return
        }

        let campaignId = userInfo["campaign_id"] as? String
        let messageId = (userInfo["message_id"] as? String)
            ?? (userInfo["notification_id"] as? String)

        var payload: [String: Any] = [
            "event_type": "push.delivered",
            "platform": "ios",
            "campaign_id": campaignId ?? "",
            "message_id": messageId ?? "",
        ]
        if let propertyId = config.propertyId { payload["property_id"] = propertyId }
        if let contactId = config.contactId {
            payload["contact_id"] = contactId
            payload["user_id"] = contactId
        }
        if let anonymousId = config.anonymousId { payload["anonymous_id"] = anonymousId }
        var metadata: [String: Any] = [:]
        if let nid = userInfo["notification_id"] as? String { metadata["notification_id"] = nid }
        payload["metadata"] = metadata

        guard let url = URL(string: config.baseURL + "/v1/push/engagement") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        if let organizationId = config.organizationId {
            request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        }
        if let propertyId = config.propertyId {
            request.setValue(propertyId, forHTTPHeaderField: "X-Property-Id")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }

    /// NSE-local mirror of the AegisPush `Config` struct. Decoded
    /// from the App Group UserDefaults via the same JSON key the
    /// host app writes to.
    private struct NSEConfig {
        let writeKey: String
        let baseURL: String
        let propertyId: String?
        let organizationId: String?
        let contactId: String?
        let anonymousId: String?
    }

    /// Read the host app's `marketing` consent state from the App
    /// Group UserDefaults. Returns true when consent is granted OR
    /// when no consent record exists (default behaviour — the host
    /// app hasn't shown a CMP yet; better to suppress than to
    /// double-default the pre-Phase-4-5 behaviour).
    private func readMarketingConsent() -> Bool {
        let suiteName: String? = (Bundle.main.object(forInfoDictionaryKey: "AegisNotificationServiceAppGroup") as? String)
        let defaults: UserDefaults? = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard let data = defaults?.data(forKey: "ai.aegis.consent.preferences"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // No consent record yet — Phase 4.5 default is to skip
            // so the NSE doesn't post analytics before the host has
            // shown its CMP. Host can override via the App-Group
            // record once consent is granted.
            return false
        }
        return (json["marketing"] as? Bool) ?? false
    }

    private func readAppGroupConfig(_ userInfo: [AnyHashable: Any]) -> NSEConfig? {
        // Resolution order:
        //   1. App-Group suite from this NSE's Info.plist
        //   2. App-Group suite from the push payload userInfo
        //      (`aegis_app_group`) — fallback for hosts that prefer to
        //      configure NSE per-push
        //   3. .standard (only useful when the host App + NSE somehow
        //      share UserDefaults — usually they don't, so this is a
        //      best-effort no-op)
        let suiteName: String? = (Bundle.main.object(forInfoDictionaryKey: "AegisNotificationServiceAppGroup") as? String)
            ?? (userInfo["aegis_app_group"] as? String)
        let defaults: UserDefaults? = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard let data = defaults?.data(forKey: "ai.aegis.push.tracker.config") else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let writeKey = json["writeKey"] as? String, !writeKey.isEmpty else { return nil }
        let baseURL = (json["baseURL"] as? String) ?? "https://api.active-reach.ai"
        return NSEConfig(
            writeKey: writeKey,
            baseURL: baseURL,
            propertyId: json["propertyId"] as? String,
            organizationId: json["organizationId"] as? String,
            contactId: json["contactId"] as? String,
            anonymousId: json["anonymousId"] as? String
        )
    }
}
