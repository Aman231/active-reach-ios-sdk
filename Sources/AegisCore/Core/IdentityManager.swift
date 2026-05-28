import Foundation
import Security

/// Manages user identity (anonymous ID and user ID)
class IdentityManager {
    
    private let keychainService = "ai.aegis.sdk"
    private let anonymousIdKey = "aegis_anonymous_id"
    private let userIdKey = "aegis_user_id"
    
    private(set) var anonymousId: String
    private(set) var userId: String?
    
    init() {
        // Swift requires all stored properties to be initialised before
        // `self`-methods are called. Use static-context Keychain reads
        // to populate the locals, assign, then run any post-init save.
        let storedAnon = IdentityManager.loadFromKeychainStatic(key: "aegis_anonymous_id")
        let storedUser = IdentityManager.loadFromKeychainStatic(key: "aegis_user_id")

        if let existingId = storedAnon {
            anonymousId = existingId
        } else {
            let fresh = UUID().uuidString
            anonymousId = fresh
            // Stored properties are now initialised — instance method OK.
            saveToKeychain(key: anonymousIdKey, value: fresh)
        }
        userId = storedUser
    }

    /// Static-context Keychain read used during init() before `self` is
    /// fully initialised. Mirrors the body of the instance-level
    /// `loadFromKeychain(key:)`.
    private static func loadFromKeychainStatic(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrAccount as String:     key,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne,
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func identify(userId: String) {
        self.userId = userId
        saveToKeychain(key: userIdKey, value: userId)
    }
    
    func reset() {
        userId = nil
        deleteFromKeychain(key: userIdKey)
        
        // Generate new anonymous ID
        anonymousId = UUID().uuidString
        saveToKeychain(key: anonymousIdKey, value: anonymousId)
    }
    
    // MARK: - Keychain Operations
    
    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
