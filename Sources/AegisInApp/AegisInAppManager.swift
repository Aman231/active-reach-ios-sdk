import Foundation
import UIKit
import SwiftUI

public class AegisInAppManager {
    
    public static let shared = AegisInAppManager()
    
    private var apiHost: String = "https://api.active-reach.ai"
    private var writeKey: String?
    private var userId: String?
    private var contactId: String?
    private var organizationId: String?
    
    private var queuedWidgets: [WidgetMessage] = []
    private var displayedWidgets: Set<String> = []
    private var sseTask: URLSessionDataTask?
    private var isInitialized = false
    private var debugMode = false
    private var enableSSE = true
    private var pendingAcks: [PendingAck] = []
    private let ackQueue = DispatchQueue(label: "ai.aegis.ackQueue")
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    
    private struct PendingAck: Codable {
        let stepExecutionId: String
        let action: String
        let timestamp: Date
        let retryCount: Int
        
        var shouldRetry: Bool {
            retryCount < 3 && Date().timeIntervalSince(timestamp) < 86400
        }
    }
    
    public struct WidgetMessage: Codable {
        public let id: String
        public let journeyStepExecutionId: String
        public let displayType: String
        public let priority: Int
        public let title: String
        public let body: String
        public let imageUrl: String?
        public let buttonText: String?
        public let actionUrl: String?
        public let backgroundColor: String?
        public let textColor: String?
        public let expiresAt: String
        public let createdAt: String
        public let ttlRemainingHours: Double?
        public let metadata: [String: String]?
        
        var isExpired: Bool {
            guard let expiryDate = ISO8601DateFormatter().date(from: expiresAt) else {
                return true
            }
            return expiryDate <= Date()
        }
    }
    
    public struct WidgetStateResponse: Codable {
        public let widgets: [WidgetMessage]
        public let total: Int
    }
    
    private init() {
        loadPendingAcks()
    }
    
    public func initialize(
        writeKey: String,
        apiHost: String = "https://api.active-reach.ai",
        userId: String? = nil,
        contactId: String? = nil,
        organizationId: String? = nil,
        enableSSE: Bool = true,
        debugMode: Bool = false
    ) {
        guard !isInitialized else {
            log("AegisInApp already initialized")
            return
        }
        
        self.writeKey = writeKey
        self.apiHost = apiHost
        self.userId = userId
        self.contactId = contactId
        self.organizationId = organizationId
        self.enableSSE = enableSSE
        self.debugMode = debugMode
        
        if enableSSE && organizationId != nil {
            connectSSE()
        } else {
            refreshWidgetQueue()
        }
        
        retryPendingAcks()
        
        isInitialized = true
        log("AegisInApp initialized successfully (SSE: \(enableSSE))")
    }
    
    public func updateUserId(_ userId: String) {
        self.userId = userId
        refreshWidgetQueue()
    }
    
    public func updateContactId(_ contactId: String) {
        self.contactId = contactId
        refreshWidgetQueue()
    }

    /// Call from `applicationDidBecomeActive` or `sceneDidBecomeActive`.
    /// Refreshes widget queue as fallback when SSE was disconnected while backgrounded.
    public func onAppResume() {
        guard isInitialized else { return }
        log("App resumed — refreshing widget queue")
        refreshWidgetQueue()
    }

    public func getQueuedWidgets() -> [WidgetMessage] {
        return queuedWidgets.filter { !$0.isExpired }
    }
    
    public func displayWidgetOnTrigger() {
        let validWidgets = queuedWidgets.filter { !$0.isExpired && !displayedWidgets.contains($0.journeyStepExecutionId) }
        guard let topWidget = validWidgets.sorted(by: { $0.priority > $1.priority }).first else {
            log("No widgets to display")
            return
        }
        displayWidget(topWidget)
    }
    
