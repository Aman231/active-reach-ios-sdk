import Foundation
import UIKit
import UserNotifications

class AegisPushSwizzler: NSObject {
    
    static let shared = AegisPushSwizzler()
    
    private var originalDidRegisterForRemoteNotifications: IMP?
    private var originalDidFailToRegisterForRemoteNotifications: IMP?
    private var originalDidReceiveRemoteNotification: IMP?
    
    var onTokenReceived: ((String) -> Void)?
    var onTokenFailed: ((Error) -> Void)?
    var onNotificationReceived: (([AnyHashable: Any]) -> Void)?
    
    private override init() {
        super.init()
    }
    
    func swizzleAppDelegate() {
        guard let appDelegate = UIApplication.shared.delegate else {
            print("[Active Reach Push] No app delegate found")
            return
        }
        
        let appDelegateClass: AnyClass = object_getClass(appDelegate)!
        
        swizzleDidRegisterForRemoteNotifications(in: appDelegateClass)
        swizzleDidFailToRegisterForRemoteNotifications(in: appDelegateClass)
        swizzleDidReceiveRemoteNotification(in: appDelegateClass)
    }
    
    private func swizzleDidRegisterForRemoteNotifications(in appDelegateClass: AnyClass) {
        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(swizzled_didRegisterForRemoteNotifications(_:deviceToken:))
        
        swizzleMethod(
            in: appDelegateClass,
            original: originalSelector,
            swizzled: swizzledSelector,
            originalIMP: &originalDidRegisterForRemoteNotifications
        )
    }
    
    private func swizzleDidFailToRegisterForRemoteNotifications(in appDelegateClass: AnyClass) {
        let originalSelector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        let swizzledSelector = #selector(swizzled_didFailToRegisterForRemoteNotifications(_:error:))
        
        swizzleMethod(
            in: appDelegateClass,
            original: originalSelector,
            swizzled: swizzledSelector,
            originalIMP: &originalDidFailToRegisterForRemoteNotifications
        )
    }
    
    private func swizzleDidReceiveRemoteNotification(in appDelegateClass: AnyClass) {
        let originalSelector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        let swizzledSelector = #selector(swizzled_didReceiveRemoteNotification(_:userInfo:fetchCompletionHandler:))
        
        swizzleMethod(
            in: appDelegateClass,
            original: originalSelector,
            swizzled: swizzledSelector,
            originalIMP: &originalDidReceiveRemoteNotification
        )
    }
    
    private func swizzleMethod(
        in targetClass: AnyClass,
        original originalSelector: Selector,
        swizzled swizzledSelector: Selector,
        originalIMP: inout IMP?
    ) {
        guard let swizzledMethod = class_getInstanceMethod(type(of: self), swizzledSelector) else {
            print("[Active Reach Push] Swizzled method not found: \(swizzledSelector)")
            return
        }
        
        let swizzledImplementation = method_getImplementation(swizzledMethod)
        let swizzledTypeEncoding = method_getTypeEncoding(swizzledMethod)
        
        if let originalMethod = class_getInstanceMethod(targetClass, originalSelector) {
            originalIMP = method_getImplementation(originalMethod)
            method_setImplementation(originalMethod, swizzledImplementation)
        } else {
            class_addMethod(
                targetClass,
                originalSelector,
                swizzledImplementation,
                swizzledTypeEncoding
            )
        }
    }
    
    @objc private func swizzled_didRegisterForRemoteNotifications(
        _ application: UIApplication,
        deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        onTokenReceived?(token)
        
        if let originalIMP = originalDidRegisterForRemoteNotifications {
            typealias MethodType = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
            let method = unsafeBitCast(originalIMP, to: MethodType.self)
            method(self, #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)), application, deviceToken)
        }
    }
    
    @objc private func swizzled_didFailToRegisterForRemoteNotifications(
        _ application: UIApplication,
        error: Error
    ) {
        onTokenFailed?(error)
        
        if let originalIMP = originalDidFailToRegisterForRemoteNotifications {
            typealias MethodType = @convention(c) (AnyObject, Selector, UIApplication, Error) -> Void
            let method = unsafeBitCast(originalIMP, to: MethodType.self)
            method(self, #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)), application, error)
        }
    }
    
    @objc private func swizzled_didReceiveRemoteNotification(
        _ application: UIApplication,
        userInfo: [AnyHashable: Any],
        fetchCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        onNotificationReceived?(userInfo)
        
        if let originalIMP = originalDidReceiveRemoteNotification {
            typealias MethodType = @convention(c) (AnyObject, Selector, UIApplication, [AnyHashable: Any], @escaping (UIBackgroundFetchResult) -> Void) -> Void
            let method = unsafeBitCast(originalIMP, to: MethodType.self)
            method(self, #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)), application, userInfo, fetchCompletionHandler)
        } else {
            fetchCompletionHandler(.newData)
        }
    }
}
