// Event-governance tests for iOS.
//
// Two concerns covered:
//   1. Hash parity — Swift MurmurHash3 x86-32 must match the pinned
//      vectors in the shared cross-SDK contract (same file
//      consumed by web-sdk tests and the CP pytest). Any drift in the
//      Swift port fails CI and prevents shipping.
//   2. NameGovernor behavior — including the `localNovelNames` fix that
//      stops repeated novel-name calls from double-decrementing the
//      counter, and the grace-active fail-open path.

import XCTest
@testable import AegisCore

final class GovernanceTests: XCTestCase {

    // MARK: - Fixture

    private struct TestVector: Decodable {
        let input: String
        let mmh3_s0: UInt32
        let mmh3_s1: UInt32
    }
    private struct Fixture: Decodable {
        let algo: String
        let seeds: Seeds
        let encoding: String
        let vectors: [TestVector]
    }
    private struct Seeds: Decodable {
        let s0: UInt32
        let s1: UInt32
    }

    private func loadFixture() throws -> Fixture {
        guard let url = Bundle.module.url(
            forResource: "bloom-test-vectors",
            withExtension: "json"
        ) else {
            XCTFail("bloom-test-vectors.json not found in test bundle")
            fatalError("missing fixture")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    // MARK: - 1. Hash parity

    func testFixtureUsesExpectedAlgo() throws {
        let fx = try loadFixture()
        XCTAssertEqual(fx.algo, "mmh3_x86_32_km")
        XCTAssertEqual(fx.seeds.s0, 0)
        XCTAssertEqual(fx.seeds.s1, 1)
        XCTAssertEqual(fx.encoding, "utf-8")
    }

    func testMurmur3Seed0MatchesFixture() throws {
        let fx = try loadFixture()
        for v in fx.vectors {
            let got = Murmur3.x86_32(v.input, seed: 0)
            XCTAssertEqual(
                got, v.mmh3_s0,
                "mmh3(s0) drift for \"\(v.input)\" — got \(got) expected \(v.mmh3_s0). Web SDK + CP will disagree — do NOT ship."
            )
        }
    }

    func testMurmur3Seed1MatchesFixture() throws {
        let fx = try loadFixture()
        for v in fx.vectors {
            let got = Murmur3.x86_32(v.input, seed: 1)
            XCTAssertEqual(got, v.mmh3_s1, "mmh3(s1) drift for \"\(v.input)\"")
        }
    }

    // MARK: - 2. Bloom filter round-trip

    /// Build a bloom wire payload in Swift the same way the Python/JS side
    /// does, so we can round-trip through the decoder. Real cross-language
    /// parity is covered by the hash-parity test above.
    private func buildPayload(_ names: [String], m: Int, k: Int) -> String {
        var buf = [UInt8](repeating: 0, count: m >> 3)
        let mask = UInt32(m - 1)
        for name in names {
            let h1 = Murmur3.x86_32(name, seed: 0)
            let h2 = Murmur3.x86_32(name, seed: 1)
            for i in 0..<k {
                let combined = h1 &+ (UInt32(truncatingIfNeeded: i) &* h2)
                let idx = Int(combined & mask)
                buf[idx >> 3] |= 1 << (idx & 7)
            }
        }
        return Data(buf).base64EncodedString()
    }

    func testBloomReturnsTrueForEveryAddedName() throws {
        let names = ["cart_item_added", "order_placed", "page_view"]
        let m = 1024, k = 7
        let bloom = try BloomFilter.fromBase64(
            buildPayload(names, m: m, k: k),
            params: BloomFilterParams(m: m, k: k, seedA: 0, seedB: 1)
        )
        for n in names {
            XCTAssertTrue(bloom.has(n), "\(n) missing from bloom")
        }
    }

    func testBloomReturnsFalseForAbsentName() throws {
        let m = 1024, k = 7
        let bloom = try BloomFilter.fromBase64(
            buildPayload(["cart_item_added", "order_placed"], m: m, k: k),
            params: BloomFilterParams(m: m, k: k, seedA: 0, seedB: 1)
        )
        XCTAssertFalse(bloom.has("definitely_not_in_the_set_12345"))
    }

    func testBloomRejectsNonPowerOfTwoM() {
        let buf = Data(repeating: 0, count: 1000 / 8).base64EncodedString()
        XCTAssertThrowsError(
            try BloomFilter.fromBase64(
                buf,
                params: BloomFilterParams(m: 1000, k: 3, seedA: 0, seedB: 1)
            )
        )
    }

    // MARK: - 3. NameGovernor behavior

    private func hintFor(_ knownNames: [String], remaining: Int?, grace: Bool = false) -> EventGovernanceHint {
        let m = 1024, k = 7
        let bloomB64 = buildPayload(knownNames, m: m, k: k)
        return EventGovernanceHint(
            bloomAlgo: "mmh3_x86_32_km",
            seedA: 0, seedB: 1,
            k: k, m: m,
            bloomB64: bloomB64,
            remainingNewNames: remaining,
            graceActive: grace,
            ttlSeconds: 300
        )
    }

    func testFailsOpenWhenNoHint() {
        let g = NameGovernor()
        XCTAssertTrue(g.shouldSend("anything"))
        XCTAssertTrue(g.shouldSend("even_this"))
    }

    func testAllowsKnownNames() {
        let g = NameGovernor()
        g.ingestHint(hintFor(["order_placed", "cart_item_added"], remaining: 3))
        XCTAssertTrue(g.shouldSend("order_placed"))
        XCTAssertTrue(g.shouldSend("cart_item_added"))
    }

    func testAllowsNovelNamesWithinHeadroom() {
        let g = NameGovernor()
        g.ingestHint(hintFor(["order_placed"], remaining: 2))
        XCTAssertTrue(g.shouldSend("first_novel"))
        XCTAssertTrue(g.shouldSend("second_novel"))
        XCTAssertFalse(g.shouldSend("third_novel"))
    }

    func testDropsNovelNamesOnceCapExhausted() {
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 0))
        XCTAssertFalse(g.shouldSend("anything_novel"))
    }

