// NameGovernor — client-side event-name cap enforcement for iOS.
// Parity port of the web SDK source.
//
// The governor consumes an `EventGovernanceHint` from the bootstrap
// response and decides whether to let a `track()` call proceed to the
// network or drop it locally.
//
// Why this exists (same rationale as web SDK): without it, an app that
// calls `track("new_btn_\(Date())")` in a render loop would pass the
// local rate-limiter on burst, force the gateway to ask CP for a verdict
// on every unique name, and amplify the CP /event-governance/check load
// quadratically in the number of sessions firing the same bug. The bloom
// filter gives the SDK enough information to drop novel names locally
// once the org hits its cap, collapsing the amplification to zero.
//
// Design constraints — identical to the web SDK:
//   • FAIL-OPEN — missing hint (Enterprise, bootstrap outage) lets every
//     name through. Gateway is the authoritative cap.
//   • FALSE-POSITIVE-SAFE — if the bloom says "known" for a name that
//     isn't actually registered, we send to gateway and the gateway's
//     exact check catches it.
//   • LOCAL-MEMO — a novel name that has already charged
//     `remainingNewNames` in this session must NOT charge again within
//     the same hint TTL. Without this, firing the same new name 50 times
//     would drain 50 from the counter and block every OTHER legitimate
//     novel name.
//   • GRACE-AWARE — when the server reports it's in the 7-day grace
//     window, SDK skips the local drop entirely so we don't enforce
//     harder than the server.

import Foundation

public struct DropReport {
    public let events: [String: Int]
    public let total: Int
    public let since: Date
}

public final class NameGovernor {
    private let queue = DispatchQueue(label: "ai.aegis.governance.name-governor")
    private let supportedAlgo = "mmh3_x86_32_km"

    private var bloom: BloomFilter?
    private var remainingNewNames: Int = Int.max
    private var graceActive: Bool = false
    private var localNovelNames: Set<String> = []
    private var droppedSinceLastReport: [String: Int] = [:]
    private var reportWindowStart: Date = Date()
    private var hasWarnedThisSession: Bool = false

    public init() {}

    /// Ingest a freshly-bootstrapped hint. Call on every successful
    /// bootstrap. Passing nil disables governance (fail-open).
    public func ingestHint(_ hint: EventGovernanceHint?) {
        queue.sync {
            guard let hint = hint, hint.bloomAlgo == supportedAlgo else {
                bloom = nil
                remainingNewNames = .max
                graceActive = false
                localNovelNames.removeAll()
                return
            }

            do {
                bloom = try BloomFilter.fromBase64(
                    hint.bloomB64,
                    params: BloomFilterParams(
                        m: hint.m, k: hint.k,
                        seedA: hint.seedA, seedB: hint.seedB
                    )
                )
            } catch {
                // Malformed hint — fail open. Logged by the caller.
                bloom = nil
            }

            remainingNewNames = hint.remainingNewNames ?? .max
            graceActive = hint.graceActive
            localNovelNames.removeAll()
        }
    }

    /// Decide whether a `track()` call should proceed.
    /// Returns true  = send to network (rate-limiter still runs after).
    /// Returns false = drop locally; caller should return early.
    public func shouldSend(_ eventName: String) -> Bool {
        return queue.sync {
            // No hint = unlimited plan or fail-open. Send everything.
            guard let bloom = bloom else { return true }

            // 7-day soft-cap grace window — server accepts novel names.
            if graceActive { return true }

            // Known name — send.
            if bloom.has(eventName) { return true }

            // Already charged in this session — send.
            if localNovelNames.contains(eventName) { return true }

            // Novel name, within headroom — charge once, send.
            if remainingNewNames > 0 {
                localNovelNames.insert(eventName)
                remainingNewNames -= 1
                return true
            }

            // Novel + over cap → drop locally, record for telemetry.
            let prev = droppedSinceLastReport[eventName] ?? 0
            droppedSinceLastReport[eventName] = prev + 1

            if !hasWarnedThisSession {
                hasWarnedThisSession = true
                #if DEBUG
                print(
                    "[Active Reach] Event-name cap reached — \"\(eventName)\" " +
                    "dropped locally. Upgrade your plan or remove " +
                    "dynamically-generated event names."
                )
                #endif
            }
            return false
        }
    }

    /// Snapshot + reset the dropped-names counter. Called by the batch
    /// flush path so the gateway gets visibility into client-side drops
    /// for ops dashboards.
    public func drainDropReport() -> DropReport? {
        return queue.sync {
            guard !droppedSinceLastReport.isEmpty else { return nil }

            let events = droppedSinceLastReport
            let total = events.values.reduce(0, +)
            let since = reportWindowStart

            droppedSinceLastReport.removeAll()
            reportWindowStart = Date()

            return DropReport(events: events, total: total, since: since)
        }
    }

    // Test-only accessors — mirror the TS _debugState() pattern.
    public struct DebugState {
        public let hasBloom: Bool
        public let remaining: Int
        public let localNovel: Int
        public let graceActive: Bool
    }
    public func debugState() -> DebugState {
        return queue.sync {
            DebugState(
                hasBloom: bloom != nil,
                remaining: remainingNewNames,
                localNovel: localNovelNames.count,
                graceActive: graceActive
            )
        }
    }
}
