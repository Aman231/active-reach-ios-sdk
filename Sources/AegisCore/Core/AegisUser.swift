import Foundation
import os.log

/// `Aegis.shared.user` namespace — typed PII + per-channel opt-in
/// setters that delegate to `Aegis.identify(_:traits:)` with pre-login
/// buffering. Parity port of the web SDK source
/// (web SDK 1.13.0).
///
/// Pre-login `setX` calls accumulate in `pendingTraits` and flush as a
/// single `identify()` when `login()` fires — avoids polluting the
/// contact graph with anonymous-id-as-userId rows.
///
/// Contract pinned by
/// `the cross-SDK drift contract`.
public final class AegisUser {

    public enum OptInChannel: String {
        case email, sms, push, webpush, whatsapp, rcs, inapp
    }

    private let aegis: Aegis
    private let lock = NSLock()
    private var pendingTraits: [String: Any] = [:]
    private let logger = OSLog(subsystem: "ai.active-reach.sdk", category: "AegisUser")

    internal init(aegis: Aegis) {
        self.aegis = aegis
    }

    public func login(_ userId: String, traits: [String: Any]? = nil) {
        guard !userId.isEmpty else {
            os_log("[user.login] userId must be non-empty", log: logger, type: .default)
            return
        }
        var merged = [String: Any]()
        lock.lock()
        for (k, v) in pendingTraits { merged[k] = v }
        pendingTraits.removeAll()
        lock.unlock()
        traits?.forEach { merged[$0.key] = $0.value }
        aegis.identify(userId, traits: merged)
    }

    public func logout() {
        lock.lock(); pendingTraits.removeAll(); lock.unlock()
        aegis.reset()
    }

    public func setAttribute(_ key: String, _ value: Any) {
        guard !key.isEmpty else {
            os_log("[user.setAttribute] key must be non-empty", log: logger, type: .default)
            return
        }
        writeTraits([key: value])
    }

    public func setAttributes(_ map: [String: Any]) { writeTraits(map) }

    public func setEmail(_ email: String) {
        guard Self.emailRegex.firstMatch(in: email, options: [], range: NSRange(location: 0, length: email.utf16.count)) != nil else {
            os_log("[user.setEmail] invalid email format", log: logger, type: .default)
            return
        }
        writeTraits(["email": email.lowercased()])
    }

    public func setPhone(_ phone: String) {
        guard Self.phoneRegex.firstMatch(in: phone, options: [], range: NSRange(location: 0, length: phone.utf16.count)) != nil else {
            os_log("[user.setPhone] phone must be E.164 (e.g. +15551234567)", log: logger, type: .default)
            return
        }
        writeTraits(["phone": phone])
    }

    public func setHashedEmail(_ sha256Hex: String) {
        guard Self.sha256Regex.firstMatch(in: sha256Hex, options: [], range: NSRange(location: 0, length: sha256Hex.utf16.count)) != nil else {
            os_log("[user.setHashedEmail] expected 64-char hex SHA-256", log: logger, type: .default)
            return
        }
        writeTraits(["email_sha256": sha256Hex.lowercased()])
    }

    public func setHashedPhone(_ sha256Hex: String) {
        guard Self.sha256Regex.firstMatch(in: sha256Hex, options: [], range: NSRange(location: 0, length: sha256Hex.utf16.count)) != nil else {
            os_log("[user.setHashedPhone] expected 64-char hex SHA-256", log: logger, type: .default)
            return
        }
        writeTraits(["phone_sha256": sha256Hex.lowercased()])
    }

    public func setBirthDate(_ iso: String) {
        guard Self.isoDateRegex.firstMatch(in: iso, options: [], range: NSRange(location: 0, length: iso.utf16.count)) != nil else {
            os_log("[user.setBirthDate] expected YYYY-MM-DD", log: logger, type: .default)
            return
        }
        writeTraits(["birth_date": iso])
    }

    public func setOptIn(_ channel: OptInChannel, _ granted: Bool) {
        writeTraits(["opt_in_\(channel.rawValue)": granted])
    }

    public func setSecureToken(_ token: String) {
        guard !token.isEmpty else {
            os_log("[user.setSecureToken] token must be non-empty", log: logger, type: .default)
            return
        }
        writeTraits(["_secure_token": token])
    }

    /// Test hook — returns a copy of pendingTraits.
    public func _getPendingTraitsForTest() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return pendingTraits
    }

    // MARK: - Private

    private func writeTraits(_ traits: [String: Any]) {
        if let userId = aegis.getUserId() {
            aegis.identify(userId, traits: traits)
            return
        }
        lock.lock()
        for (k, v) in traits { pendingTraits[k] = v }
        lock.unlock()
    }

    private static let emailRegex = try! NSRegularExpression(pattern: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
    private static let phoneRegex = try! NSRegularExpression(pattern: "^\\+[1-9]\\d{7,14}$")
    private static let sha256Regex = try! NSRegularExpression(pattern: "^[a-fA-F0-9]{64}$")
    private static let isoDateRegex = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")
}
