import Foundation
import os.log

/// TraitGovernor — client-side guards for trait writes. Parity port of
/// the web SDK source (web SDK ≥1.11.0).
///
/// Runs the same 5 ingestion guards the the server-side ingestion pipeline enforces in
/// data_governance.ingestion_guards.GuardResult, so the SDK can warn
/// developers about problematic keys/values BEFORE the network write.
///
/// Verdict codes here MUST match the backend `GuardResult.verdict` +
/// `ingestion_dlq.verdict` DB CHECK + the FE `IngestionDLQVerdict`
/// union. Four-surface drift protection. Source-of-truth fixture:
/// the cross-SDK drift contract.
public final class TraitGovernor {

    public enum Verdict: String {
        case badKeyFormat = "bad_key_format"
        case valueTooLong = "value_too_long"
        case badDateFormat = "bad_date_format"
        case nameTooLong = "name_too_long"
        case reservedPrefix = "reserved_prefix"
    }

    public struct Drop {
        public let originalKey: String
        public let verdict: Verdict
        public let reason: String
    }

    public struct Result {
        public let sanitized: [String: Any]
        public let drops: [Drop]
    }

    private static let warnCap = 3
    private static let softValueCap = 512
    private static let hardValueCap = 10_000

    private static let reservedPrefixes: [String] = [
        "system.", "user.", "loyalty.", "review.", "cart.",
        "checkout.", "product.", "pos.", "bill.", "feedback.",
        "chat.", "delivery.", "event.", "$", "_",
    ]

    private static let dateKeyHints: Set<String> = [
        "at", "on", "date", "time", "timestamp", "dob", "birthday",
        "joined", "expired", "expires", "created", "updated",
        "started", "ended",
    ]

    private static let camelBoundary1 = try! NSRegularExpression(pattern: "(.)([A-Z][a-z]+)")
    private static let camelBoundary2 = try! NSRegularExpression(pattern: "([a-z0-9])([A-Z])")
    private static let nonSnake = try! NSRegularExpression(pattern: "[\\s\\-.]+")
    private static let dupeUnderscore = try! NSRegularExpression(pattern: "_+")
    private static let iso8601 = try! NSRegularExpression(
        pattern: "^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?)?$"
    )

    private let warnLock = NSLock()
    private var warnCounts: [String: [Verdict: Int]] = [:]
    private let logger = OSLog(subsystem: "ai.active-reach.sdk", category: "TraitGovernor")

    public init() {}

    /// Apply all guards to a traits dictionary. Returns the sanitised
    /// payload to send + a list of drops/modifications.
    ///
    /// - Parameter workspaceId: Scope warnings per-workspace so an
    ///   agency user switching brands doesn't burn the warning budget
    ///   cross-workspace.
    public func process(_ traits: [String: Any]?, workspaceId: String? = nil) -> Result {
        guard let traits = traits else { return Result(sanitized: [:], drops: []) }

        var sanitized: [String: Any] = [:]
        var drops: [Drop] = []

        for (rawKey, rawValue) in traits {
            // 1. Reserved prefix on the ORIGINAL key. Order matters —
            //    "system.foo" normalises to "system_foo" and bypasses
            //    the check otherwise.
            if let prefix = Self.startsWithReserved(rawKey) {
                drops.append(Drop(
                    originalKey: rawKey,
                    verdict: .reservedPrefix,
                    reason: "key uses reserved namespace \"\(prefix)\""
                ))
                continue
            }

            // 2. Normalise key casing.
            guard let normalised = Self.normaliseKey(rawKey) else {
                drops.append(Drop(
                    originalKey: rawKey,
                    verdict: .badKeyFormat,
                    reason: "key reduced to empty after normalisation"
                ))
                continue
            }

            // 3. Re-check reserved on normalised form.
            if Self.startsWithReserved(normalised) != nil {
                drops.append(Drop(
                    originalKey: rawKey,
                    verdict: .reservedPrefix,
                    reason: "normalised key \"\(normalised)\" still uses a reserved namespace"
                ))
                continue
            }

            // 4. Value-side guards.
            var value: Any = rawValue

            if let s = value as? String {
                if s.count > Self.hardValueCap {
                    drops.append(Drop(
                        originalKey: rawKey,
                        verdict: .valueTooLong,
                        reason: "value length \(s.count) exceeds hard cap \(Self.hardValueCap)"
                    ))
                    continue
                }
                if s.count > Self.softValueCap {
                    drops.append(Drop(
                        originalKey: rawKey,
                        verdict: .valueTooLong,
                        reason: "value truncated from \(s.count) to \(Self.softValueCap) chars"
                    ))
                    value = String(s.prefix(Self.softValueCap))
                }
            }

            // 4b. Date normalisation for date-keyed string values.
            if Self.looksLikeDateKey(normalised), let s = value as? String {
                guard let epochMs = Self.parseDateValue(s) else {
                    drops.append(Drop(
                        originalKey: rawKey,
                        verdict: .badDateFormat,
                        reason: "value \"\(s)\" on date-keyed field \"\(normalised)\" didn't parse as ISO-8601 / epoch"
                    ))
                    continue
                }
                value = epochMs
            }

            sanitized[normalised] = value
        }

        for drop in drops { maybeWarn(workspaceId: workspaceId, drop: drop) }
        return Result(sanitized: sanitized, drops: drops)
    }

