import Foundation
import UIKit
import CoreTelephony

/// Collects device, app, and environmental context
class ContextBuilder {
    
    static func buildContext() -> EventContext {
        let device = buildDeviceInfo()
        let os = buildOSInfo()
        let app = buildAppInfo()
        let screen = buildScreenInfo()
        let network = buildNetworkInfo()
        let battery = buildBatteryInfo()
        let locale = buildLocaleInfo()
        let timezone = buildTimezoneInfo()
        
        // EventContext field order: library, device, os, app, screen,
        // network, battery, locale, timezone, cell. `cell` is server-set
        // for cell-routing telemetry; client always sends nil.
        return EventContext(
            library: LibraryInfo(name: "aegis-ios-sdk", version: "1.6.0"),
            device: device,
            os: os,
            app: app,
            screen: screen,
            network: network,
            battery: battery,
            locale: locale,
            timezone: timezone,
            cell: nil
        )
    }
    
    private static func buildDeviceInfo() -> DeviceInfo {
        let device = UIDevice.current
        
        // Device model (e.g., "iPhone14,2" for iPhone 13 Pro)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // DeviceInfo struct fields: type, manufacturer, model, id, advertisingId?
        // The marketing name (e.g. "iPhone 13 Pro") returned by mapModelIdentifier
        // isn't part of the wire shape — we keep model = device identifier.
        // advertisingId requires AdSupport.framework + ATT prompt; nil for now.
        return DeviceInfo(
            type: device.userInterfaceIdiom == .pad ? "tablet" : "mobile",
            manufacturer: "Apple",
            model: identifier,
            id: device.identifierForVendor?.uuidString ?? "",
            advertisingId: nil
        )
    }
    
    private static func buildOSInfo() -> OSInfo {
        let os = ProcessInfo.processInfo
        let version = "\(os.operatingSystemVersion.majorVersion).\(os.operatingSystemVersion.minorVersion).\(os.operatingSystemVersion.patchVersion)"
        
        return OSInfo(
            name: UIDevice.current.systemName,
            version: version
        )
    }
    
    private static func buildAppInfo() -> AppInfo {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? bundle.infoDictionary?["CFBundleName"] as? String ?? "unknown"
        let bundleId = bundle.bundleIdentifier ?? "unknown"
        
        // AppInfo only carries name/version/build. bundleId previously
        // landed in a removed `namespace` field; if needed for analytics
        // it can ride in event properties.
        _ = bundleId
        return AppInfo(
            name: name,
            version: version,
            build: build
        )
    }
    
    private static func buildScreenInfo() -> ScreenInfo {
        let screen = UIScreen.main
        let width = Int(screen.bounds.width * screen.scale)
        let height = Int(screen.bounds.height * screen.scale)
        let density = screen.scale
        
        return ScreenInfo(
            width: width,
            height: height,
            density: density
        )
    }
    
    private static func buildNetworkInfo() -> NetworkInfo {
        let networkInfo = CTTelephonyNetworkInfo()
        
        var carrier: String?
        var cellularTechnology: String?
        
        if let serviceCurrentRadioAccessTechnology = networkInfo.serviceCurrentRadioAccessTechnology?.values.first {
            cellularTechnology = mapRadioAccessTechnology(serviceCurrentRadioAccessTechnology)
        }
        
        if let serviceSubscriberCellularProviders = networkInfo.serviceSubscriberCellularProviders?.values.first {
            carrier = serviceSubscriberCellularProviders.carrierName
        }
        
        // Determine connection type
        let reachability = NetworkReachability()
        let connectionType = reachability.currentConnectionType()
        
        // NetworkInfo struct only carries carrier + connectionType + effectiveType;
        // the bluetooth/cellular/wifi booleans aren't part of its public shape.
        return NetworkInfo(
            carrier: carrier,
            connectionType: connectionType,
            effectiveType: cellularTechnology
        )
    }

    private static func buildBatteryInfo() -> BatteryInfo {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState

        let isCharging: Bool
        switch state {
        case .charging, .full:
            isCharging = true
        default:
            isCharging = false
        }

        // BatteryInfo.level is `Double`. UIDevice.batteryLevel is Float,
        // and is -1 when unknown — fall back to 0 to keep the field
        // non-optional (the struct requires a value).
        return BatteryInfo(
            level: Double(level >= 0 ? level : 0),
            isCharging: isCharging
        )
    }
    
    private static func buildLocaleInfo() -> String {
        return Locale.current.identifier
    }
    
    private static func buildTimezoneInfo() -> String {
        return TimeZone.current.identifier
    }
    
    // MARK: - Helpers
    
    private static func mapModelIdentifier(_ identifier: String) -> String {
        let modelMap: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 14",
            "iPhone15,5": "iPhone 14 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPad13,1": "iPad Air (5th generation)",
            "iPad13,2": "iPad Air (5th generation)",
            "iPad14,1": "iPad Pro 11-inch (4th generation)",
            "iPad14,2": "iPad Pro 12.9-inch (6th generation)"
        ]
        
        return modelMap[identifier] ?? identifier
    }
    
    private static func mapRadioAccessTechnology(_ technology: String) -> String {
        switch technology {
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge:
            return "2G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA, CTRadioAccessTechnologyCDMA1x, CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA, CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyLTE:
            return "4G"
        default:
            if #available(iOS 14.1, *) {
                if technology == CTRadioAccessTechnologyNRNSA || technology == CTRadioAccessTechnologyNR {
                    return "5G"
                }
            }
            return "Unknown"
        }
    }
}

// MARK: - Network Reachability

import SystemConfiguration

private class NetworkReachability {
    func currentConnectionType() -> String {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return "none"
        }
        
        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return "none"
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let isConnected = isReachable && !needsConnection
        
        if !isConnected {
            return "none"
        }
        
        if flags.contains(.isWWAN) {
            return "cellular"
        }
        
        return "wifi"
    }
}
