// Bloom filter — wire-compatible with the Python builder in
// the server-side governance service
// and the JS decoder in the web SDK source.
//
// SDK-side is QUERY-ONLY. The filter is built server-side from the org's
// registered event-name set, base64-encoded, and shipped to the mobile
// SDK on `/v1/sdk/bootstrap`. SDK reads once, uses it to gate `track()`
// calls, and discards on next bootstrap.
//
// Wire format:
//   • m bits of storage, represented as m/8 bytes, base64-encoded.
//   • Bit `i` is at byte `i >> 3`, bitmask `1 << (i & 7)` — LSB-first.
//   • m MUST be a power of two — allows `idx & (m-1)` modulo.
//   • k hash functions synthesised via Kirsch-Mitzenmacher from two
//     MurmurHash3 x86-32 hashes with seeds (seedA, seedB):
//         h_i(x) = (h1(x) + i * h2(x)) mod m

import Foundation

public struct BloomFilterParams {
    public let m: Int       // bits in the filter (must be power of 2)
    public let k: Int       // number of hash functions
    public let seedA: UInt32
    public let seedB: UInt32

    public init(m: Int, k: Int, seedA: UInt32, seedB: UInt32) {
        self.m = m
        self.k = k
        self.seedA = seedA
        self.seedB = seedB
    }
}

public enum BloomFilterError: Error {
    case mNotPowerOfTwo(Int)
    case sizeMismatch(expected: Int, actual: Int)
    case invalidBase64
}

public struct BloomFilter {
    private let buf: [UInt8]
    private let params: BloomFilterParams
    private let mask: UInt32

    public init(buf: [UInt8], params: BloomFilterParams) throws {
        if (params.m & (params.m - 1)) != 0 {
            throw BloomFilterError.mNotPowerOfTwo(params.m)
        }
        let expected = params.m >> 3
        if buf.count != expected {
            throw BloomFilterError.sizeMismatch(expected: expected, actual: buf.count)
        }
        self.buf = buf
        self.params = params
        self.mask = UInt32(params.m - 1)
    }

    /// Build from the wire format (base64 string + explicit params).
    public static func fromBase64(_ bloomB64: String, params: BloomFilterParams) throws -> BloomFilter {
        guard let data = Data(base64Encoded: bloomB64) else {
            throw BloomFilterError.invalidBase64
        }
        return try BloomFilter(buf: [UInt8](data), params: params)
    }

    /// Returns true if `name` is probably in the set — possibly with the
    /// filter's configured false-positive rate. FALSE is always authoritative.
    ///
    /// FP here means: SDK thinks a name is already registered when it isn't.
    /// That costs one wasted server round-trip (gateway does the exact
    /// check and catches it) — strictly safer than a false-negative, which
    /// could leak a novel name past the SDK.
    public func has(_ name: String) -> Bool {
        let h1 = Murmur3.x86_32(name, seed: params.seedA)
        let h2 = Murmur3.x86_32(name, seed: params.seedB)

        for i in 0..<params.k {
            // Overflow-aware 32-bit arithmetic — we can't mask only at
            // the end because h1 + i*h2 can wrap past 2^32 when i*h2 is
            // large. Swift's `&*` / `&+` give us the same behavior as
            // `(h1 + i*h2) >>> 0` in JS.
            let combined = h1 &+ (UInt32(truncatingIfNeeded: i) &* h2)
            let idx = Int(combined & mask)
            let bit = buf[idx >> 3] & (1 << (idx & 7))
            if bit == 0 {
                return false
            }
        }
        return true
    }
}
