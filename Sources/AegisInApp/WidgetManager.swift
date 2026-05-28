import Foundation
import UIKit
import SwiftUI

public class WidgetManager {
    
    public static let shared = WidgetManager()
    
    private var apiHost: String = "https://api.active-reach.ai"
    private var writeKey: String?
    private var userId: String?
    private var contactId: String?
    private var organizationId: String?
    private var debugMode = false
    private var enablePrefetch = true
    
    private var widgets: [WidgetConfig] = []
    private var renderedWidgets = Set<String>()
    private var isInitialized = false
    private var prefetchWidgetConfigs: [String: [String: Any]] = [:]
    
    private var triggerEngine: TriggerEngine?
    
    public struct WidgetConfig: Codable {
        public let widgetId: String
        public let widgetType: WidgetType
        public let name: String
        public let config: [String: AnyCodable]
        public let position: String?
        public let priority: Int
        public let triggerRules: TriggerRules?
        
        public enum WidgetType: String, Codable {
            case chatBubble = "chat_bubble"
            case spinWheel = "spin_wheel"
            case scratchCard = "scratch_card"
            case toast
            case feedbackForm = "feedback_form"
            case exitIntentPopup = "exit_intent_popup"
        }
        
        public struct TriggerRules: Codable {
            public let type: String
            public let config: [String: AnyCodable]?
        }
    }
    
    public struct AnyCodable: Codable {
        public let value: Any
        
