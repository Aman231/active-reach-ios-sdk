// Shape of the hint delivered by `/v1/sdk/bootstrap`. Mirrors the Python
// pydantic model at the server-side schema
// and the TypeScript interface at the web SDK source.

import Foundation

public struct EventGovernanceHint: Codable {
    public let bloomAlgo: String
    public let seedA: UInt32
    public let seedB: UInt32
    public let k: Int
    public let m: Int
    public let bloomB64: String
    public let remainingNewNames: Int?
    /// When true, the server is in its 7-day soft-cap grace window: it
    /// accepts novel event names past the cap. SDK must NOT drop locally
    /// in this mode — doing so would enforce harder than the server.
    public let graceActive: Bool
    public let ttlSeconds: Int

    enum CodingKeys: String, CodingKey {
        case bloomAlgo = "bloom_algo"
        case seedA = "seed_a"
        case seedB = "seed_b"
        case k
        case m
        case bloomB64 = "bloom_b64"
        case remainingNewNames = "remaining_new_names"
        case graceActive = "grace_active"
        case ttlSeconds = "ttl_seconds"
    }

    public init(
        bloomAlgo: String,
        seedA: UInt32,
        seedB: UInt32,
        k: Int,
        m: Int,
        bloomB64: String,
        remainingNewNames: Int?,
        graceActive: Bool = false,
        ttlSeconds: Int = 300
    ) {
        self.bloomAlgo = bloomAlgo
        self.seedA = seedA
        self.seedB = seedB
        self.k = k
        self.m = m
        self.bloomB64 = bloomB64
        self.remainingNewNames = remainingNewNames
        self.graceActive = graceActive
        self.ttlSeconds = ttlSeconds
    }

    /// Decoder with default for grace_active — older server builds may
    /// not set this field, and a missing value should mean "no grace".
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.bloomAlgo = try c.decode(String.self, forKey: .bloomAlgo)
        self.seedA = try c.decode(UInt32.self, forKey: .seedA)
        self.seedB = try c.decode(UInt32.self, forKey: .seedB)
        self.k = try c.decode(Int.self, forKey: .k)
        self.m = try c.decode(Int.self, forKey: .m)
        self.bloomB64 = try c.decode(String.self, forKey: .bloomB64)
        self.remainingNewNames = try c.decodeIfPresent(Int.self, forKey: .remainingNewNames)
        self.graceActive = try c.decodeIfPresent(Bool.self, forKey: .graceActive) ?? false
        self.ttlSeconds = try c.decodeIfPresent(Int.self, forKey: .ttlSeconds) ?? 300
    }
}
