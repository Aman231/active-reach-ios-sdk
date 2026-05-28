import Foundation
import UIKit

public struct CartItem: Codable {
    public let productId: String
    public let productName: String
    public let quantity: Int
    public let price: Double
    
    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case productName = "product_name"
        case quantity
        case price
    }
    
    public init(productId: String, productName: String, quantity: Int, price: Double) {
        self.productId = productId
        self.productName = productName
        self.quantity = quantity
        self.price = price
    }
}

public struct CartData: Codable {
    public let cartId: String
    public let cartTotal: Double
    public let cartCurrency: String
    public let cartItems: [CartItem]
    public let cartToken: String?
    public let cartUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case cartId = "cart_id"
        case cartTotal = "cart_total"
        case cartCurrency = "cart_currency"
        case cartItems = "cart_items"
        case cartToken = "cart_token"
        case cartUrl = "cart_url"
    }
    
    public init(cartId: String, cartTotal: Double, cartCurrency: String, cartItems: [CartItem], cartToken: String? = nil, cartUrl: String? = nil) {
        self.cartId = cartId
        self.cartTotal = cartTotal
        self.cartCurrency = cartCurrency
        self.cartItems = cartItems
        self.cartToken = cartToken
        self.cartUrl = cartUrl
    }
}

/// Main Active Reach SDK interface for iOS
public class Aegis {
    
    // MARK: - Singleton
    public static let shared = Aegis()
    
    // MARK: - Properties
    private var config: AegisConfig?
    private var writeKey: String?
    private var identityManager: IdentityManager?
    private var sessionManager: SessionManager?
    private var eventQueue: EventQueue?
    private var transport: Transport?
    private var cellSelector: CellSelector?
    private var remoteConfigManager: RemoteConfigManager?
    private var remoteConfig: RemoteConfig?
    // contextBuilder field removed — `ContextBuilder.buildContext()` is a
    // static call on the singleton class; no per-instance state needed.
    private var cartData: CartData?
    // SDK-side event-name governance — populated by ingestGovernanceHint
    // after the integrator runs the /v1/sdk/bootstrap handshake. Drops
    // novel event names locally once the org hits its plan cap so we
    // don't amplify CP /event-governance/check load. Grace-aware: skips
    // local drop when the server is inside its 7-day soft-cap window.
    // Parity with the web SDK v1.4.0.
    private let nameGovernor = NameGovernor()
    // SDK-side trait governance — parity with the web SDK v1.11.0.
    // Runs the same 5 ingestion guards the the server-side ingestion pipeline runs at
    // record_attribute_keys, so developers see warnings BEFORE the bad
    // data hits production.
    private let traitGovernor = TraitGovernor()

    /// E-commerce helper. Canonical 15-method tracker; parity with
    /// the web SDK EcommerceTracker. Methods + event names locked by
    /// the cross-SDK drift contract.
    public lazy var ecommerce: EcommerceTracker = EcommerceTracker(aegis: self)

    /// `Aegis.shared.user` namespace (Phase 4, web 1.13 parity). Typed
    /// PII + per-channel opt-in setters with pre-login buffering.
    /// Pinned by the cross-SDK drift contract.
    public lazy var user: AegisUser = AegisUser(aegis: self)

    /// Phase 4 consent (GDPR/CCPA categories). Default state per
    /// the cross-SDK drift contract.
    /// ATT denial → marketing=false (set via `applyATTOutcome`).
    /// Phase 4.5: when the host configures `AegisConfig.appGroupSuiteName`,
    /// consent persists to the shared App-Group UserDefaults so the
    /// NSE process can read it.
    public lazy var consent: ConsentManager = {
        if let suite = config?.appGroupSuiteName, let d = UserDefaults(suiteName: suite) {
            return ConsentManager(defaults: d)
        }
        return ConsentManager()
    }()

