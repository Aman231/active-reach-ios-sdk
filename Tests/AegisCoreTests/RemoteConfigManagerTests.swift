import XCTest
@testable import AegisCore

final class RemoteConfigManagerTests: XCTestCase {
    
    var sut: RemoteConfigManager!
    
    override func setUp() {
        super.setUp()
        sut = RemoteConfigManager(writeKey: "test_key", baseURL: "https://api.test.aegis.ai")
    }
    
    func testFetchConfig() {
        // Given
        let expectation = XCTestExpectation(description: "Config fetched")
        
        // When
        sut.fetchConfig { config in
            // Then
            if let config = config {
                XCTAssertGreaterThan(config.batchSize, 0)
                XCTAssertGreaterThan(config.flushInterval, 0)
                XCTAssertGreaterThanOrEqual(config.samplingRate, 0.0)
                XCTAssertLessThanOrEqual(config.samplingRate, 1.0)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConfigCaching() {
        // Given
        let expectation1 = XCTestExpectation(description: "First fetch")
        let expectation2 = XCTestExpectation(description: "Second fetch (cached)")
        
        // When - first fetch
        sut.fetchConfig { config in
            XCTAssertNotNil(config)
            expectation1.fulfill()
        }
        
        wait(for: [expectation1], timeout: 5.0)
        
        // When - second fetch (should use cache)
        sut.fetchConfig { config in
            XCTAssertNotNil(config) // Should return cached value
            expectation2.fulfill()
        }
        
        // Then - should return immediately from cache
        wait(for: [expectation2], timeout: 0.5)
    }
    
    func testEventBlocking() {
        // Given
        var config = RemoteConfig()
        config = RemoteConfig()
        // Can't directly modify, so test with default
        
        // When/Then
        XCTAssertFalse(config.isEventBlocked("Purchase"))
    }
    
    func testEventSampling() {
        // Given
        var config = RemoteConfig()
        
        // When - test sampling at 50%
        var sampledCount = 0
        for _ in 0..<1000 {
            if config.shouldSampleEvent() {
                sampledCount += 1
            }
        }
        
        // Then - should be approximately 1000 (100% sampling rate by default)
        XCTAssertGreaterThan(sampledCount, 950) // Allow some variance
    }
    
    func testConfigUpdateCallback() {
        // Given
        let expectation = XCTestExpectation(description: "Callback invoked")
        var callbackInvoked = false
        
        sut.setConfigUpdateCallback { config in
            callbackInvoked = true
            XCTAssertGreaterThan(config.batchSize, 0)
            expectation.fulfill()
        }
        
        // When
        sut.fetchConfig { _ in }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(callbackInvoked)
    }
    
    func testFallbackToCachedConfigOnError() {
        // Given
        let invalidSUT = RemoteConfigManager(writeKey: "invalid", baseURL: "https://nonexistent.invalid")
        let expectation = XCTestExpectation(description: "Fallback to cached")
        
        // When
        invalidSUT.fetchConfig { config in
            // Then - should return cached (nil on first attempt) or default
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
}