    private func connectSSE() {
        guard let writeKey = writeKey,
              let organizationId = organizationId else {
            log("Cannot connect SSE: missing required parameters")
            return
        }
        
        disconnectSSE()
        
        let endpoint = "\(apiHost)/v1/stream/realtime"
        guard let url = URL(string: endpoint) else {
            log("Invalid SSE endpoint URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        
        if let contactId = contactId {
            request.setValue(contactId, forHTTPHeaderField: "X-Contact-ID")
        }
        
        request.timeoutInterval = .infinity
        
        let session = URLSession(configuration: .default)
        sseTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("SSE connection error: \(error.localizedDescription)")
                self.attemptReconnect()
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                self.log("SSE connection failed with status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                self.attemptReconnect()
                return
            }
            
            self.log("SSE connection established")
            self.reconnectAttempts = 0
            self.refreshWidgetQueue()
        }
        
        let delegate = SSEDelegate { [weak self] event, data in
            self?.handleSSEEvent(event: event, data: data)
        }
        
        sseTask?.resume()
    }
    
    private func disconnectSSE() {
        sseTask?.cancel()
        sseTask = nil
    }
    
    private func handleSSEEvent(event: String, data: String) {
        switch event {
        case "in_app_campaign_updated":
            log("Received in-app campaign update")
            refreshWidgetQueue()
        case "heartbeat":
            log("SSE heartbeat received")
        case "connected":
            log("SSE connected event received")
        default:
            break
        }
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            log("Max SSE reconnect attempts reached")
            return
        }
        
        reconnectAttempts += 1
        let delay = min(Double(1 << reconnectAttempts), 30.0)
        
        log("Reconnecting SSE in \(delay)s (attempt \(reconnectAttempts))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  self.isInitialized,
                  self.enableSSE,
                  self.organizationId != nil else { return }
            self.connectSSE()
        }
    }
    
    public func disconnect() {
        disconnectSSE()
        isInitialized = false
    }
}

private class SSEDelegate: NSObject, URLSessionDataDelegate {
    private var onEvent: (String, String) -> Void
    private var buffer = ""
    
    init(onEvent: @escaping (String, String) -> Void) {
        self.onEvent = onEvent
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""
        
        var eventType = ""
        var eventData = ""
        
        for line in lines.dropLast() {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                eventData = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if line.isEmpty && !eventType.isEmpty {
                onEvent(eventType, eventData)
                eventType = ""
                eventData = ""
            }
        }
    }
    
