import Foundation
import UIKit

public class DeepLinkRouter {
    
    public static let shared = DeepLinkRouter()
    
    private var routes: [String: (DeepLink) -> Bool] = [:]
    private var fallbackHandler: ((DeepLink) -> Bool)?
    private var debugMode = false
    
    public struct DeepLink {
        public let url: URL
        public let scheme: String?
        public let host: String?
        public let path: String
        public let pathComponents: [String]
        public let queryItems: [String: String]
        public let fragment: String?
        
        init(url: URL) {
            self.url = url
            self.scheme = url.scheme
            self.host = url.host
            self.path = url.path
            self.pathComponents = url.pathComponents.filter { $0 != "/" }
            
            var queryDict: [String: String] = [:]
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                for item in queryItems {
                    queryDict[item.name] = item.value
                }
            }
            self.queryItems = queryDict
            self.fragment = url.fragment
        }
    }
    
    private init() {}
    
    public func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
    }
    
    public func registerRoute(_ pattern: String, handler: @escaping (DeepLink) -> Bool) {
        routes[pattern] = handler
        log("Registered route: \(pattern)")
    }
    
    public func setFallbackHandler(_ handler: @escaping (DeepLink) -> Bool) {
        fallbackHandler = handler
        log("Fallback handler registered")
    }
    
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        let deepLink = DeepLink(url: url)
        log("Handling deep link: \(url.absoluteString)")
        
        for (pattern, handler) in routes {
            if matches(deepLink: deepLink, pattern: pattern) {
                log("Matched route pattern: \(pattern)")
                let handled = handler(deepLink)
                if handled {
                    log("Route handler succeeded")
                    return true
                }
            }
        }
        
        if let fallbackHandler = fallbackHandler {
            log("Using fallback handler")
            return fallbackHandler(deepLink)
        }
        
        log("No handler found for deep link")
        return false
    }
    
    public func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            log("Invalid URL: \(urlString)")
            return
        }
        
        if handle(url) {
            return
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                self.log("Opened URL externally: \(success)")
            }
        }
    }
    
    private func matches(deepLink: DeepLink, pattern: String) -> Bool {
        guard let patternUrl = URL(string: pattern.hasPrefix("http") ? pattern : "app://\(pattern)") else {
            return false
        }
        
        if let scheme = patternUrl.scheme, deepLink.scheme != scheme {
            return false
        }
        
        if let host = patternUrl.host, deepLink.host != host {
            return false
        }
        
        let patternComponents = patternUrl.pathComponents.filter { $0 != "/" }
        
        if patternComponents.count != deepLink.pathComponents.count {
            return false
        }
        
        for (index, component) in patternComponents.enumerated() {
            if component.hasPrefix(":") {
                continue
            }
            
            if component != deepLink.pathComponents[index] {
                return false
            }
        }
        
        return true
    }
    
    public func extractParameters(from deepLink: DeepLink, pattern: String) -> [String: String] {
        var params: [String: String] = [:]
        
        guard let patternUrl = URL(string: pattern.hasPrefix("http") ? pattern : "app://\(pattern)") else {
            return params
        }
        
        let patternComponents = patternUrl.pathComponents.filter { $0 != "/" }
        
        for (index, component) in patternComponents.enumerated() {
            if component.hasPrefix(":") {
                let paramName = String(component.dropFirst())
                params[paramName] = deepLink.pathComponents[index]
            }
        }
        
        return params
    }
    
    private func log(_ message: String) {
        if debugMode {
            print("[DeepLinkRouter] \(message)")
        }
    }
}

public extension DeepLinkRouter {
    func registerCommonRoutes() {
        registerRoute("aegis://products/:id") { deepLink in
            let params = self.extractParameters(from: deepLink, pattern: "aegis://products/:id")
            self.log("Product deep link: \(params)")
            return false
        }
        
        registerRoute("aegis://cart") { deepLink in
            self.log("Cart deep link")
            return false
        }
        
        registerRoute("aegis://checkout") { deepLink in
            self.log("Checkout deep link")
            return false
        }
        
        registerRoute("aegis://profile") { deepLink in
            self.log("Profile deep link")
            return false
        }
    }
}
