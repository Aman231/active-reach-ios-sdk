import Foundation
import UIKit

public class TriggerEngine {
    
    public typealias TriggerCallback = ([String: Any]) -> Void
    
    private var listeners: [String: [TriggerCallback]] = [:]
    private var isStarted = false
    
    private var scrollDepthTargets = Set<Int>()
    private var scrollDepthReached = Set<Int>()
    
    private var timeOnScreenTargets: [TimeInterval: Timer] = [:]
    private var screenLoadTime: Date?
    
    private var exitIntentEnabled = false
    private var exitIntentFired = false
    
    private var inactivityTargets: [TimeInterval: Timer] = [:]
    private var lastActivityTime = Date()
    private var inactivityCheckTimer: Timer?
    
    public init() {}
    
    public func on(eventType: String, callback: @escaping TriggerCallback) {
        if listeners[eventType] == nil {
            listeners[eventType] = []
        }
        listeners[eventType]?.append(callback)
    }
    
    public func off(eventType: String) {
        listeners.removeValue(forKey: eventType)
    }
    
    public func start() {
        guard !isStarted else { return }
        
        screenLoadTime = Date()
        lastActivityTime = Date()
        
        setupScrollTracking()
        setupInactivityTracking()
        
        isStarted = true
    }
    
    public func stop() {
        timeOnScreenTargets.values.forEach { $0.invalidate() }
        timeOnScreenTargets.removeAll()
        
        inactivityTargets.values.forEach { $0.invalidate() }
        inactivityTargets.removeAll()
        
        inactivityCheckTimer?.invalidate()
        inactivityCheckTimer = nil
        
        isStarted = false
    }
    
    public func registerScrollDepth(depthPercent: Int) {
        scrollDepthTargets.insert(depthPercent)
    }
    
    public func registerTimeOnScreen(seconds: TimeInterval) {
        guard timeOnScreenTargets[seconds] == nil else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.emit(eventType: "time_on_screen_\(Int(seconds))", data: [
                "seconds": seconds,
                "screen": self?.getCurrentScreen() ?? "unknown"
            ])
            self?.timeOnScreenTargets.removeValue(forKey: seconds)
        }
        
        timeOnScreenTargets[seconds] = timer
    }
    
    public func registerExitIntent() {
        exitIntentEnabled = true
    }
    
    public func registerInactivity(idleSeconds: TimeInterval) {
        guard inactivityTargets[idleSeconds] == nil else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: idleSeconds, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let timeSinceActivity = Date().timeIntervalSince(self.lastActivityTime)
            
            if timeSinceActivity >= idleSeconds {
                self.emit(eventType: "inactivity_\(Int(idleSeconds))", data: [
                    "idle_seconds": idleSeconds,
                    "last_activity": self.lastActivityTime.timeIntervalSince1970
                ])
            }
            
            self.inactivityTargets.removeValue(forKey: idleSeconds)
        }
        
        inactivityTargets[idleSeconds] = timer
    }
    
    public func trackScrollPosition(scrollView: UIScrollView) {
        guard isStarted else { return }
        
        let contentHeight = scrollView.contentSize.height
        let scrollOffset = scrollView.contentOffset.y
        let frameHeight = scrollView.frame.size.height
        
        guard contentHeight > 0 else { return }
        
        let scrollPercent = Int(((scrollOffset + frameHeight) / contentHeight) * 100)
        
        for target in scrollDepthTargets {
            if scrollPercent >= target && !scrollDepthReached.contains(target) {
                scrollDepthReached.insert(target)
                emit(eventType: "scroll_depth_\(target)", data: [
                    "depth_percent": target,
                    "current_scroll": scrollPercent
                ])
            }
        }
    }
    
    public func trackUserActivity() {
        lastActivityTime = Date()
        
        inactivityTargets.values.forEach { $0.invalidate() }
        inactivityTargets.removeAll()
    }
    
    private func setupScrollTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScroll(_:)),
            name: NSNotification.Name("UIScrollViewDidScroll"),
            object: nil
        )
    }
    
    private func setupInactivityTracking() {
        inactivityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let timeSinceActivity = Date().timeIntervalSince(self.lastActivityTime)
            
            for (idleSeconds, _) in self.inactivityTargets {
                if timeSinceActivity >= idleSeconds {
                    self.emit(eventType: "inactivity_\(Int(idleSeconds))", data: [
                        "idle_seconds": idleSeconds,
                        "last_activity": self.lastActivityTime.timeIntervalSince1970
                    ])
                    self.inactivityTargets.removeValue(forKey: idleSeconds)
                }
            }
        }
    }
    
    @objc private func handleScroll(_ notification: Notification) {
        guard let scrollView = notification.object as? UIScrollView else { return }
        trackScrollPosition(scrollView: scrollView)
    }
    
    private func emit(eventType: String, data: [String: Any]) {
        var eventData = data
        eventData["type"] = eventType
        eventData["timestamp"] = Date().timeIntervalSince1970
        
        listeners[eventType]?.forEach { callback in
            callback(eventData)
        }
    }
    
    private func getCurrentScreen() -> String {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return "unknown"
        }
        
        var currentVC = rootViewController
        while let presentedVC = currentVC.presentedViewController {
            currentVC = presentedVC
        }
        
        return String(describing: type(of: currentVC))
    }
    
    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
    }
}