    private func refreshWidgetQueue() {
        guard let writeKey = writeKey,
              let contactId = contactId,
              let organizationId = organizationId else {
            log("Cannot refresh widget queue: missing required parameters")
            return
        }
        
        let endpoint = "\(apiHost)/v1/in-app/widgets/state"
        
        guard let url = URL(string: endpoint) else {
            log("Invalid API endpoint URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        request.setValue(contactId, forHTTPHeaderField: "X-Contact-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("Failed to fetch widget queue: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                self.log("No data received from widget queue endpoint")
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let widgetState = try decoder.decode(WidgetStateResponse.self, from: data)
                
                DispatchQueue.main.async {
                    let validWidgets = widgetState.widgets.filter { !$0.isExpired }
                    self.queuedWidgets = validWidgets.sorted { $0.priority > $1.priority }
                    self.log("Fetched \(validWidgets.count) queued widgets (filtered \(widgetState.widgets.count - validWidgets.count) expired)")
                }
            } catch {
                self.log("Failed to decode widget queue: \(error)")
            }
        }
        
        task.resume()
    }
    
    private func displayWidget(_ widget: WidgetMessage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            log("No window available to display widget")
            return
        }
        
        displayedWidgets.insert(widget.journeyStepExecutionId)
        
        let legacyCampaign = convertToLegacyCampaign(widget)
        
        let onDismiss = { [weak self] in
            self?.acknowledgeWidget(widget.journeyStepExecutionId, action: "dismissed")
        }
        let onAction = { [weak self] in
            self?.acknowledgeWidget(widget.journeyStepExecutionId, action: "clicked")
        }

        let interactiveTypes: Set<String> = [
            "nps_survey", "star_rating", "quick_poll", "quiz",
            "countdown_offer", "multi_step_form", "spin_wheel", "scratch_card"
        ]

        DispatchQueue.main.async { [weak self] in
            let hostingController: UIHostingController<AnyView>

            if interactiveTypes.contains(widget.displayType) {
                let responseService = InAppResponseService(
                    apiHost: self?.apiHost ?? "",
                    writeKey: self?.writeKey,
                    organizationId: self?.organizationId,
                    userId: self?.userId,
                    contactId: self?.contactId
                )
                hostingController = UIHostingController(rootView: AnyView(
                    InAppInteractiveView(
                        campaign: legacyCampaign,
                        subType: widget.displayType,
                        responseService: responseService,
                        onDismiss: onDismiss,
                        onAction: onAction
                    )
                ))
            } else {
                switch widget.displayType {
                case "modal":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppModal(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "banner":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppBanner(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "full_screen":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppFullScreen(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "half_interstitial":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppHalfInterstitial(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "alert":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppAlert(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "pip":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppPIP(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                case "tooltip":
                    hostingController = UIHostingController(rootView: AnyView(
                        InAppTooltipView(campaign: legacyCampaign, onDismiss: onDismiss, onAction: onAction)
                    ))
                default:
                    self?.log("Widget type \(widget.displayType) not supported")
                    return
                }
            }

            hostingController.view.backgroundColor = .clear
            hostingController.modalPresentationStyle = .overFullScreen
            hostingController.modalTransitionStyle = .crossDissolve

            window.rootViewController?.present(hostingController, animated: true) {
                self?.acknowledgeWidget(widget.journeyStepExecutionId, action: "viewed")
            }
        }
    }
    
    private func convertToLegacyCampaign(_ widget: WidgetMessage) -> InAppCampaign {
        var interactiveConfig: [String: InAppCampaign.AnyCodable]? = nil
        if let icString = widget.metadata?["interactive_config"],
           let data = icString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            interactiveConfig = dict.mapValues { InAppCampaign.AnyCodable($0) }
        }

        return InAppCampaign(
            id: widget.id,
            type: .modal,
            subType: widget.displayType,
            title: widget.title,
            body: widget.body,
            imageUrl: widget.imageUrl,
            videoUrl: nil,
            actionUrl: widget.actionUrl,
            buttonText: widget.buttonText,
            backgroundColor: widget.backgroundColor,
            textColor: widget.textColor,
            priority: widget.priority,
            expiresAt: widget.expiresAt,
            frequency: nil,
            interactiveConfig: interactiveConfig,
            assignedVariantId: nil
        )
    }
    
    public struct InAppCampaign: Codable {
        public let id: String
        public let type: CampaignType
        public let subType: String?
        public let title: String
        public let body: String
        public let imageUrl: String?
        public let videoUrl: String?
        public let actionUrl: String?
        public let buttonText: String?
        public let backgroundColor: String?
        public let textColor: String?
        public let priority: Int
        public let expiresAt: String?
        public let frequency: FrequencyCap?
        public let interactiveConfig: [String: AnyCodable]?
        public let assignedVariantId: String?

        public enum CampaignType: String, Codable {
            case modal
            case banner
            case tooltip
            case fullScreen = "full_screen"
            case halfInterstitial = "half_interstitial"
            case alert
            case pip
        }

        public struct FrequencyCap: Codable {
            public let maxImpressions: Int?
            public let maxImpressionsPerDay: Int?
            public let cooldownSeconds: Int?
        }

        public struct AnyCodable: Codable {
            public let value: Any

            public init(_ value: Any) { self.value = value }

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let v = try? container.decode(Int.self) { value = v }
                else if let v = try? container.decode(Double.self) { value = v }
                else if let v = try? container.decode(String.self) { value = v }
                else if let v = try? container.decode(Bool.self) { value = v }
                else if let v = try? container.decode([AnyCodable].self) { value = v.map { $0.value } }
                else if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
                else { value = NSNull() }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch value {
                case let v as Int: try container.encode(v)
                case let v as Double: try container.encode(v)
                case let v as String: try container.encode(v)
                case let v as Bool: try container.encode(v)
                case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
                case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
                default: try container.encodeNil()
                }
            }
        }
    }
    
    private func acknowledgeWidget(_ stepExecutionId: String, action: String) {
        guard let writeKey = writeKey,
              let organizationId = organizationId,
              let contactId = contactId else {
            log("Cannot acknowledge widget: missing required parameters")
            return
        }
        
        let endpoint = "\(apiHost)/v1/in-app/widgets/\(stepExecutionId)/ack"
        
        guard let url = URL(string: endpoint) else {
            log("Invalid acknowledgment endpoint URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue(organizationId, forHTTPHeaderField: "X-Organization-ID")
        request.setValue(contactId, forHTTPHeaderField: "X-Contact-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let ackData: [String: String] = ["action": action]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ackData)
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.log("Failed to acknowledge widget (will retry): \(error.localizedDescription)")
                    self.queueAckForRetry(stepExecutionId: stepExecutionId, action: action)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        self.log("Widget acknowledged: \(action) for step \(stepExecutionId)")
                        self.removeFromRetryQueue(stepExecutionId: stepExecutionId, action: action)
                    } else {
                        self.log("Widget acknowledgment failed with status \(httpResponse.statusCode) (will retry)")
                        self.queueAckForRetry(stepExecutionId: stepExecutionId, action: action)
                    }
                }
            }
            
            task.resume()
        } catch {
            log("Failed to serialize acknowledgment: \(error)")
            queueAckForRetry(stepExecutionId: stepExecutionId, action: action)
        }
    }
    
    private func queueAckForRetry(stepExecutionId: String, action: String) {
        ackQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let existingIndex = self.pendingAcks.firstIndex(where: { $0.stepExecutionId == stepExecutionId && $0.action == action }) {
                var existingAck = self.pendingAcks[existingIndex]
                existingAck = PendingAck(
                    stepExecutionId: existingAck.stepExecutionId,
                    action: existingAck.action,
                    timestamp: existingAck.timestamp,
                    retryCount: existingAck.retryCount + 1
                )
                self.pendingAcks[existingIndex] = existingAck
            } else {
                let newAck = PendingAck(
                    stepExecutionId: stepExecutionId,
                    action: action,
                    timestamp: Date(),
                    retryCount: 0
                )
                self.pendingAcks.append(newAck)
            }
            
            self.savePendingAcks()
        }
    }
    
    private func removeFromRetryQueue(stepExecutionId: String, action: String) {
        ackQueue.async { [weak self] in
            guard let self = self else { return }
            self.pendingAcks.removeAll { $0.stepExecutionId == stepExecutionId && $0.action == action }
            self.savePendingAcks()
        }
    }
    
    private func retryPendingAcks() {
        ackQueue.async { [weak self] in
            guard let self = self else { return }
            
            let acksToRetry = self.pendingAcks.filter { $0.shouldRetry }
            
            for ack in acksToRetry {
                DispatchQueue.main.async {
                    self.acknowledgeWidget(ack.stepExecutionId, action: ack.action)
                }
            }
            
            self.pendingAcks.removeAll { !$0.shouldRetry }
            self.savePendingAcks()
        }
    }
    
    private func savePendingAcks() {
        guard let data = try? JSONEncoder().encode(pendingAcks) else { return }
        UserDefaults.standard.set(data, forKey: "aegis_pending_acks")
    }
    
    private func loadPendingAcks() {
        guard let data = UserDefaults.standard.data(forKey: "aegis_pending_acks"),
              let acks = try? JSONDecoder().decode([PendingAck].self, from: data) else {
            return
        }
        pendingAcks = acks
    }
    
    private func log(_ message: String) {
        if debugMode {
            print("[Active Reach InApp] \(message)")
        }
    }
}
