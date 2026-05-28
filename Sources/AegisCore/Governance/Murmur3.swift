// MurmurHash3 x86-32 — deterministic, byte-identical with Python `mmh3.hash`
// and the TypeScript `murmurhash3_x86_32` in the web SDK source.
//
// This is the authoritative cross-language hash for the event-governance
// bloom filter. Any drift between Python, JS, and Swift produces silent
// FP-rate spikes in prod, so this implementation is pinned by the shared
// fixture at the shared cross-SDK contract (checked in CI).
//
// Contract:
//   • Input is a Swift string; it is UTF-8 encoded before hashing.
//   • Output is an unsigned 32-bit integer (0 .. 2^32-1).
//   • Matches `mmh3.hash(s.encode('utf-8'), seed=seed, signed=False)`.
//
// Reference: Austin Appleby, MurmurHash3 (public domain).
//
// Implementation notes:
//   • Swift's native `&*`, `&+`, `&-` overflow operators give us correct
//     32-bit arithmetic without needing explicit masks after each step.
//   • We intentionally DO NOT use the Swift `hashValue` / `Hasher` API —
//     those are randomly salted per process and not stable across
//     platforms. Murmur3 is deterministic by design.

import Foundation

public enum Murmur3 {

    private static let c1: UInt32 = 0xcc9e2d51
    private static let c2: UInt32 = 0x1b873593

    /// Compute MurmurHash3 x86-32 of a UTF-8 encoded string.
    /// - Parameters:
    ///   - input: The string to hash.
    ///   - seed: 32-bit unsigned seed (matches mmh3.hash seed arg).
    /// - Returns: Unsigned 32-bit integer hash.
    public static func x86_32(_ input: String, seed: UInt32 = 0) -> UInt32 {
        return x86_32(Data(input.utf8), seed: seed)
    }

    /// Compute MurmurHash3 x86-32 over a byte buffer directly.
    /// Exposed for callers that already have UTF-8 bytes and want to skip
    /// the encode step (e.g., internal bloom-hash paths).
    public static func x86_32(_ bytes: Data, seed: UInt32 = 0) -> UInt32 {
        let len = bytes.count
        let nBlocks = len / 4

        var h1: UInt32 = seed

        // Body — consume 4-byte blocks in little-endian order.
        for i in 0..<nBlocks {
            let offset = i * 4
            var k1: UInt32 =
                UInt32(bytes[offset]) |
                (UInt32(bytes[offset + 1]) << 8) |
                (UInt32(bytes[offset + 2]) << 16) |
                (UInt32(bytes[offset + 3]) << 24)

            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2

            h1 ^= k1
            h1 = (h1 << 13) | (h1 >> 19)
            h1 = (h1 &* 5) &+ 0xe6546b64
        }

        // Tail — up to 3 trailing bytes.
        let tailStart = nBlocks * 4
        let tailLen = len - tailStart
        var k1: UInt32 = 0
        if tailLen == 3 { k1 ^= UInt32(bytes[tailStart + 2]) << 16 }
        if tailLen >= 2 { k1 ^= UInt32(bytes[tailStart + 1]) << 8 }
        if tailLen >= 1 {
            k1 ^= UInt32(bytes[tailStart])
            k1 = k1 &* c1
            k1 = (k1 << 15) | (k1 >> 17)
            k1 = k1 &* c2
            h1 ^= k1
        }

        // Finalization — fmix32 avalanche.
        h1 ^= UInt32(truncatingIfNeeded: len)
        h1 ^= h1 >> 16
        h1 = h1 &* 0x85ebca6b
        h1 ^= h1 >> 13
        h1 = h1 &* 0xc2b2ae35
        h1 ^= h1 >> 16

        return h1
    }
}
