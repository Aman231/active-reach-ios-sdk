import Foundation

/// Canonical cell regions. Mirrors the web SDK source
/// CellRegion union + the cross-SDK drift contract.
public enum CellRegion: String {
    case usEast = "us-east"
    case usWest = "us-west"
    case euCentral = "eu-central"
    case apSouth = "ap-south"
    case apSoutheast = "ap-southeast"
}

/// Multi-region cell endpoint. Identical wire-shape to the web SDK
/// `CellEndpoint`. `healthy` is a `var` because health checks flip it
/// asynchronously.
public final class CellEndpointEntry {
    public let region: CellRegion
    public let url: String
    public let priority: Int
    public var healthy: Bool

    public init(region: CellRegion, url: String, priority: Int = 100, healthy: Bool = true) {
        self.region = region
        self.url = url
        self.priority = priority
        self.healthy = healthy
    }
}

/// Canonical multi-region cell-selection algorithm. Pinned by
/// the cross-SDK drift contract.
///
/// Order of operations:
///   1. If `preferredRegion` is set AND that endpoint is healthy → pick it.
///   2. Else if `autoRegionDetection` → probe every healthy /health and
///      pick lowest latency.
///   3. Else → sort healthy endpoints by priority asc, pick first.
///   4. Else → nil (caller fails closed; no events transmitted).
public final class CellSelector {

    private let endpoints: [CellEndpointEntry]
    private let preferredRegion: CellRegion?
    private let autoRegionDetection: Bool
    private let session: URLSession
    private let lock = NSLock()
    private var activeEndpoint: CellEndpointEntry?

    public init(
        endpoints: [CellEndpointEntry],
        preferredRegion: CellRegion? = nil,
        autoRegionDetection: Bool = true,
        session: URLSession = .shared
    ) {
        self.endpoints = endpoints
        self.preferredRegion = preferredRegion
        self.autoRegionDetection = autoRegionDetection
        self.session = session
    }

    /// Run selection synchronously (latency probes are dispatched on a
    /// concurrent group; total wall-clock bounded by the longest probe ~2s).
    @discardableResult
    public func select() -> CellEndpointEntry? {
        guard !endpoints.isEmpty else {
            store(nil)
            return nil
        }

        if let pref = preferredRegion,
           let match = endpoints.first(where: { $0.region == pref && $0.healthy }) {
            store(match)
            return match
        }

        let picked: CellEndpointEntry?
        if autoRegionDetection {
            picked = detectLowestLatency() ?? selectByPriority()
        } else {
            picked = selectByPriority()
        }
        store(picked)
        return picked
    }

    public func active() -> CellEndpointEntry? {
        lock.lock(); defer { lock.unlock() }
        return activeEndpoint
    }

    /// Run health checks against every endpoint. Flip the `healthy`
    /// flag. If the active endpoint turned unhealthy, re-run selection.
    @discardableResult
    public func runHealthChecks() -> CellEndpointEntry? {
        for ep in endpoints { ep.healthy = probeHealthy(ep) }
        if let current = active(), current.healthy { return current }
        return select()
    }

    // MARK: - Provisional region fallback

    /// Provisional region mapping from the device timezone. Used when no
    /// cellEndpoints are configured. The bootstrap response then returns
    /// canonical endpoints. Mirrors
    /// the cross-SDK drift contract
    /// tz_to_region_fallback.
    public static func guessRegionFromTimezone(_ tz: TimeZone = .current) -> CellRegion {
        let id = tz.identifier
        if id.contains("Asia/Kolkata") || id.contains("Asia/Calcutta") { return .apSouth }
        if id.contains("Asia/Dubai") || id.contains("Asia/Riyadh") { return .apSouth }
        if id.hasPrefix("Asia/") { return .apSoutheast }
        if id.hasPrefix("Europe/") || id.hasPrefix("Africa/") { return .euCentral }
        if id == "America/Los_Angeles" || id == "America/Denver"
            || id == "America/Phoenix" || id == "America/Vancouver" { return .usWest }
        if id.hasPrefix("America/") { return .usEast }
        if id.hasPrefix("Australia/") || id.hasPrefix("Pacific/") { return .apSoutheast }
        return .usEast
    }

    // MARK: - Private

    private func store(_ endpoint: CellEndpointEntry?) {
        lock.lock(); defer { lock.unlock() }
        activeEndpoint = endpoint
    }

    private func selectByPriority() -> CellEndpointEntry? {
        endpoints.filter { $0.healthy }.min { $0.priority < $1.priority }
    }

    private func detectLowestLatency() -> CellEndpointEntry? {
        let healthy = endpoints.filter { $0.healthy }
        guard !healthy.isEmpty else { return nil }

        let group = DispatchGroup()
        let resultsLock = NSLock()
        var results: [(CellEndpointEntry, TimeInterval)] = []
        let probeQueue = DispatchQueue(label: "ai.aegis.cell-probe", attributes: .concurrent)

        for ep in healthy {
            group.enter()
            probeQueue.async {
                let latency = self.measureLatency(ep)
                resultsLock.lock()
                results.append((ep, latency))
                resultsLock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 3.0)
        return results.filter { $0.1 != .infinity }.min { $0.1 < $1.1 }?.0
    }

    private func measureLatency(_ ep: CellEndpointEntry) -> TimeInterval {
        guard let url = URL(string: "\(ep.url)/health") else { return .infinity }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2.0
        let start = Date()
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        session.dataTask(with: req) { _, response, _ in
            ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)
        return ok ? Date().timeIntervalSince(start) : .infinity
    }

    private func probeHealthy(_ ep: CellEndpointEntry) -> Bool {
        guard let url = URL(string: "\(ep.url)/health") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3.0
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        session.dataTask(with: req) { _, response, _ in
            ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) < 400
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 3.5)
        return ok
    }
}
