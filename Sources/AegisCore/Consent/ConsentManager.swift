import Foundation

/// Canonical GDPR/CCPA consent category model. Parity port of
/// the web SDK source. Pinned by
/// `the cross-SDK drift contract`.
///
/// iOS-specific: ATT denial (`ATTrackingManager.requestTrackingAuthorization`
/// returns `.denied`) MUST set `marketing=false`. ATT grant SHOULD set
/// `marketing=true`. Operators can pre-grant marketing via setConsent
/// without showing the ATT prompt.
///
/// Pre-Phase-4 the iOS SDK had only `enableATT` / `waitForATTConsent`
/// boolean flags — those are now wrapped into this categorical model.
public final class ConsentManager {

    public enum Category: String {
        case necessary
        case functional
        case analytics
        case marketing
    }

    public struct ConsentPreferences: Codable, Equatable {
        public let necessary: Bool
        public let functional: Bool
        public let analytics: Bool
        public let marketing: Bool

        public init(necessary: Bool = true, functional: Bool = true,
                    analytics: Bool = false, marketing: Bool = false) {
            self.necessary = true  // immutable per drift contract
            _ = necessary           // silence unused warning
            self.functional = functional
            self.analytics = analytics
            self.marketing = marketing
        }
    }

    private static let storageKey = "ai.aegis.consent.preferences"
    private static let identityEvents: Set<String> = ["identify", "alias", "group"]

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var preferences: ConsentPreferences
    private var listeners: [(ConsentPreferences) -> Void] = []

    public init(defaults: UserDefaults = .standard,
                defaultConsent: ConsentPreferences? = nil) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(ConsentPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = defaultConsent ?? ConsentPreferences()
        }
    }

    /// Current consent preferences. Necessary is always true.
    public func current() -> ConsentPreferences {
        lock.lock(); defer { lock.unlock() }
        return preferences
    }

    /// True when consent has been ACTIVELY set by the user (not just default).
    public func hasUserDecision() -> Bool {
        defaults.data(forKey: Self.storageKey) != nil
    }

    public func setConsent(_ partial: [Category: Bool]) {
        var updated: ConsentPreferences
        lock.lock()
        updated = ConsentPreferences(
            necessary: true,
            functional: partial[.functional] ?? preferences.functional,
            analytics: partial[.analytics] ?? preferences.analytics,
            marketing: partial[.marketing] ?? preferences.marketing
        )
        preferences = updated
        if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.storageKey)
        }
        let snapshot = listeners
        lock.unlock()
        for listener in snapshot { listener(updated) }
    }

    public func has(_ category: Category) -> Bool {
        switch category {
        case .necessary:  return true
        case .functional: return preferences.functional
        case .analytics:  return preferences.analytics
        case .marketing:  return preferences.marketing
        }
    }

    /// Mapping mirrors the drift fixture's `event_category_mapping`.
    public func categoryForEvent(_ eventName: String) -> Category {
        if Self.identityEvents.contains(eventName) { return .necessary }
        if eventName.hasPrefix("push.") { return .marketing }
        if eventName == "meta-pixel-bridge" { return .marketing }
        return .analytics
    }

    public func shouldEmit(_ eventName: String) -> Bool {
        has(categoryForEvent(eventName))
    }

    @discardableResult
    public func onChange(_ listener: @escaping (ConsentPreferences) -> Void) -> () -> Void {
        lock.lock(); listeners.append(listener); lock.unlock()
        return { [weak self] in
            self?.lock.lock()
            self?.listeners.removeAll { String(describing: $0) == String(describing: listener) }
            self?.lock.unlock()
        }
    }
}
