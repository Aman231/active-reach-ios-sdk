import Foundation

/// Fetches and manages remote SDK configuration from server
class RemoteConfigManager {
    
    private let writeKey: String
    private let baseURL: String
    private let session: URLSession
    
    private var cachedConfig: RemoteConfig?
    private var lastFetchTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private var configUpdateCallback: ((RemoteConfig) -> Void)?
    
    init(writeKey: String, baseURL: String = "https://api.active-reach.ai") {
        self.writeKey = writeKey
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: config)
        
        loadCachedConfig()
    }
    
    func fetchConfig(completion: @escaping (RemoteConfig?) -> Void) {
        // Return cached config if still valid
        if let cachedConfig = cachedConfig,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheValidityDuration {
            completion(cachedConfig)
            return
        }
        
        let endpoint = "\(baseURL)/v1/sdk/config"
        
        guard let url = URL(string: endpoint) else {
            completion(cachedConfig) // Fallback to cached
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ActiveReach-iOS-SDK/1.1.0", forHTTPHeaderField: "User-Agent")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[Active Reach] Failed to fetch config: \(error.localizedDescription)")
                completion(self.cachedConfig) // Fallback to cached
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data else {
                print("[Active Reach] Invalid config response")
                completion(self.cachedConfig) // Fallback to cached
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let config = try decoder.decode(RemoteConfig.self, from: data)
                
                self.cachedConfig = config
                self.lastFetchTime = Date()
                self.saveCachedConfig(config)
                
                // Notify callback
                self.configUpdateCallback?(config)
                
                completion(config)
            } catch {
                print("[Active Reach] Failed to decode config: \(error)")
                completion(self.cachedConfig) // Fallback to cached
            }
        }
        
        task.resume()
    }
    
    func setConfigUpdateCallback(_ callback: @escaping (RemoteConfig) -> Void) {
        self.configUpdateCallback = callback
    }
    
    private func saveCachedConfig(_ config: RemoteConfig) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(config)
            UserDefaults.standard.set(data, forKey: "aegis_remote_config")
            UserDefaults.standard.set(Date(), forKey: "aegis_remote_config_timestamp")
        } catch {
            print("[Active Reach] Failed to cache config: \(error)")
        }
    }
    
    private func loadCachedConfig() {
        guard let data = UserDefaults.standard.data(forKey: "aegis_remote_config"),
              let timestamp = UserDefaults.standard.object(forKey: "aegis_remote_config_timestamp") as? Date else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(RemoteConfig.self, from: data)
            self.cachedConfig = config
            self.lastFetchTime = timestamp
        } catch {
            print("[Active Reach] Failed to load cached config: \(error)")
        }
    }
}

// MARK: - Remote Config Model

struct RemoteConfig: Codable {
    let batchSize: Int
    let flushInterval: Int // in seconds
    let blockEvents: [String]
    let samplingRate: Double // 0.0 to 1.0
    let features: FeatureFlags
    let endpoints: Endpoints
    // Fields from GET /v1/sdk/config (security-scoped — non-sensitive only)
    let version: String?
    let push: PushConfig?
    let inApp: InAppConfig?
    let consent: ConsentConfig?

    struct FeatureFlags: Codable {
        let pushNotifications: Bool
        let inAppMessaging: Bool
        let locationTracking: Bool
        let sessionReplay: Bool
    }

    struct Endpoints: Codable {
        let batch: String
        let identify: String
        let track: String
    }

    struct PushConfig: Codable {
        let enabled: Bool
        let vapidPublicKey: String?
        let platforms: [String]
    }

    struct InAppConfig: Codable {
        let enabled: Bool
    }

    struct ConsentConfig: Codable {
        let channelsRequiringOptIn: [String]
    }

    init() {
        self.batchSize = 20
        self.flushInterval = 30
        self.blockEvents = []
        self.samplingRate = 1.0
        self.features = FeatureFlags(
            pushNotifications: true,
            inAppMessaging: true,
            locationTracking: false,
            sessionReplay: false
        )
        self.endpoints = Endpoints(
            batch: "/v1/batch",
            identify: "/v1/identify",
            track: "/v1/track"
        )
        self.version = nil
        self.push = nil
        self.inApp = nil
        self.consent = nil
    }

    func isEventBlocked(_ eventName: String) -> Bool {
        return blockEvents.contains(eventName)
    }

    func shouldSampleEvent() -> Bool {
        return Double.random(in: 0...1) <= samplingRate
    }
}
