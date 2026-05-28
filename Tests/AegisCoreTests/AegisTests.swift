import XCTest
@testable import AegisCore

final class AegisTests: XCTestCase {
    
    var sut: Aegis!
    
    override func setUp() {
        super.setUp()
        sut = Aegis.shared
    }
    
    override func tearDown() {
        sut.reset()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSDKInitialization() {
        // Given
        let writeKey = "test_write_key_123"
        let config = AegisConfig(debugMode: true)
        
        // When
        sut.initialize(writeKey: writeKey, config: config)
        
        // Then
        XCTAssertNotNil(sut.getAnonymousId())
        XCTAssertNil(sut.getUserId())
        XCTAssertNotNil(sut.getSessionId())
    }
    
    func testDoubleInitializationPrevented() {
        // Given
        let writeKey = "test_write_key_123"
        sut.initialize(writeKey: writeKey)
        
        // When & Then
        // Should not crash or throw
        sut.initialize(writeKey: "another_key")
    }
    
    // MARK: - Identity Tests
    
    func testIdentifyUser() {
        // Given
        sut.initialize(writeKey: "test_key")
        let userId = "user_123"
        let traits: [String: Any] = ["email": "test@example.com", "name": "Test User"]
        
        // When
        sut.identify(userId, traits: traits)
        
        // Then
        XCTAssertEqual(sut.getUserId(), userId)
        XCTAssertNotNil(sut.getAnonymousId())
    }
    
    func testResetIdentity() {
        // Given
        sut.initialize(writeKey: "test_key")
        sut.identify("user_123")
        let firstAnonymousId = sut.getAnonymousId()
        
        // When
        sut.reset()
        
        // Then
        XCTAssertNil(sut.getUserId())
        XCTAssertNotEqual(sut.getAnonymousId(), firstAnonymousId)
    }
    
    func testAliasUser() {
        // Given
        sut.initialize(writeKey: "test_key")
        sut.identify("old_user_id")
        
        // When
        sut.alias("new_user_id")
        
        // Then
        XCTAssertEqual(sut.getUserId(), "new_user_id")
    }
    
    // MARK: - Tracking Tests
    
    func testTrackEvent() {
        // Given
        sut.initialize(writeKey: "test_key")
        let eventName = "Purchase Completed"
        let properties: [String: Any] = [
            "product_id": "prod_123",
            "price": 29.99,
            "currency": "USD"
        ]
        
        // When & Then
        // Should not crash
        sut.track(eventName, properties: properties)
    }
    
    func testScreenTracking() {
        // Given
        sut.initialize(writeKey: "test_key")
        let screenName = "Home Screen"
        let properties: [String: Any] = ["previous_screen": "Login"]
        
        // When & Then
        // Should not crash
        sut.screen(screenName, properties: properties)
    }
    
    func testGroupTracking() {
        // Given
        sut.initialize(writeKey: "test_key")
        let groupId = "company_123"
        let traits: [String: Any] = ["name": "Acme Corp", "plan": "enterprise"]
        
        // When & Then
        // Should not crash
        sut.group(groupId, traits: traits)
    }
    
    // MARK: - Configuration Tests
    
    func testDebugModeToggle() {
        // Given
        sut.initialize(writeKey: "test_key")
        
        // When
        sut.setDebugMode(true)
        
        // Then
        // Should not crash and should log events
        sut.track("Test Event")
    }
    
    // MARK: - Session Tests
    
    func testSessionGeneration() {
        // Given
        sut.initialize(writeKey: "test_key")
        
        // When
        let sessionId1 = sut.getSessionId()
        sut.reset()
        let sessionId2 = sut.getSessionId()
        
        // Then
        XCTAssertNotNil(sessionId1)
        XCTAssertNotEqual(sessionId1, sessionId2)
    }
}