    // MARK: - Private

    private func maybeWarn(workspaceId: String?, drop: Drop) {
        let key = workspaceId ?? "__no_workspace__"
        warnLock.lock()
        defer { warnLock.unlock() }
        var perVerdict = warnCounts[key] ?? [:]
        let count = perVerdict[drop.verdict] ?? 0
        guard count < Self.warnCap else { return }
        perVerdict[drop.verdict] = count + 1
        warnCounts[key] = perVerdict
        os_log(
            "[Active Reach SDK] trait %{public}@: %{public}@ (original key: %{public}@). Backend will reject; fix the SDK call to silence this warning.",
            log: logger,
            type: .default,
            drop.verdict.rawValue, drop.reason, drop.originalKey
        )
    }

    private static func startsWithReserved(_ key: String) -> String? {
        let lower = key.lowercased()
        return reservedPrefixes.first(where: { lower.hasPrefix($0) })
    }

    private static func normaliseKey(_ key: String) -> String? {
        guard !key.isEmpty else { return nil }
        var s = key as NSString
        let range1 = NSRange(location: 0, length: s.length)
        s = camelBoundary1.stringByReplacingMatches(in: s as String, options: [], range: range1, withTemplate: "$1_$2") as NSString
        let range2 = NSRange(location: 0, length: s.length)
        s = camelBoundary2.stringByReplacingMatches(in: s as String, options: [], range: range2, withTemplate: "$1_$2") as NSString
        let range3 = NSRange(location: 0, length: s.length)
        s = nonSnake.stringByReplacingMatches(in: s as String, options: [], range: range3, withTemplate: "_") as NSString
        var result = (s as String).lowercased()
        let range4 = NSRange(location: 0, length: result.utf16.count)
        result = dupeUnderscore.stringByReplacingMatches(in: result, options: [], range: range4, withTemplate: "_")
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return result.isEmpty ? nil : result
    }

    private static func looksLikeDateKey(_ key: String) -> Bool {
        let parts = key.lowercased().components(separatedBy: CharacterSet(charactersIn: "_-. \t"))
        for p in parts {
            if dateKeyHints.contains(p) { return true }
        }
        return false
    }

    private static func parseDateValue(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let nsRange = NSRange(location: 0, length: trimmed.utf16.count)
        if iso8601.firstMatch(in: trimmed, options: [], range: nsRange) != nil {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm'Z'",
                "yyyy-MM-dd'T'HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm",
                "yyyy-MM-dd",
            ]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            for fmt in formats {
                formatter.dateFormat = fmt
                if let d = formatter.date(from: trimmed) {
                    return Int64(d.timeIntervalSince1970 * 1000)
                }
            }
        }

        if let n = Double(trimmed) {
            return n < 1e11 ? Int64(n * 1000) : Int64(n)
        }
        return nil
    }
}
