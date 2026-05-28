import Foundation

/// Plugin runtime — concrete backing for the Phase 4
/// [plugin-system-contract.json](../../../../the cross-SDK drift contract)
/// interface. Phase 4 pinned the lifecycle-hook shape; Phase 4.5
/// lands the in-memory registry that dispatches hooks to every
/// registered plugin.
///
/// Plugins are scoped per-SDK-instance. The Aegis singleton owns
/// the registry; the host app calls
/// `Aegis.shared.plugins.register(MyPlugin())` after init.

/// Decision returned from `onTrack` — lets a plugin suppress, pass
/// through, or replace the event entirely.
public enum PluginTrackDecision {
    case pass
    case suppress
    case replace(AegisEvent)
}

/// Plugin lifecycle hooks. Default implementations are no-ops so
/// plugins only override the hooks they care about.
public protocol AegisPlugin: AnyObject {
    var name: String { get }
    var version: String { get }
    var requiredConsentCategory: ConsentManager.Category? { get }

    func onInit(aegis: Aegis)
    func onTrack(event: AegisEvent) -> PluginTrackDecision
    func onIdentify(userId: String, traits: [String: Any]?)
    func onScreen(screenName: String, properties: [String: Any]?)
    func onConsentChange(preferences: ConsentManager.ConsentPreferences)
    func onReset()
    func onDestroy()
}

public extension AegisPlugin {
    var requiredConsentCategory: ConsentManager.Category? { nil }
    func onInit(aegis: Aegis) {}
    func onTrack(event: AegisEvent) -> PluginTrackDecision { .pass }
    func onIdentify(userId: String, traits: [String: Any]?) {}
    func onScreen(screenName: String, properties: [String: Any]?) {}
    func onConsentChange(preferences: ConsentManager.ConsentPreferences) {}
    func onReset() {}
    func onDestroy() {}
}

public final class PluginRegistry {

    private let lock = NSLock()
    private var plugins: [String: AegisPlugin] = [:]
    private var order: [String] = []
    private weak var aegis: Aegis?

    internal init(aegis: Aegis?) {
        self.aegis = aegis
    }

    /// Register a plugin. Throws if a plugin with the same name is
    /// already registered. Invokes `onInit` synchronously.
    @discardableResult
    public func register(_ plugin: AegisPlugin) -> Bool {
        lock.lock()
        if plugins[plugin.name] != nil {
            lock.unlock()
            return false
        }
        plugins[plugin.name] = plugin
        order.append(plugin.name)
        lock.unlock()
        if let aegis = aegis {
            plugin.onInit(aegis: aegis)
        }
        return true
    }

    /// Unregister a plugin by name. Invokes `onDestroy` synchronously.
    @discardableResult
    public func unregister(_ name: String) -> Bool {
        lock.lock()
        guard let plugin = plugins.removeValue(forKey: name) else {
            lock.unlock()
            return false
        }
        order.removeAll { $0 == name }
        lock.unlock()
        plugin.onDestroy()
        return true
    }

    public func list() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return order
    }

    /// Ordered iteration over all registered plugins. Order matches
    /// registration order — `Aegis.track()` uses this so the first
    /// plugin to suppress short-circuits.
    public func allPlugins() -> [AegisPlugin] {
        lock.lock(); defer { lock.unlock() }
        return order.compactMap { plugins[$0] }
    }

    // Convenience dispatchers used by Aegis.swift.

    internal func dispatchIdentify(userId: String, traits: [String: Any]?) {
        for plugin in allPlugins() { plugin.onIdentify(userId: userId, traits: traits) }
    }

    internal func dispatchScreen(screenName: String, properties: [String: Any]?) {
        for plugin in allPlugins() { plugin.onScreen(screenName: screenName, properties: properties) }
    }

    internal func dispatchConsentChange(_ preferences: ConsentManager.ConsentPreferences) {
        for plugin in allPlugins() { plugin.onConsentChange(preferences: preferences) }
    }

    internal func dispatchReset() {
        for plugin in allPlugins() { plugin.onReset() }
    }
}