    /// Phase 4.5 plugin runtime — register Aegis-shipped plugins
    /// (Meta App Events bridge, etc.) or your own integrations.
    /// Plugins receive `onTrack` / `onIdentify` / `onScreen` /
    /// `onConsentChange` / `onReset` lifecycle hooks. Contract
    /// pinned by the cross-SDK drift contract.
    public lazy var plugins: PluginRegistry = PluginRegistry(aegis: self)

    private var isInitialized = false
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Initialize the Active Reach SDK
    /// - Parameters:
    ///   - writeKey: Your Aegis write key
    ///   - config: SDK configuration
    public func initialize(writeKey: String, config: AegisConfig = AegisConfig()) {
        guard !isInitialized else {
            print("[Active Reach] SDK already initialized")
            return
        }
        
        self.writeKey = writeKey
        self.config = config
        
        // Initialize core components
        identityManager = IdentityManager()
        sessionManager = SessionManager(timeout: config.sessionTimeout)
        // ContextBuilder.buildContext() is a static method — no instance
        // needed; the contextBuilder field is retained as nil for any
        // legacy nil-checks elsewhere in the file.

        // Multi-region cell selection — parity with the web SDK
        // Transport. When `cellEndpoints` is empty the selector is nil
        // and Transport falls back to `apiHost` (legacy single-host).
        if let endpoints = config.cellEndpoints, !endpoints.isEmpty {
            let entries = endpoints.compactMap { ep -> CellEndpointEntry? in
                guard let region = CellRegion(rawValue: ep.region) else { return nil }
                return CellEndpointEntry(region: region, url: ep.endpoint)
            }
            let preferred = config.preferredRegion.flatMap { CellRegion(rawValue: $0) }
            let selector = CellSelector(
                endpoints: entries,
                preferredRegion: preferred,
                autoRegionDetection: config.autoRegionDetection
            )
            DispatchQueue.global(qos: .utility).async { selector.select() }
            cellSelector = selector
        }

        transport = Transport(
            apiHost: config.apiHost,
            writeKey: writeKey,
            workspaceId: config.workspaceId,
            cellSelector: cellSelector
        )
        eventQueue = EventQueue(
            batchSize: config.batchSize,
            batchInterval: config.batchInterval,
            transport: transport!,
            encryptionEnabled: config.encryptLocalStorage
        )
        
        // Fetch remote configuration if enabled
        if config.enableRemoteConfig {
            remoteConfigManager = RemoteConfigManager(writeKey: writeKey, baseURL: config.apiHost)
            remoteConfigManager?.fetchConfig { [weak self] (remoteConfig: RemoteConfig?) in
                self?.applyRemoteConfig(remoteConfig)
            }
        }
        
        // Setup session tracking
        if config.autoSessionTracking {
            sessionManager?.startTracking { [weak self] event in
                self?.track(event.name, properties: event.properties)
            }
        }
        
        isInitialized = true
        
        if config.debugMode {
            print("[Active Reach] SDK initialized successfully")
            print("[Active Reach] Write Key: \(writeKey.prefix(8))...")
            print("[Active Reach] API Host: \(config.apiHost)")
        }
    }
    
    // MARK: - Tracking Methods
    
