import Foundation
import SQLite

/// Event queue with SQLite persistence and AES-256 encryption
class EventQueue {
    
    private let db: Connection
    private let events = Table("events")
    private let id = Expression<Int64>("id")
    private let messageId = Expression<String>("message_id")
    private let eventData = Expression<Data>("event_data")
    private let timestamp = Expression<Date>("timestamp")
    private let retryCount = Expression<Int>("retry_count")
    
    private var batchSize: Int
    private var batchInterval: TimeInterval
    private let transport: Transport
    private let encryptionEnabled: Bool
    private var timer: Timer?
    private let maxRetries = 3
    private let maxEvents = 10000
    
    private let encryptionKey: Data
    
    init(batchSize: Int, batchInterval: TimeInterval, transport: Transport, encryptionEnabled: Bool) {
        self.batchSize = batchSize
        self.batchInterval = batchInterval
        self.transport = transport
        self.encryptionEnabled = encryptionEnabled
        
        // Generate or load encryption key from Keychain
        if let existingKey = KeychainHelper.load(key: "aegis_encryption_key") {
            self.encryptionKey = existingKey
        } else {
            self.encryptionKey = SymmetricKey.generate()
            KeychainHelper.save(key: "aegis_encryption_key", data: encryptionKey)
        }
        
        // Setup SQLite database
        let fileURL = try! FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("aegis_events.db")
        
        self.db = try! Connection(fileURL.path)
        
        createTable()
        setupBatchTimer()
        cleanupOldEvents()
    }
    
    private func createTable() {
        try? db.run(events.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(messageId, unique: true)
            t.column(eventData)
            t.column(timestamp)
            t.column(retryCount, defaultValue: 0)
        })
        
        // Create index on timestamp for efficient queries
        try? db.run(events.createIndex(timestamp, ifNotExists: true))
    }
    
    func enqueue(_ event: AegisEvent) {
        guard count() < maxEvents else {
            print("[Active Reach] Event queue full. Dropping oldest events.")
            deleteOldest(count: 100)
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var eventData = try encoder.encode(event)
            
            // Encrypt if enabled
            if encryptionEnabled {
                eventData = try AESEncryption.encrypt(data: eventData, key: encryptionKey)
            }
            
            try db.run(events.insert(
                messageId <- event.messageId,
                self.eventData <- eventData,
                timestamp <- event.timestamp,
                retryCount <- 0
            ))
            
            // Check if we should flush immediately
            if count() >= batchSize {
                flush()
            }
        } catch {
            print("[Active Reach] Failed to enqueue event: \(error)")
        }
    }
    
    func flush() {
        let batch = fetchBatch(limit: batchSize)
        
        guard !batch.isEmpty else { return }
        
        transport.sendBatch(events: batch) { [weak self] success, failedEventIds in
            if success {
                self?.delete(messageIds: batch.map { $0.messageId })
            } else {
                self?.incrementRetryCount(messageIds: failedEventIds)
                // Remove events that exceeded max retries
                self?.deleteMaxRetried()
            }
        }
    }
    
    func updateBatchSize(_ size: Int) {
        self.batchSize = size
    }
    
    func updateBatchInterval(_ interval: TimeInterval) {
        self.batchInterval = interval
        setupBatchTimer()
    }
    
    private func fetchBatch(limit: Int) -> [AegisEvent] {
        var eventsList: [AegisEvent] = []
        
        do {
            let query = events
                .filter(retryCount < maxRetries)
                .order(timestamp.asc)
                .limit(limit)
            
            for row in try db.prepare(query) {
                var eventData = try row.get(self.eventData)
                
                // Decrypt if enabled
                if encryptionEnabled {
                    eventData = try AESEncryption.decrypt(data: eventData, key: encryptionKey)
                }
                
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let event = try decoder.decode(AegisEvent.self, from: eventData)
                eventsList.append(event)
            }
        } catch {
            print("[Active Reach] Failed to fetch batch: \(error)")
        }
        
        return eventsList
    }
    
    private func count() -> Int {
        return (try? db.scalar(events.count)) ?? 0
    }
    
    private func delete(messageIds: [String]) {
        do {
            for msgId in messageIds {
                try db.run(events.filter(messageId == msgId).delete())
            }
        } catch {
            print("[Active Reach] Failed to delete events: \(error)")
        }
    }
    
    private func deleteOldest(count: Int) {
        do {
            let oldestEvents = events.order(timestamp.asc).limit(count)
            try db.run(oldestEvents.delete())
        } catch {
            print("[Active Reach] Failed to delete oldest events: \(error)")
        }
    }
    
    private func incrementRetryCount(messageIds: [String]) {
        do {
            for msgId in messageIds {
                let event = events.filter(messageId == msgId)
                try db.run(event.update(retryCount += 1))
            }
        } catch {
            print("[Active Reach] Failed to increment retry count: \(error)")
        }
    }
    
    private func deleteMaxRetried() {
        do {
            try db.run(events.filter(retryCount >= maxRetries).delete())
        } catch {
            print("[Active Reach] Failed to delete max retried events: \(error)")
        }
    }
    
    private func cleanupOldEvents() {
        // Delete events older than 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        do {
            try db.run(events.filter(timestamp < thirtyDaysAgo).delete())
        } catch {
            print("[Active Reach] Failed to cleanup old events: \(error)")
        }
    }
    
    private func setupBatchTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - AES Encryption Helper

private class AESEncryption {
    static func encrypt(data: Data, key: Data) throws -> Data {
        let iv = SymmetricKey.generateIV()
        let encrypted = try CryptoKit.AES.GCM.seal(data, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv))
        
        // Combine IV + encrypted data
        var result = Data()
        result.append(iv)
        result.append(encrypted.ciphertext)
        result.append(encrypted.tag)
        return result
    }
    
    static func decrypt(data: Data, key: Data) throws -> Data {
        let ivSize = 12
        let tagSize = 16
        
        let iv = data.prefix(ivSize)
        let tag = data.suffix(tagSize)
        let ciphertext = data.dropFirst(ivSize).dropLast(tagSize)
        
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: ciphertext,
            tag: tag
        )
        
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
    }
}

// MARK: - Symmetric Key Helper

import CryptoKit

private extension SymmetricKey {
    static func generate() -> Data {
        return SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
    
    static func generateIV() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

// MARK: - Keychain Helper

private class KeychainHelper {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        return status == errSecSuccess ? result as? Data : nil
    }
}
