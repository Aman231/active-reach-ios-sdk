import Foundation

/// Active Reach SDK configuration
public struct AegisConfig {
    
    // MARK: - Core Settings
    public var apiHost: String
    public var cellEndpoints: [CellEndpoint]?
    public var preferredRegion: String?
    public var autoRegionDetection: Bool

    /// Brand-tenant identifier — stamped as `X-Workspace-Id` on every
    /// outgoing event when set. Required for any tenant that has more
    /// than one workspace; optional for single-workspace orgs.
    public var workspaceId: String?

    /// Outlet identifier within the brand. Optional — propagates onto
    /// events that need outlet-scoped attribution (per-store ops,
    /// inventory, kitchen).
    public var locationId: String?

    /// App Group suite name — required when shipping a Notification
    /// Service Extension (NSE) AND the host app needs the NSE to
    /// post `push.delivered` engagement events. The NSE runs in a
    /// separate process and can only read configuration the host
    /// pushes into a shared App Group. Set to e.g. `"group.com.your.id"`.
    /// Phase 4.5: ConsentManager + AegisPushTracker persist their
    /// state to this suite so the NSE can read it.
    public var appGroupSuiteName: String?
    
    // MARK: - Remote Configuration (v1.1)
    public var enableRemoteConfig: Bool
    public var remoteConfigSyncInterval: TimeInterval
    public var fallbackToLocalConfig: Bool
    
    // MARK: - Batching & Flushing
    public var batchSize: Int
    public var batchInterval: TimeInterval
    public var enableAdaptiveBatching: Bool
    
    // MARK: - Auto-Tracking
    public var autoPageView: Bool
    public var autoSessionTracking: Bool
    public var autoAppLifecycle: Bool
    
    // MARK: - Session Management
    public var sessionTimeout: TimeInterval
    
    // MARK: - Context Capture
    public var captureDeviceInfo: Bool
    public var captureNetworkInfo: Bool
    public var captureBatteryInfo: Bool
    
    // MARK: - Privacy & Compliance
    public var respectDoNotTrack: Bool
    /// **Deprecated since Phase 4.** Use the categorical
    /// `Aegis.shared.consent.setConsent([.marketing: granted])` model
    /// instead. ATT denial maps to `marketing=false`. The flag is
    /// retained as a config knob purely for backwards-compat — it no
    /// longer gates anything in the SDK; the categorical
    /// `ConsentManager` is the single source of truth.
    public var enableATT: Bool
    /// **Deprecated since Phase 4.** Same rationale as `enableATT`.
    /// Use `Aegis.shared.consent` directly.
    public var waitForATTConsent: Bool
    public var encryptLocalStorage: Bool
    
    // MARK: - Offline Mode & Storage
    public var enableOfflineMode: Bool
    public var maxOfflineEvents: Int
    public var eventRetentionDays: Int
    
    // MARK: - Retry Logic
    public var retryFailedRequests: Bool
    public var maxRetries: Int
    public var retryBackoffMultiplier: Double
    
    // MARK: - Network & Security
    public var requestTimeout: TimeInterval
    public var enableCertificatePinning: Bool
    public var enableHTTP2: Bool
    public var enableGzipCompression: Bool
    
    // MARK: - Debugging
    public var debugMode: Bool
    public var logLevel: LogLevel
    
    // MARK: - Internal (set by remote config)
    internal var blockedEvents: [String]?
    
    // MARK: - Initialization
    
    public init(
        apiHost: String = "https://api.active-reach.ai",
        cellEndpoints: [CellEndpoint]? = nil,
        preferredRegion: String? = nil,
        autoRegionDetection: Bool = true,
        workspaceId: String? = nil,
        locationId: String? = nil,
        appGroupSuiteName: String? = nil,
        enableRemoteConfig: Bool = true,
        remoteConfigSyncInterval: TimeInterval = 24 * 60 * 60,
        fallbackToLocalConfig: Bool = true,
        batchSize: Int = 10,
        batchInterval: TimeInterval = 5.0,
        enableAdaptiveBatching: Bool = true,
        autoPageView: Bool = false,
        autoSessionTracking: Bool = true,
        autoAppLifecycle: Bool = true,
        sessionTimeout: TimeInterval = 30 * 60,
        captureDeviceInfo: Bool = true,
        captureNetworkInfo: Bool = true,
        captureBatteryInfo: Bool = true,
        respectDoNotTrack: Bool = true,
        enableATT: Bool = true,
        waitForATTConsent: Bool = false,
        encryptLocalStorage: Bool = true,
        enableOfflineMode: Bool = true,
        maxOfflineEvents: Int = 10000,
        eventRetentionDays: Int = 30,
        retryFailedRequests: Bool = true,
        maxRetries: Int = 3,
        retryBackoffMultiplier: Double = 2.0,
        requestTimeout: TimeInterval = 10.0,
        enableCertificatePinning: Bool = true,
        enableHTTP2: Bool = true,
        enableGzipCompression: Bool = true,
        debugMode: Bool = false,
        logLevel: LogLevel = .error
    ) {
        self.apiHost = apiHost
        self.cellEndpoints = cellEndpoints
        self.preferredRegion = preferredRegion
        self.autoRegionDetection = autoRegionDetection
        self.workspaceId = workspaceId
        self.locationId = locationId
        self.appGroupSuiteName = appGroupSuiteName
        self.enableRemoteConfig = enableRemoteConfig
        self.remoteConfigSyncInterval = remoteConfigSyncInterval
        self.fallbackToLocalConfig = fallbackToLocalConfig
        self.batchSize = batchSize
        self.batchInterval = batchInterval
        self.enableAdaptiveBatching = enableAdaptiveBatching
        self.autoPageView = autoPageView
        self.autoSessionTracking = autoSessionTracking
        self.autoAppLifecycle = autoAppLifecycle
        self.sessionTimeout = sessionTimeout
        self.captureDeviceInfo = captureDeviceInfo
        self.captureNetworkInfo = captureNetworkInfo
        self.captureBatteryInfo = captureBatteryInfo
        self.respectDoNotTrack = respectDoNotTrack
        self.enableATT = enableATT
        self.waitForATTConsent = waitForATTConsent
        self.encryptLocalStorage = encryptLocalStorage
        self.enableOfflineMode = enableOfflineMode
        self.maxOfflineEvents = maxOfflineEvents
        self.eventRetentionDays = eventRetentionDays
        self.retryFailedRequests = retryFailedRequests
        self.maxRetries = maxRetries
        self.retryBackoffMultiplier = retryBackoffMultiplier
        self.requestTimeout = requestTimeout
        self.enableCertificatePinning = enableCertificatePinning
        self.enableHTTP2 = enableHTTP2
        self.enableGzipCompression = enableGzipCompression
        self.debugMode = debugMode
        self.logLevel = logLevel
    }
}

// MARK: - Supporting Types

public struct CellEndpoint {
    public let region: String
    public let endpoint: String
    
    public init(region: String, endpoint: String) {
        self.region = region
        self.endpoint = endpoint
    }
}

public enum LogLevel: String {
    case verbose
    case debug
    case info
    case warning
    case error
}
