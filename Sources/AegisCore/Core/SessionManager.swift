import Foundation
import UIKit

/// Manages app sessions with automatic lifecycle tracking
class SessionManager {
    
    private(set) var sessionId: String
    private var sessionStartTime: Date
    private let sessionTimeout: TimeInterval
    private var eventCallback: ((SessionEvent) -> Void)?
    
    struct SessionEvent {
        let name: String
        let properties: [String: Any]
    }
    
    init(timeout: TimeInterval = 30 * 60) {
        self.sessionTimeout = timeout
        self.sessionId = UUID().uuidString
        self.sessionStartTime = Date()
    }
    
    func startTracking(eventCallback: @escaping (SessionEvent) -> Void) {
        self.eventCallback = eventCallback
        setupLifecycleObservers()
    }
    
    func reset() {
        sessionId = UUID().uuidString
        sessionStartTime = Date()
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterForeground() {
        let timeSinceBackground = Date().timeIntervalSince(sessionStartTime)
        
        if timeSinceBackground > sessionTimeout {
            // Start new session
            sessionId = UUID().uuidString
            sessionStartTime = Date()
            
            eventCallback?(SessionEvent(
                name: "Session Started",
                properties: ["session_id": sessionId]
            ))
        }
    }
    
    @objc private func appDidEnterBackground() {
        let sessionDuration = Date().timeIntervalSince(sessionStartTime)
        
        eventCallback?(SessionEvent(
            name: "Session Ended",
            properties: [
                "session_id": sessionId,
                "duration_seconds": sessionDuration
            ]
        ))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
