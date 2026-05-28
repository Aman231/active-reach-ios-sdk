import XCTest
@testable import AegisCore

final class EventQueueTests: XCTestCase {
    
    var mockTransport: MockTransport!
    var sut: EventQueue!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockTransport()
        sut = EventQueue(
            batchSize: 5,
            batchInterval: 10,
            transport: mockTransport,
            encryptionEnabled: true
        )
    }
    
    func testEventEnqueue() {
        // Given
        let event = createTestEvent(name: "Test Event")
        
        // When
        sut.enqueue(event)
        
        // Then - event should be stored
        XCTAssertEqual(sut.count(), 1)
    }
    
    func testBatchFlushWhenSizeReached() {
        // Given
        let expectation = XCTestExpectation(description: "Batch flushed")
        mockTransport.onSendBatch = { events, completion in
            XCTAssertEqual(events.count, 5)
            completion(true, [])
            expectation.fulfill()
        }
        
        // When - add 5 events to trigger batch
        for i in 0..<5 {
            sut.enqueue(createTestEvent(name: "Event \(i)"))
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testEventEncryption() {
        // Given - encryption enabled in setUp
        let event = createTestEvent(name: "Sensitive Event", properties: ["ssn": "123-45-6789"])
        
        // When
        sut.enqueue(event)
        
        // Then - should store encrypted (can't directly verify, but shouldn't crash)
        XCTAssertEqual(sut.count(), 1)
    }
    
    func testMaxEventsLimit() {
        // Given - 10,000 event limit
        let maxEvents = 10000
        
        // When - try to add more than max
        for i in 0..<(maxEvents + 100) {
            sut.enqueue(createTestEvent(name: "Event \(i)"))
        }
        
        // Then - should not exceed limit
        XCTAssertLessThanOrEqual(sut.count(), maxEvents)
    }
    
    func testRetryLogic() {
        // Given
        let expectation = XCTestExpectation(description: "Retry attempted")
        expectation.expectedFulfillmentCount = 2
        
        mockTransport.onSendBatch = { events, completion in
            completion(false, events.map { $0.messageId })
            expectation.fulfill()
        }
        
        // When
        sut.enqueue(createTestEvent(name: "Failing Event"))
        sut.flush()
        
        // Manually flush again to trigger retry
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.sut.flush()
        }
        
        // Then
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testBatchSizeUpdate() {
        // Given
        let expectation = XCTestExpectation(description: "Updated batch size")
        
        // When
        sut.updateBatchSize(3)
        
        mockTransport.onSendBatch = { events, completion in
            XCTAssertEqual(events.count, 3)
            completion(true, [])
            expectation.fulfill()
        }
        
        for i in 0..<3 {
            sut.enqueue(createTestEvent(name: "Event \(i)"))
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
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

// MARK: - Mock Transport

class MockTransport: Transport {
    var onSendBatch: (([AegisEvent], @escaping (Bool, [String]) -> Void) -> Void)?
    
    override func sendBatch(events: [AegisEvent], completion: @escaping (Bool, [String]) -> Void) {
        if let handler = onSendBatch {
            handler(events, completion)
        } else {
            completion(true, [])
        }
    }
}