    /// Track a custom event
    /// - Parameters:
    ///   - eventName: Name of the event
    ///   - properties: Optional event properties
    public func track(_ eventName: String, properties: [String: Any]? = nil) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }

        // Check if event is blocked by remote config
        if let blockedEvents = config?.blockedEvents, blockedEvents.contains(eventName) {
            if config?.debugMode == true {
                print("[Active Reach] Event '\(eventName)' blocked by remote config")
            }
            return
        }

        // Phase 4 consent gate. Meta events bypass — same rule as the
        // NameGovernor.
        if !eventName.hasPrefix("aegis.client.") && !consent.shouldEmit(eventName) {
            if config?.debugMode == true {
                print("[Active Reach] Event '\(eventName)' blocked by consent (\(consent.categoryForEvent(eventName).rawValue) denied)")
            }
            return
        }

        // SDK-side event-name governance — drops novel names once the
        // org hits its plan cap. Fails open when no hint is loaded, and
        // skips the drop during the server's 7-day soft-cap grace window.
        // Meta events ("aegis.client.*") bypass the governor so telemetry
        // stays open even during a cap-exhaustion storm.
        if !eventName.hasPrefix("aegis.client.") {
            guard nameGovernor.shouldSend(eventName) else { return }
        }

        let event = AegisEvent(
            type: .track,
            name: eventName,
            properties: properties,
            userId: identityManager?.userId,
            anonymousId: identityManager?.anonymousId ?? "",
            sessionId: sessionManager?.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )

        // Phase 4.5 Meta Pixel companion — record the latest messageId
        // (only under marketing consent) so callers can dedup
        // client-side Meta Pixel events with the server-side CAPI
        // event via `lastEventId(eventName)`.
        if consent.has(.marketing) {
            MetaPixelCompanion.shared.recordEvent(eventName, messageId: event.messageId)
        }

        // Phase 4.5 plugin runtime — give every registered plugin a
        // chance to suppress or mutate before enqueue.
        var emittedEvent: AegisEvent? = event
        for plugin in plugins.allPlugins() {
            switch plugin.onTrack(event: emittedEvent!) {
            case .suppress: emittedEvent = nil
            case .pass: break
            case .replace(let mutated): emittedEvent = mutated
            }
            if emittedEvent == nil { break }
        }
        guard let toEnqueue = emittedEvent else {
            if config?.debugMode == true {
                print("[Active Reach] Event '\(eventName)' suppressed by plugin")
            }
            return
        }
        eventQueue?.enqueue(toEnqueue)

        if config?.debugMode == true {
            print("[Active Reach] Tracked event: \(eventName)")
        }
    }

    /// Phase 4.5 Meta Pixel companion. Returns the messageId of the
    /// most recent `track(eventName)` call (only events tracked
    /// while marketing consent was granted). Pass to a tenant's
    /// client-side Meta Pixel for client+server CAPI dedup:
    ///
    ///   let eventId = Aegis.shared.lastEventId("order_completed")
    ///   metaPixel.track("Purchase", payload, ["eventID": eventId])
    public func lastEventId(_ eventName: String) -> String? {
        MetaPixelCompanion.shared.lastEventId(eventName)
    }
    
    /// Identify a user
    /// - Parameters:
    ///   - userId: Unique user identifier
    ///   - traits: Optional user traits
    public func identify(_ userId: String, traits: [String: Any]? = nil) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }
        
        identityManager?.identify(userId: userId)

        // Trait governance — sanitise + warn BEFORE the wire write.
        let sanitised = traitGovernor
            .process(traits, workspaceId: config?.workspaceId)
            .sanitized

        let event = AegisEvent(
            type: .identify,
            name: "identify",
            properties: sanitised,
            userId: userId,
            anonymousId: identityManager?.anonymousId ?? "",
            sessionId: sessionManager?.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )

        eventQueue?.enqueue(event)

        if config?.debugMode == true {
            print("[Active Reach] Identified user: \(userId)")
        }
    }

    /// Perform the /v1/sdk/bootstrap handshake. On success returns the
    /// `BootstrapResult` AND applies the contained `EventGovernanceHint`
    /// to the NameGovernor automatically — callers don't need a separate
    /// `ingestGovernanceHint` call.
    ///
    /// Parity with the web SDK's `bootstrap()` export. Wired by Phase 1
    /// per the cross-SDK parity matrix.
    public func bootstrap(
        completion: @escaping (Swift.Result<BootstrapResult, BootstrapError>) -> Void
    ) {
        guard isInitialized, let writeKey = writeKey, let config = config else {
            completion(.failure(.sdkNotInitialised))
            return
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let request = BootstrapRequest(
            writeKey: writeKey,
            bundleIdentifier: bundleId,
            userAgent: AegisVersion.userAgent
        )
        Bootstrap.perform(apiHost: config.apiHost, request: request) { [weak self] result in
            if case .success(let res) = result {
                if let hint = res.eventGovernance {
                    self?.nameGovernor.ingestHint(hint)
                }
            }
            completion(result)
        }
    }
    
    /// Track a screen view
    /// - Parameters:
    ///   - screenName: Name of the screen
    ///   - properties: Optional screen properties
    public func screen(_ screenName: String, properties: [String: Any]? = nil) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }
        
        var props = properties ?? [:]
        props["screen_name"] = screenName
        
        let event = AegisEvent(
            type: .screen,
            name: "Screen Viewed",
            properties: props,
            userId: identityManager?.userId,
            anonymousId: identityManager?.anonymousId ?? "",
            sessionId: sessionManager?.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )
        
        eventQueue?.enqueue(event)
        
        if config?.debugMode == true {
            print("[Active Reach] Tracked screen: \(screenName)")
        }
    }
    
    /// Group a user
    /// - Parameters:
    ///   - groupId: Unique group identifier
    ///   - traits: Optional group traits
    public func group(_ groupId: String, traits: [String: Any]? = nil) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }

        let sanitised = traitGovernor
            .process(traits, workspaceId: config?.workspaceId)
            .sanitized

        let event = AegisEvent(
            type: .group,
            name: "group",
            properties: sanitised,
            userId: identityManager?.userId,
            anonymousId: identityManager?.anonymousId ?? "",
            groupId: groupId,
            sessionId: sessionManager?.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )
        
        eventQueue?.enqueue(event)
        
        if config?.debugMode == true {
            print("[Active Reach] Grouped user with: \(groupId)")
        }
    }
    
    /// Alias a user ID
    /// - Parameter newUserId: New user ID to alias
    public func alias(_ newUserId: String) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }
        
        let previousId = identityManager?.userId ?? identityManager?.anonymousId ?? ""
        
        let event = AegisEvent(
            type: .alias,
            name: "alias",
            properties: [
                "previous_id": previousId,
                "new_id": newUserId
            ],
            userId: newUserId,
            anonymousId: identityManager?.anonymousId ?? "",
            sessionId: sessionManager?.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )
        
        eventQueue?.enqueue(event)
        identityManager?.identify(userId: newUserId)
        
        if config?.debugMode == true {
            print("[Active Reach] Aliased user from \(previousId) to \(newUserId)")
        }
    }
    
    /// Reset user identity (typically on logout)
    public func reset() {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }
        
        identityManager?.reset()
        sessionManager?.reset()
        
        if config?.debugMode == true {
            print("[Active Reach] Reset user identity")
        }
    }
    
    /// Flush all queued events immediately
    public func flush() {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }

        // Emit coalesced governance-drop telemetry BEFORE flushing so the
        // meta event rides in the same batch as the rest.
        emitGovernanceDropMeta()
        eventQueue?.flush()

        if config?.debugMode == true {
            print("[Active Reach] Flushed event queue")
        }
    }

    // MARK: - Event Governance

    /// Ingest the event-governance hint returned from `/v1/sdk/bootstrap`.
    ///
    /// Integrators run `bootstrap()` themselves (parity with web SDK) and
    /// pass the resulting hint here so the SDK can self-throttle novel
    /// event names before they hit the gateway. Passing nil disables
    /// governance (Enterprise plan / outage fail-open). Safe to call
    /// before `initialize()` — the hint is stored and applied as soon as
    /// init completes.
    public func ingestGovernanceHint(_ hint: EventGovernanceHint?) {
        nameGovernor.ingestHint(hint)
        if config?.debugMode == true {
            if let h = hint {
                print("[Active Reach] Governance hint ingested: k=\(h.k) m=\(h.m) remaining=\(String(describing: h.remainingNewNames)) grace=\(h.graceActive)")
            } else {
                print("[Active Reach] Governance hint cleared (fail-open)")
            }
        }
    }

    /// Drain the client-side drop counter and queue a coalesced meta
    /// event. Called automatically during `flush()` so ops dashboards see
    /// novel-name amplification patterns in near-real-time.
    private func emitGovernanceDropMeta() {
        guard isInitialized,
              let session = sessionManager,
              let identity = identityManager
        else { return }
        guard let report = nameGovernor.drainDropReport() else { return }

        // Cap the sample list — a runaway loop could produce thousands of
        // names; ship the top 10 for diagnostics and the total for counting.
        let samples = report.events
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { (key: $0.key, value: $0.value) }

        let properties: [String: Any] = [
            "dropped_count": report.total,
            "distinct_names": report.events.count,
            "sample_names": samples.map { ["name": $0.key, "count": $0.value] },
            "window_start": ISO8601DateFormatter().string(from: report.since),
            "window_end": ISO8601DateFormatter().string(from: Date()),
        ]

        let event = AegisEvent(
            type: .track,
            name: "aegis.client.name_governor_dropped",
            properties: properties,
            userId: identity.userId,
            anonymousId: identity.anonymousId,
            sessionId: session.sessionId,
            context: ContextBuilder.buildContext(),
            timestamp: Date()
        )
        eventQueue?.enqueue(event)
    }
    
    // MARK: - Getters
    
    /// Get the current anonymous ID
    public func getAnonymousId() -> String? {
        return identityManager?.anonymousId
    }
    
    /// Get the current user ID
    public func getUserId() -> String? {
        return identityManager?.userId
    }
    
    /// Get the current session ID
    public func getSessionId() -> String? {
        return sessionManager?.sessionId
    }
    
    /// Enable or disable debug mode
    public func setDebugMode(_ enabled: Bool) {
        config?.debugMode = enabled
    }
    
    // MARK: - Cart Tracking (Spin Wheel Integration)
    
    /// Set cart data for cart recovery
    /// - Parameter cart: Cart data containing items, total, and currency
    public func setCartData(_ cart: CartData) {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return
        }
        
        self.cartData = cart
        
        if config?.debugMode == true {
            print("[Active Reach] Cart data updated: \(cart.cartId), total: \(cart.cartTotal) \(cart.cartCurrency)")
        }
    }
    
    /// Get current cart data
    public func getCartData() -> CartData? {
        return cartData
    }
    
    /// Clear cart data (typically after purchase or cart abandonment)
    public func clearCartData() {
        cartData = nil
        
        if config?.debugMode == true {
            print("[Active Reach] Cart data cleared")
        }
    }
    
    /// Submit spin wheel with phone/email capture
    /// - Parameters:
    ///   - phone: User's phone number (E.164 format recommended)
    ///   - email: User's email address (optional)
    ///   - name: User's name (optional)
    ///   - completion: Callback with prize data or error
    public func submitSpinWheel(
        phone: String?,
        email: String?,
        name: String?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard isInitialized else {
            completion(.failure(NSError(domain: "ai.aegis.sdk", code: -1, userInfo: [NSLocalizedDescriptionKey: "SDK not initialized"])))
            return
        }
        
        guard phone != nil || email != nil else {
            completion(.failure(NSError(domain: "ai.aegis.sdk", code: -2, userInfo: [NSLocalizedDescriptionKey: "Either phone or email is required"])))
            return
        }
        
        let cart = cartData ?? CartData(
            cartId: "ios_\(Int(Date().timeIntervalSince1970))",
            cartTotal: 0,
            cartCurrency: "USD",
            cartItems: []
        )
        
        var payload: [String: Any] = [
            "cart_id": cart.cartId,
            "cart_total": cart.cartTotal,
            "cart_currency": cart.cartCurrency,
            "cart_items": cart.cartItems.map { item in
                [
                    "product_id": item.productId,
                    "product_name": item.productName,
                    "quantity": item.quantity,
                    "price": item.price
                ]
            },
            "platform": "ios",
            "device_type": UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "mobile",
            "session_id": sessionManager?.sessionId ?? "",
            "anonymous_id": identityManager?.anonymousId ?? ""
        ]
        
        if let phone = phone { payload["phone"] = phone }
        if let email = email { payload["email"] = email }
        if let name = name { payload["name"] = name }
        if let cartToken = cart.cartToken { payload["cart_token"] = cartToken }
        if let cartUrl = cart.cartUrl { payload["cart_url"] = cartUrl }
        
        let geoRegion = detectGeoRegion()
        payload["geo_region"] = geoRegion
        
        guard let url = URL(string: "\(config?.apiHost ?? "https://api.active-reach.ai")/v1/widgets/spin-wheel/submit") else {
            completion(.failure(NSError(domain: "ai.aegis.sdk", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        
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
                completion(.failure(NSError(domain: "ai.aegis.sdk", code: -4, userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(NSError(domain: "ai.aegis.sdk", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
        
        if config?.debugMode == true {
            print("[Active Reach] Submitted spin wheel for cart: \(cart.cartId)")
        }
    }
    
    /// Trigger exit intent manually (typically called when app enters background with active cart)
    /// - Returns: True if exit intent was triggered, false if no cart data available
    @discardableResult
    public func triggerExitIntent() -> Bool {
        guard isInitialized else {
            print("[Active Reach] SDK not initialized. Call initialize() first.")
            return false
        }
        
        guard cartData != nil else {
            if config?.debugMode == true {
                print("[Active Reach] No cart data available for exit intent")
            }
            return false
        }
        
        track("exit_intent_triggered", properties: [
            "cart_id": cartData?.cartId ?? "",
            "cart_total": cartData?.cartTotal ?? 0,
            "cart_currency": cartData?.cartCurrency ?? "USD",
            "trigger_source": "manual"
        ])
        
        if config?.debugMode == true {
            print("[Active Reach] Exit intent triggered for cart: \(cartData?.cartId ?? "")")
        }
        
        return true
    }
    
    // MARK: - Private Methods
    
    private func detectGeoRegion() -> String {
        let timezone = TimeZone.current.identifier
        
        if timezone.contains("America") {
            if timezone.contains("Argentina") || timezone.contains("Brazil") || timezone.contains("Chile") {
                return "latin_america"
            }
            return "north_america"
        } else if timezone.contains("Europe") {
            return "europe"
        } else if timezone.contains("Asia/Kolkata") || timezone.contains("Asia/Calcutta") {
            return "india"
        } else if timezone.contains("Asia") {
            if timezone.contains("Dubai") || timezone.contains("Riyadh") {
                return "middle_east"
            }
            return "southeast_asia"
        } else if timezone.contains("Australia") || timezone.contains("Pacific/Auckland") {
            return "oceania"
        }
        
        return "north_america"
    }
    
    private func applyRemoteConfig(_ sdkConfig: RemoteConfig?) {
        guard let sdkConfig = sdkConfig else { return }
        
        // Apply remote configuration
        config?.batchSize = sdkConfig.batchSize
        config?.batchInterval = TimeInterval(sdkConfig.flushInterval / 1000)
        config?.blockedEvents = sdkConfig.blockEvents
        
        // Update event queue with new settings
        eventQueue?.updateBatchSize(sdkConfig.batchSize)
        eventQueue?.updateBatchInterval(TimeInterval(sdkConfig.flushInterval / 1000))
        
        if config?.debugMode == true {
            print("[Active Reach] Applied remote config: batch=\(sdkConfig.batchSize), interval=\(sdkConfig.flushInterval)ms")
        }
    }
}