    func testLocalNovelNamesFixPreventsDoubleDecrement() {
        // 1 headroom slot — firing same novel name 50 times should consume
        // exactly 1 slot, leaving the OTHER novel name allowed afterwards.
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 2))

        for _ in 0..<50 {
            XCTAssertTrue(g.shouldSend("spammed_novel_name"))
        }
        XCTAssertTrue(g.shouldSend("a_different_novel_name"))
        // Both slots now consumed → next distinct novel name is dropped.
        XCTAssertFalse(g.shouldSend("yet_another_novel_name"))
    }

    func testGraceActiveMakesShouldSendAlwaysTrue() {
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 0, grace: true))

        XCTAssertTrue(g.shouldSend("novel_1"))
        XCTAssertTrue(g.shouldSend("novel_2"))
        XCTAssertTrue(g.shouldSend("novel_3"))

        XCTAssertTrue(g.debugState().graceActive)
    }

    func testGraceInactiveRevertsToHardDrop() {
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 0, grace: false))
        XCTAssertFalse(g.shouldSend("novel_x"))
    }

    func testDrainDropReportReturnsCoalescedCountsThenClears() {
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 0))
        _ = g.shouldSend("alpha")
        _ = g.shouldSend("alpha")
        _ = g.shouldSend("beta")

        let report1 = g.drainDropReport()
        XCTAssertNotNil(report1)
        XCTAssertEqual(report1?.total, 3)
        XCTAssertEqual(report1?.events["alpha"], 2)
        XCTAssertEqual(report1?.events["beta"], 1)

        XCTAssertNil(g.drainDropReport())
    }

    func testDisablesGovernanceForUnknownAlgoTag() {
        let g = NameGovernor()
        var hint = hintFor(["x"], remaining: 0)
        hint = EventGovernanceHint(
            bloomAlgo: "some_future_algo_v2",
            seedA: hint.seedA, seedB: hint.seedB,
            k: hint.k, m: hint.m, bloomB64: hint.bloomB64,
            remainingNewNames: hint.remainingNewNames,
            graceActive: hint.graceActive,
            ttlSeconds: hint.ttlSeconds
        )
        g.ingestHint(hint)
        XCTAssertTrue(g.shouldSend("anything"))
    }

    func testResetsLocalNovelNamesOnHintRefresh() {
        let g = NameGovernor()
        g.ingestHint(hintFor([], remaining: 1))
        XCTAssertTrue(g.shouldSend("first_session_novel"))

        g.ingestHint(hintFor([], remaining: 1))
        XCTAssertTrue(g.shouldSend("first_session_novel"))
        XCTAssertFalse(g.shouldSend("second_session_novel"))
    }
}
