import Foundation

/// Meta Pixel companion helper. Parity port of Android
/// `MetaPixelCompanion` (Phase 4) — same shape, same wire contract.
/// Pinned by `the cross-SDK drift contract`
/// + `phase45-cross-platform.json`.
///
/// Used by tenants that also run Meta's App Events SDK / Pixel
/// client-side and need to pass the SAME `event_id` for client +
/// server CAPI dedup. Call `aegis.lastEventId(eventName)` and feed
/// that into the Meta Pixel's `eventID` parameter.
///
/// `_fbp` / `_fbc` cookie equivalents: Phase 4.5 sets up the in-memory
/// cache. Full persistence (`UserDefaults`) + `fbclid` extraction from
/// universal-link callbacks lands in Phase 4.6 alongside the
/// behavioural-trigger native implementations.
public final class MetaPixelCompanion {

    public static let shared = MetaPixelCompanion()

    private let lock = NSLock()
    private var lastByEvent: [String: String] = [:]

    private init() {}

    /// Record the messageId of the most recent track(eventName) call.
    /// Called by `Aegis.track()` under marketing consent.
    public func recordEvent(_ eventName: String, messageId: String) {
        lock.lock(); defer { lock.unlock() }
        lastByEvent[eventName] = messageId
    }

    /// Returns the messageId of the most recent track(<eventName>)
    /// call, or nil if none has been tracked since SDK init.
    public func lastEventId(_ eventName: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return lastByEvent[eventName]
    }

    /// Generate a stable `_fbp` cookie value. Mirrors the
    /// the web SDK meta-cookies.ts shape:
    /// `fb.<subdomain_index>.<creation_ms>.<random>`.
    public func generateFbp() -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let random = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))
        return "fb.1.\(now).\(random)"
    }

    /// Reset — called by `Aegis.reset()`.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        lastByEvent.removeAll()
    }
}
