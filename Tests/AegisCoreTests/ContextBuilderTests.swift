import XCTest
@testable import AegisCore

final class ContextBuilderTests: XCTestCase {
    
    func testBuildCompleteContext() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertNotNil(context.device)
        XCTAssertNotNil(context.os)
        XCTAssertNotNil(context.app)
        XCTAssertNotNil(context.screen)
        XCTAssertNotNil(context.network)
        XCTAssertNotNil(context.battery)
        XCTAssertNotNil(context.locale)
        XCTAssertNotNil(context.timezone)
        XCTAssertNotNil(context.library)
    }
    
    func testDeviceInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertEqual(context.device.manufacturer, "Apple")
        XCTAssertFalse(context.device.id.isEmpty)
        XCTAssertFalse(context.device.model.isEmpty)
        XCTAssertTrue(context.device.type == "mobile" || context.device.type == "tablet")
    }
    
    func testOSInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertTrue(context.os.name == "iOS" || context.os.name == "iPadOS")
        XCTAssertFalse(context.os.version.isEmpty)
        XCTAssertTrue(context.os.version.contains("."))
    }
    
    func testAppInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertFalse(context.app.name.isEmpty)
        XCTAssertFalse(context.app.version.isEmpty)
        XCTAssertFalse(context.app.build.isEmpty)
        XCTAssertFalse(context.app.namespace.isEmpty)
    }
    
    func testScreenInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertGreaterThan(context.screen.width, 0)
        XCTAssertGreaterThan(context.screen.height, 0)
        XCTAssertGreaterThan(context.screen.density, 0)
    }
    
    func testNetworkInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        // Should have network info (can't assert specific values as they depend on device state)
        XCTAssertNotNil(context.network)
    }
    
    func testBatteryInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        if let batteryLevel = context.battery.level {
            XCTAssertGreaterThanOrEqual(batteryLevel, 0.0)
            XCTAssertLessThanOrEqual(batteryLevel, 1.0)
        }
    }
    
    func testLocaleAndTimezone() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertFalse(context.locale.isEmpty)
        XCTAssertFalse(context.timezone.isEmpty)
        XCTAssertTrue(context.locale.contains("_"))
        XCTAssertTrue(context.timezone.contains("/") || context.timezone == "GMT")
    }
    
    func testLibraryInfo() {
        // When
        let context = ContextBuilder.buildContext()
        
        // Then
        XCTAssertEqual(context.library.name, "aegis-ios-sdk")
        XCTAssertEqual(context.library.version, "1.1.0")
    }
    
    func testContextConsistency() {
        // When - build context twice
        let context1 = ContextBuilder.buildContext()
        let context2 = ContextBuilder.buildContext()
        
        // Then - device-level properties should be consistent
        XCTAssertEqual(context1.device.id, context2.device.id)
        XCTAssertEqual(context1.device.model, context2.device.model)
        XCTAssertEqual(context1.os.version, context2.os.version)
        XCTAssertEqual(context1.app.version, context2.app.version)
    }
}
