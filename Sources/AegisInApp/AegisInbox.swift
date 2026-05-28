import Foundation

/// AegisInbox — persistent message-center client for iOS.
///
/// Mirrors the TypeScript `AegisInbox` contract (the web SDK/src/inbox/).
/// Fetches the contact's inbox page from `/v1/in-app/inbox` at startup,
/// persists a cached copy in UserDefaults so the drawer paints before
/// the network round-trip completes, and exposes read/dismiss mutations.
///
/// SCAFFOLD NOTE: Compiles + mirrors the wire contract, not yet
/// exercised on a physical iOS device. Production integration needs:
///   1. Wire into a SwiftUI view + assert inbox renders after cold start
///   2. Verify the UserDefaults cache survives app termination
///   3. Confirm mark-read optimistic update matches server state after
///      a background refresh
public class AegisInbox {

    public static let shared = AegisInbox()

    public struct Entry: Codable, Equatable {
        public let id: String
        public let source: String
        public let campaignId: String?
        public let title: String
        public let body: String
        public let mediaUrl: String?
        public let ctaUrl: String?
        public let read: Bool
        public let readAt: String?
        public let createdAt: String?
        public let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id, source, title, body, read
            case campaignId = "campaign_id"
            case mediaUrl = "media_url"
            case ctaUrl = "cta_url"
            case readAt = "read_at"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    private struct InboxResponse: Codable {
        let unreadCount: Int
        let entries: [Entry]
        let cursor: String?

        enum CodingKeys: String, CodingKey {
            case entries, cursor
            case unreadCount = "unread_count"
        }
    }

    public typealias Listener = (_ unreadCount: Int, _ entries: [Entry]) -> Void

    private let cacheKey = "ai.aegis.inbox.cache"
    private let unreadKey = "ai.aegis.inbox.unread"

    private var apiHost: String = "https://api.active-reach.ai"
    private var writeKey: String?
    private var contactId: String?
    private var organizationId: String?
    private var propertyId: String?

    private var cachedEntries: [Entry] = []
    private var cachedUnread: Int = 0
    private var listeners: [UUID: Listener] = [:]

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    /// Configure the client. Hydrates from UserDefaults immediately, then
    /// fires a background refresh — identical to the Android contract.
    public func initialize(
        apiHost: String,
        writeKey: String,
        contactId: String?,
        organizationId: String?,
        propertyId: String?
    ) {
        self.apiHost = apiHost.hasSuffix("/") ? String(apiHost.dropLast()) : apiHost
        self.writeKey = writeKey
        self.contactId = contactId
        self.organizationId = organizationId
        self.propertyId = propertyId
        loadCache()
        notifyListeners()
        refresh()
    }

    @discardableResult
    public func addListener(_ listener: @escaping Listener) -> () -> Void {
        let token = UUID()
        listeners[token] = listener
        listener(cachedUnread, cachedEntries)
        return { [weak self] in
            self?.listeners.removeValue(forKey: token)
        }
    }

    public func getEntries() -> [Entry] { cachedEntries }
    public func getUnreadCount() -> Int { cachedUnread }

    public func refresh() {
        guard let contact = contactId,
              let property = propertyId,
              let key = writeKey,
              let url = URL(string: "\(apiHost)/v1/in-app/inbox") else { return }

        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "X-Aegis-Write-Key")
        req.setValue(contact, forHTTPHeaderField: "X-Contact-ID")
        req.setValue(property, forHTTPHeaderField: "X-Property-Id")
        if let org = organizationId { req.setValue(org, forHTTPHeaderField: "X-Organization-ID") }

        session.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self = self,
                  let http = resp as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  let data = data else { return }
            guard let parsed = try? JSONDecoder().decode(InboxResponse.self, from: data) else { return }
            DispatchQueue.main.async {
                self.cachedEntries = parsed.entries
                self.cachedUnread = parsed.unreadCount
                self.saveCache()
                self.notifyListeners()
            }
        }.resume()
    }

    public func markRead(_ messageId: String) {
        postAction(path: "/v1/in-app/inbox/\(messageId)/read")
        cachedEntries = cachedEntries.map { entry in
            if entry.id == messageId {
                return Entry(
                    id: entry.id, source: entry.source, campaignId: entry.campaignId,
                    title: entry.title, body: entry.body, mediaUrl: entry.mediaUrl,
                    ctaUrl: entry.ctaUrl, read: true, readAt: ISO8601DateFormatter().string(from: Date()),
                    createdAt: entry.createdAt, expiresAt: entry.expiresAt
                )
            }
            return entry
        }
        cachedUnread = cachedEntries.filter { !$0.read }.count
        saveCache()
        notifyListeners()
    }

    public func dismiss(_ messageId: String) {
        postAction(path: "/v1/in-app/inbox/\(messageId)/dismiss")
        cachedEntries.removeAll { $0.id == messageId }
        cachedUnread = cachedEntries.filter { !$0.read }.count
        saveCache()
        notifyListeners()
    }

    public func updateContactId(_ contactId: String) {
        if self.contactId == contactId { return }
        self.contactId = contactId
        refresh()
    }

    public func destroy() {
        listeners.removeAll()
    }

    // MARK: - internals

    private func loadCache() {
        let defaults = UserDefaults.standard
        cachedUnread = defaults.integer(forKey: unreadKey)
        if let data = defaults.data(forKey: cacheKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            cachedEntries = decoded
        }
    }

    private func saveCache() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(cachedEntries) {
            defaults.set(data, forKey: cacheKey)
        }
        defaults.set(cachedUnread, forKey: unreadKey)
    }

    private func notifyListeners() {
        listeners.values.forEach { $0(cachedUnread, cachedEntries) }
    }

    private func postAction(path: String) {
        guard let key = writeKey,
              let url = URL(string: "\(apiHost)\(path)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "X-Aegis-Write-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let contact = contactId { req.setValue(contact, forHTTPHeaderField: "X-Contact-ID") }
        if let org = organizationId { req.setValue(org, forHTTPHeaderField: "X-Organization-ID") }
        if let property = propertyId { req.setValue(property, forHTTPHeaderField: "X-Property-Id") }
        session.dataTask(with: req) { _, _, _ in }.resume()
    }
}
