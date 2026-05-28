import Foundation

/// PrefetchBundleClient — single-round-trip init resolver for in-app state.
///
/// iOS parity for the TypeScript `PrefetchBundleClient` (the web SDK/
/// src/core/prefetch-bundle-client.ts). Fetches `/v1/sdk/prefetch-bundle`
/// once at init and on a 5-minute ETag poll; armed campaigns + inbox
/// first-page land in memory so trigger-time rendering is zero-latency.
///
/// SCAFFOLD NOTE: Compiles + matches the wire contract. Not yet wired
/// into AegisInAppManager, not exercised on device. Production use
/// requires integration tests + hooking AegisInApp's trigger evaluator
/// into `getCampaigns()`.
public class PrefetchBundleClient {

    public struct BundleCampaign: Codable {
        public let id: String
        public let type: String
        public let subType: String?
        public let title: String
        public let body: String
        public let backgroundColor: String?
        public let textColor: String?
        public let actionUrl: String?
        public let priority: Int
        public let interactiveConfig: [String: AnyCodable]?
        public let assignedVariantId: String?
        public let inboxEnabled: Bool?

        enum CodingKeys: String, CodingKey {
            case id, type, title, body, priority
            case subType = "sub_type"
            case backgroundColor = "background_color"
            case textColor = "text_color"
            case actionUrl = "action_url"
            case interactiveConfig = "interactive_config"
            case assignedVariantId = "assigned_variant_id"
            case inboxEnabled = "inbox_enabled"
        }
    }

    public struct BundleInboxEntry: Codable {
        public let id: String
        public let title: String
        public let body: String
        public let campaignId: String?
        public let read: Bool
        public let createdAt: String?
        public let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id, title, body, read
            case campaignId = "campaign_id"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    public struct BundleInbox: Codable {
        public let unreadCount: Int
        public let page: [BundleInboxEntry]
        public let cursor: String?

        enum CodingKeys: String, CodingKey {
            case page, cursor
            case unreadCount = "unread_count"
        }
    }

    public struct Bundle: Codable {
        public let etag: String
        public let generatedAt: String
        public let ttlSeconds: Int
        public let invalidationTopic: String
        public let campaigns: [BundleCampaign]
        public let inbox: BundleInbox

        enum CodingKeys: String, CodingKey {
            case etag, campaigns, inbox
            case generatedAt = "generated_at"
            case ttlSeconds = "ttl_seconds"
            case invalidationTopic = "invalidation_topic"
        }
    }

    public typealias Listener = (Bundle) -> Void

    private let apiHost: String
    private let writeKey: String
    private var contactId: String?
    private var userId: String?
    private var organizationId: String?
    private var propertyId: String?
    private let pollIntervalSec: TimeInterval

    private var currentBundle: Bundle?
    private var currentETag: String?
    private var listeners: [UUID: Listener] = [:]
    private var pollTimer: Timer?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    public init(
        apiHost: String,
        writeKey: String,
        contactId: String? = nil,
        userId: String? = nil,
        organizationId: String? = nil,
        propertyId: String? = nil,
        pollIntervalSec: TimeInterval = 300
    ) {
        self.apiHost = apiHost.hasSuffix("/") ? String(apiHost.dropLast()) : apiHost
        self.writeKey = writeKey
        self.contactId = contactId
        self.userId = userId
        self.organizationId = organizationId
        self.propertyId = propertyId
        self.pollIntervalSec = pollIntervalSec
    }

    public func start() {
        fetch()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSec, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    public func getBundle() -> Bundle? { currentBundle }
    public func getCampaigns() -> [BundleCampaign] { currentBundle?.campaigns ?? [] }
    public func getInbox() -> BundleInbox { currentBundle?.inbox ?? BundleInbox(unreadCount: 0, page: [], cursor: nil) }

    @discardableResult
    public func addListener(_ listener: @escaping Listener) -> () -> Void {
        let token = UUID()
        listeners[token] = listener
        if let bundle = currentBundle { listener(bundle) }
        return { [weak self] in self?.listeners.removeValue(forKey: token) }
    }

    public func updateIdentity(
        contactId: String? = nil,
        userId: String? = nil,
        organizationId: String? = nil,
        propertyId: String? = nil
    ) {
        var changed = false
        if let v = contactId, v != self.contactId { self.contactId = v; changed = true }
        if let v = userId, v != self.userId { self.userId = v; changed = true }
        if let v = organizationId, v != self.organizationId { self.organizationId = v; changed = true }
        if let v = propertyId, v != self.propertyId { self.propertyId = v; changed = true }
        if changed {
            currentETag = nil
            fetch()
        }
    }

    public func refresh() { fetch() }

    public func destroy() {
        stop()
        listeners.removeAll()
    }

    // MARK: - internals

    private func fetch() {
        guard let url = URL(string: "\(apiHost)/v1/sdk/prefetch-bundle") else { return }
        var req = URLRequest(url: url)
        req.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        if let v = contactId { req.setValue(v, forHTTPHeaderField: "X-Contact-ID") }
        if let v = userId { req.setValue(v, forHTTPHeaderField: "X-User-ID") }
        if let v = organizationId { req.setValue(v, forHTTPHeaderField: "X-Organization-ID") }
        if let v = propertyId { req.setValue(v, forHTTPHeaderField: "X-Property-Id") }
        if let tag = currentETag { req.setValue(tag, forHTTPHeaderField: "If-None-Match") }

        session.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self = self, let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 304 { return }
            guard 200..<300 ~= http.statusCode, let data = data else { return }
            guard let parsed = try? JSONDecoder().decode(Bundle.self, from: data) else { return }
            DispatchQueue.main.async {
                self.currentBundle = parsed
                self.currentETag = parsed.etag
                self.listeners.values.forEach { $0(parsed) }
            }
        }.resume()
    }
}

/// Minimal type-erased Codable for JSON "any" values in interactive_config.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = NSNull(); return }
        if let v = try? c.decode(Bool.self) { self.value = v; return }
        if let v = try? c.decode(Int.self) { self.value = v; return }
        if let v = try? c.decode(Double.self) { self.value = v; return }
        if let v = try? c.decode(String.self) { self.value = v; return }
        if let v = try? c.decode([AnyCodable].self) { self.value = v.map { $0.value }; return }
        if let v = try? c.decode([String: AnyCodable].self) {
            self.value = v.mapValues { $0.value }; return
        }
        self.value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [Any]: try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try c.encode(v.mapValues { AnyCodable($0) })
        default: try c.encodeNil()
        }
    }
}
