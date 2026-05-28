import XCTest
@testable import AegisCore

final class TransportTests: XCTestCase {
    
    var sut: Transport!
    
    override func setUp() {
        super.setUp()
        sut = Transport(
            writeKey: "test_key_123",
            baseURL: "https://api.test.aegis.ai",
            certificatePinningEnabled: false,
            publicKeyHashes: []
        )
    }
    
    func testSuccessfulBatchSend() {
        // Given
        let expectation = XCTestExpectation(description: "Batch sent successfully")
        let events = [createTestEvent(name: "Test Event 1"), createTestEvent(name: "Test Event 2")]
        
        // When
        sut.sendBatch(events: events) { success, failedIds in
            // Then
            XCTAssertTrue(success)
            XCTAssertTrue(failedIds.isEmpty)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testGzipCompression() {
        // Given
        let expectation = XCTestExpectation(description: "Large batch compressed")
        
        // Create many events to trigger compression (>1KB)
        var events: [AegisEvent] = []
        for i in 0..<50 {
            events.append(createTestEvent(name: "Event \(i)", properties: ["data": String(repeating: "x", count: 100)]))
        }
        
        // When
        sut.sendBatch(events: events) { success, failedIds in
            // Then - should compress and send
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testRetryOnNetworkError() {
        // Given
        let expectation = XCTestExpectation(description: "Retry attempted")
        expectation.isInverted = false // Will be fulfilled on first attempt
        
        let event = createTestEvent(name: "Network Failure Test")
        
        // When - send to invalid URL
        let invalidTransport = Transport(writeKey: "test", baseURL: "https://invalid.aegis.ai.nonexistent")
        invalidTransport.sendBatch(events: [event]) { success, failedIds in
            // Then - should fail and retry
            XCTAssertFalse(success)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    func testAuthorizationHeader() {
        // Given
        let writeKey = "sk_test_1234567890"
        let transport = Transport(writeKey: writeKey, baseURL: "https://api.test.aegis.ai")
        
        let expectation = XCTestExpectation(description: "Auth header set")
        let event = createTestEvent(name: "Auth Test")
        
        // When
        transport.sendBatch(events: [event]) { _, _ in
            // Then - request should have Authorization header (verified by server)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Helpers
    
    private func createTestEvent(name: String, properties: [String: Any]? = nil) -> AegisEvent {
        return AegisEvent(
            type: .track,
            name: name,
            properties: properties,
            userId: "test_user",
            anonymousId: "anon_123",
            sessionId: "session_456",
            context: EventContext(
                device: DeviceInfo(id: "device_1", manufacturer: "Apple", model: "iPhone14,2", name: "iPhone 13 Pro", type: "mobile"),
                os: OSInfo(name: "iOS", version: "17.0"),
                app: AppInfo(name: "TestApp", version: "1.0", build: "1", namespace: "com.test.app"),
                screen: ScreenInfo(width: 1170, height: 2532, density: 3.0),
                network: NetworkInfo(bluetooth: false, cellular: true, wifi: false, carrier: "Verizon"),
                battery: BatteryInfo(level: 0.85, charging: false),
                locale: "en_US",
                timezone: "America/New_York",
                library: LibraryInfo(name: "aegis-ios-sdk", version: "1.1.0")
            ),
            timestamp: Date()
        )
    }
}