        public init(_ value: Any) {
            self.value = value
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let intValue = try? container.decode(Int.self) {
                value = intValue
            } else if let doubleValue = try? container.decode(Double.self) {
                value = doubleValue
            } else if let stringValue = try? container.decode(String.self) {
                value = stringValue
            } else if let boolValue = try? container.decode(Bool.self) {
                value = boolValue
            } else if let arrayValue = try? container.decode([AnyCodable].self) {
                value = arrayValue.map { $0.value }
            } else if let dictValue = try? container.decode([String: AnyCodable].self) {
                value = dictValue.mapValues { $0.value }
            } else {
                value = NSNull()
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch value {
            case let intValue as Int:
                try container.encode(intValue)
            case let doubleValue as Double:
                try container.encode(doubleValue)
            case let stringValue as String:
                try container.encode(stringValue)
            case let boolValue as Bool:
                try container.encode(boolValue)
            case let arrayValue as [Any]:
                try container.encode(arrayValue.map { AnyCodable($0) })
            case let dictValue as [String: Any]:
                try container.encode(dictValue.mapValues { AnyCodable($0) })
            default:
                try container.encodeNil()
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
        triggerEngine: TriggerEngine? = nil,
        debugMode: Bool = false,
        enablePrefetch: Bool = true
    ) {
        guard !isInitialized else {
            log("WidgetManager already initialized")
            return
        }
        
        self.writeKey = writeKey
        self.apiHost = apiHost
        self.userId = userId
        self.contactId = contactId
        self.organizationId = organizationId
        self.triggerEngine = triggerEngine
        self.debugMode = debugMode
        self.enablePrefetch = enablePrefetch
        
        if enablePrefetch && contactId != nil {
            fetchPrefetchConfigs { [weak self] in
                self?.fetchWidgets()
                self?.setupExitIntentWithPrefetch()
            }
        } else {
            fetchWidgets()
        }
        
        isInitialized = true
        log("WidgetManager initialized successfully")
    }
    
    private func fetchPrefetchConfigs(completion: @escaping () -> Void) {
        guard let writeKey = writeKey else {
            log("Cannot fetch prefetch configs: writeKey not set")
            completion()
            return
        }
        
        let endpoint = "\(apiHost)/v1/widgets/config/prefetch"
        
        guard let url = URL(string: endpoint) else {
            log("Invalid prefetch API endpoint URL")
            completion()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        
        if let contactId = contactId {
            request.setValue(contactId, forHTTPHeaderField: "X-Contact-ID")
        }
        if let organizationId = organizationId {
            request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        }
        
        let startTime = Date()
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion()
                return
            }
            
            if let error = error {
                self.log("Failed to fetch prefetch configs: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let data = data else {
                self.log("No data received from prefetch endpoint")
                completion()
                return
            }
            
            do {
                if let configs = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                    let elapsed = Date().timeIntervalSince(startTime) * 1000
                    DispatchQueue.main.async {
                        self.prefetchWidgetConfigs = configs
                        self.log("Fetched prefetch widget configs in \(String(format: "%.2f", elapsed))ms")
                        completion()
                    }
                } else {
                    self.log("Invalid prefetch config format")
                    completion()
                }
            } catch {
                self.log("Failed to decode prefetch configs: \(error)")
                completion()
            }
        }
        
        task.resume()
    }
    
    private func fetchWidgets() {
        guard let writeKey = writeKey else {
            log("Cannot fetch widgets: writeKey not set")
            return
        }
        
        let endpoint = "\(apiHost)/v1/widgets/config"
        
        guard let url = URL(string: endpoint) else {
            log("Invalid API endpoint URL")
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
                self.log("Failed to fetch widgets: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.log("No data received from widgets endpoint")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let widgets = try decoder.decode([WidgetConfig].self, from: data)
                
                DispatchQueue.main.async {
                    self.widgets = widgets.sorted { $0.priority > $1.priority }
                    self.log("Fetched \(widgets.count) widgets")
                    self.renderImmediateWidgets()
                    self.setupTriggerListeners()
                }
            } catch {
                self.log("Failed to decode widgets: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func renderImmediateWidgets() {
        let immediateWidgets = widgets.filter { widget in
            widget.triggerRules?.type == "immediate" || widget.triggerRules == nil
        }
        
        immediateWidgets.forEach { widget in
            renderWidget(widget)
        }
    }
    
    private func setupExitIntentWithPrefetch() {
        guard enablePrefetch, let triggerEngine = triggerEngine else {
            return
        }
        
        let spinWheelConfig = prefetchWidgetConfigs["spin_wheel"]
        let exitIntentConfig = prefetchWidgetConfigs["exit_intent"]
        
        if let spinWheel = spinWheelConfig, (spinWheel["enabled"] as? Bool) == true {
            let handleSpinWheelIntent = { [weak self] in
                guard let self = self else { return }
                
                let widgetId = "prefetch_spin_wheel_\(Date().timeIntervalSince1970)"
                
                if self.renderedWidgets.contains(widgetId) {
                    return
                }
                
                self.renderedWidgets.insert(widgetId)
                
                let widgetType = spinWheel["type"] as? String ?? "lead_gen"
                
                self.log("Rendering prefetch spin wheel: type=\(widgetType)")
                self.trackWidgetEvent(widgetId, event: "show")
            }
            
            triggerEngine.registerBackButton()
            triggerEngine.on(eventType: "back_button") { _ in
                handleSpinWheelIntent()
            }
            
            triggerEngine.registerAppBackgrounding()
            triggerEngine.on(eventType: "app_backgrounding") { _ in
                handleSpinWheelIntent()
            }
            
            log("Setup mobile spin wheel with back button and backgrounding triggers")
            return
        }
        
        if let exitIntent = exitIntentConfig, (exitIntent["enabled"] as? Bool) == true {
            let handleExitIntent = { [weak self] in
                guard let self = self else { return }
                
                let widgetId = "prefetch_exit_intent_\(Date().timeIntervalSince1970)"
                
                if self.renderedWidgets.contains(widgetId) {
                    return
                }
                
                self.renderedWidgets.insert(widgetId)
                
                let widgetType = exitIntent["type"] as? String ?? "cart_recovery"
                
                self.log("Rendering prefetch exit intent: type=\(widgetType)")
                self.trackWidgetEvent(widgetId, event: "show")
            }
            
            triggerEngine.registerBackButton()
            triggerEngine.on(eventType: "back_button") { _ in
                handleExitIntent()
            }
            
            triggerEngine.registerAppBackgrounding()
            triggerEngine.on(eventType: "app_backgrounding") { _ in
                handleExitIntent()
            }
            
            log("Setup mobile exit intent with back button and backgrounding triggers")
        }
    }
    
    private func setupTriggerListeners() {
        guard let triggerEngine = triggerEngine else {
            log("TriggerEngine not provided, skipping trigger-based widgets")
            return
        }
        
        for widget in widgets {
            guard let triggerRules = widget.triggerRules else { continue }
            
            switch triggerRules.type {
            case "exit_intent":
                triggerEngine.registerExitIntent()
                triggerEngine.on(eventType: "exit_intent") { [weak self] _ in
                    if !self!.renderedWidgets.contains(widget.widgetId) {
                        self?.renderWidget(widget)
                    }
                }
                
            case "scroll_depth":
                if let depthPercent = triggerRules.config?["depth_percent"]?.value as? Int {
                    triggerEngine.registerScrollDepth(depthPercent: depthPercent)
                    triggerEngine.on(eventType: "scroll_depth_\(depthPercent)") { [weak self] _ in
                        if !self!.renderedWidgets.contains(widget.widgetId) {
                            self?.renderWidget(widget)
                        }
                    }
                }
                
            case "time_on_page":
                if let seconds = triggerRules.config?["seconds"]?.value as? Int {
                    triggerEngine.registerTimeOnScreen(seconds: TimeInterval(seconds))
                    triggerEngine.on(eventType: "time_on_screen_\(seconds)") { [weak self] _ in
                        if !self!.renderedWidgets.contains(widget.widgetId) {
                            self?.renderWidget(widget)
                        }
                    }
                }
                
            default:
                break
            }
        }
    }
    
    private func renderWidget(_ widget: WidgetConfig) {
        guard !renderedWidgets.contains(widget.widgetId) else { return }
        renderedWidgets.insert(widget.widgetId)

        log("Rendering widget: \(widget.widgetId) of type: \(widget.widgetType)")
        trackWidgetEvent(widget.widgetId, event: "show")

        switch widget.widgetType {
        case .spinWheel, .scratchCard:
            let subType = widget.widgetType == .spinWheel ? "spin_wheel" : "scratch_card"
            let interactiveConfig = widget.config.mapValues {
                AegisInAppManager.InAppCampaign.AnyCodable($0.value)
            }
            let campaign = AegisInAppManager.InAppCampaign(
                id: widget.widgetId,
                type: .modal,
                subType: subType,
                title: widget.name,
                body: "",
                imageUrl: nil, videoUrl: nil, actionUrl: nil,
                buttonText: nil, backgroundColor: nil, textColor: nil,
                priority: widget.priority, expiresAt: nil, frequency: nil,
                interactiveConfig: interactiveConfig, assignedVariantId: nil
            )
            let responseService = InAppResponseService(
                apiHost: apiHost, writeKey: writeKey,
                organizationId: organizationId, userId: userId, contactId: contactId
            )

            DispatchQueue.main.async {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = windowScene.windows.first else { return }

                let hostingController = UIHostingController(rootView: SwiftUI.AnyView(
                    InAppInteractiveView(
                        campaign: campaign,
                        subType: subType,
                        responseService: responseService,
                        onDismiss: { [weak self] in self?.trackWidgetEvent(widget.widgetId, event: "dismiss") },
                        onAction: { [weak self] in self?.trackWidgetEvent(widget.widgetId, event: "click") }
                    )
                ))
                hostingController.view.backgroundColor = .clear
                hostingController.modalPresentationStyle = .overFullScreen
                hostingController.modalTransitionStyle = .crossDissolve
                window.rootViewController?.present(hostingController, animated: true)
            }

        default:
            log("Widget type \(widget.widgetType) rendering not yet implemented")
        }
    }
    
    private func trackWidgetEvent(_ widgetId: String, event: String) {
        guard let writeKey = writeKey else { return }
        
        let endpoint = "\(apiHost)/v1/widgets/track-event"
        
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let eventData: [String: Any] = [
            "widget_id": widgetId,
            "event_type": event,
            "event_data": [:] as [String: Any]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData)
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                if let error = error {
                    self?.log("Failed to track widget event: \(error.localizedDescription)")
                } else {
                    self?.log("Widget event tracked: \(event) for widget \(widgetId)")
                }
            }
            
            task.resume()
        } catch {
            log("Failed to serialize widget event: \(error)")
        }
    }
    
    private func log(_ message: String) {
        if debugMode {
            print("[WidgetManager] \(message)")
        }
    }
}
