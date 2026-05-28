import Foundation
import UIKit

public class PlacementManager {
    
    public static let shared = PlacementManager()
    
    private var apiHost: String = "https://api.active-reach.ai"
    private var writeKey: String?
    private var userId: String?
    private var contactId: String?
    private var organizationId: String?
    private var debugMode = false
    
    private var placements: [String: PlacementContent] = [:]
    private var isInitialized = false
    
    public struct PlacementContent: Codable {
        public let placementId: String
        public let variantId: String
        public let contentType: String
        public let content: ContentData
        
        public struct ContentData: Codable {
            public let html: String?
            public let title: String?
            public let body: String?
            public let imageUrl: String?
            public let actionUrl: String?
            public let buttonText: String?
            
            enum CodingKeys: String, CodingKey {
                case html
                case title
                case body
                case imageUrl = "image_url"
                case actionUrl = "action_url"
                case buttonText = "button_text"
            }
        }
    }
    
    private init() {}
    
    public func initialize(
        writeKey: String,
        apiHost: String = "https://api.active-reach.ai",
        userId: String? = nil,
        contactId: String? = nil,
        organizationId: String? = nil,
        debugMode: Bool = false
    ) {
        guard !isInitialized else {
            log("PlacementManager already initialized")
            return
        }
        
        self.writeKey = writeKey
        self.apiHost = apiHost
        self.userId = userId
        self.contactId = contactId
        self.organizationId = organizationId
        self.debugMode = debugMode
        
        isInitialized = true
        log("PlacementManager initialized successfully")
    }
    
    public func fetchPlacements(placementIds: [String], completion: @escaping ([PlacementContent]) -> Void) {
        guard let writeKey = writeKey else {
            log("Cannot fetch placements: writeKey not set")
            completion([])
            return
        }
        
        let placementIdsParam = placementIds.joined(separator: ",")
        let endpoint = "\(apiHost)/v1/placements/content?placement_ids=\(placementIdsParam)"
        
        guard let url = URL(string: endpoint) else {
            log("Invalid API endpoint URL")
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ios", forHTTPHeaderField: "X-Device-Platform")
        request.setValue("mobile", forHTTPHeaderField: "X-Device-Type")
        
        if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        }
        if let contactId = contactId {
            request.setValue(contactId, forHTTPHeaderField: "X-Contact-ID")
        }
        if let organizationId = organizationId {
            request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("Failed to fetch placements: \(error.localizedDescription)")
                completion([])
                return
            }
            
            guard let data = data else {
                self.log("No data received from placements endpoint")
                completion([])
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let contents = try decoder.decode([PlacementContent].self, from: data)
                
                DispatchQueue.main.async {
                    for content in contents {
                        self.placements[content.placementId] = content
                    }
                    
                    self.log("Fetched \(contents.count) placements")
                    completion(contents)
                }
            } catch {
                self.log("Failed to decode placements: \(error)")
                completion([])
            }
        }
        
        task.resume()
    }
    
    public func getPlacement(placementId: String) -> PlacementContent? {
        return placements[placementId]
    }
    
    public func trackPlacementEvent(placementId: String, variantId: String, eventType: String) {
        guard let writeKey = writeKey else { return }
        
        let endpoint = "\(apiHost)/v1/placements/track-event"
        
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let eventData: [String: Any] = [
            "placement_id": placementId,
            "variant_id": variantId,
            "event_type": eventType,
            "metadata": [:] as [String: Any]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                if let error = error {
                    self?.log("Failed to track placement event: \(error.localizedDescription)")
                } else {
                    self?.log("Placement event tracked: \(eventType) for placement \(placementId)")
                }
            }
            
            task.resume()
        } catch {
            log("Failed to serialize placement event: \(error)")
        }
    }
    
    private func log(_ message: String) {
        if debugMode {
            print("[PlacementManager] \(message)")
        }
    }
}
