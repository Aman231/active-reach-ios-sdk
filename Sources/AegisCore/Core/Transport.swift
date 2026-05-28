import Foundation

/// HTTP/2 transport layer with certificate pinning, retry logic, and
/// multi-region cell selection.
///
/// `cellSelector` (when set) supplies the per-request base URL and is
/// re-consulted whenever the active cell turns unhealthy. When nil,
/// the transport falls back to `baseURL` (legacy single-host mode).
class Transport {

    private let writeKey: String
    private let baseURL: String
    private let workspaceId: String?
    private let cellSelector: CellSelector?
    private let session: URLSession
    private let certificatePinningEnabled: Bool
    private let publicKeyHashes: Set<String>

    private let maxRetries = 3
    private let initialRetryDelay: TimeInterval = 1.0

    /// Resolve the active base URL. Cell selector's pick wins when
    /// configured, else fall back to the constructor `baseURL`.
    fileprivate var activeBaseURL: String {
        cellSelector?.active()?.url ?? baseURL
    }

    /// Convenience init that matches the pre-1.1 Aegis.swift call shape
    /// `Transport(apiHost:writeKey:)` AND lets the Phase 1 wiring pass
    /// in cellSelector/workspaceId.
    convenience init(
        apiHost: String,
        writeKey: String,
        workspaceId: String? = nil,
        cellSelector: CellSelector? = nil
    ) {
        self.init(
            writeKey: writeKey,
            baseURL: apiHost,
            workspaceId: workspaceId,
            cellSelector: cellSelector
        )
    }

    init(
        writeKey: String,
        baseURL: String = "https://api.active-reach.ai",
        workspaceId: String? = nil,
        cellSelector: CellSelector? = nil,
        certificatePinningEnabled: Bool = true,
        publicKeyHashes: Set<String> = []
    ) {
        self.writeKey = writeKey
        self.baseURL = baseURL
        self.workspaceId = workspaceId
        self.cellSelector = cellSelector
        self.certificatePinningEnabled = certificatePinningEnabled
        self.publicKeyHashes = publicKeyHashes
        
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        
        // Enable HTTP/2
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "ActiveReach-iOS-SDK/1.1.0"
        ]
        
        let sessionDelegate = TransportDelegate(certificatePinningEnabled: certificatePinningEnabled, publicKeyHashes: publicKeyHashes)
        self.session = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }
    
    func sendBatch(events: [AegisEvent], completion: @escaping (Bool, [String]) -> Void) {
        guard !events.isEmpty else {
            completion(true, [])
            return
        }
        
        let endpoint = "\(activeBaseURL)/v1/batch"

        guard let url = URL(string: endpoint) else {
            completion(false, events.map { $0.messageId })
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        if let ws = workspaceId {
            request.setValue(ws, forHTTPHeaderField: "X-Workspace-Id")
        }
        
        do {
            let batchPayload = BatchPayload(batch: events)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(batchPayload)
            
            // Compress with gzip if payload > 1KB
            if jsonData.count > 1024 {
                request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                request.httpBody = try jsonData.gzipped()
            } else {
                request.httpBody = jsonData
            }
            
            sendWithRetry(request: request, events: events, retryCount: 0, completion: completion)
        } catch {
            print("[Active Reach] Failed to encode batch: \(error)")
            completion(false, events.map { $0.messageId })
        }
    }
    
    private func sendWithRetry(request: URLRequest, events: [AegisEvent], retryCount: Int, completion: @escaping (Bool, [String]) -> Void) {
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[Active Reach] Network error: \(error.localizedDescription)")
                self.handleRetry(request: request, events: events, retryCount: retryCount, completion: completion)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(false, events.map { $0.messageId })
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                completion(true, [])
                
            case 400, 413:
                // Bad request or payload too large - don't retry
                print("[Active Reach] Bad request (status \(httpResponse.statusCode))")
                completion(false, events.map { $0.messageId })
                
            case 429:
                // Rate limited - retry with exponential backoff
                print("[Active Reach] Rate limited")
                self.handleRetry(request: request, events: events, retryCount: retryCount, completion: completion)
                
            case 500...599:
                // Server error - retry
                print("[Active Reach] Server error (status \(httpResponse.statusCode))")
                self.handleRetry(request: request, events: events, retryCount: retryCount, completion: completion)
                
            default:
                // Unknown status - don't retry
                print("[Active Reach] Unexpected status: \(httpResponse.statusCode)")
                completion(false, events.map { $0.messageId })
            }
        }
        
        task.resume()
    }
    
    private func handleRetry(request: URLRequest, events: [AegisEvent], retryCount: Int, completion: @escaping (Bool, [String]) -> Void) {
        guard retryCount < maxRetries else {
            completion(false, events.map { $0.messageId })
            return
        }
        
        // Exponential backoff: 1s, 2s, 4s
        let delay = initialRetryDelay * pow(2.0, Double(retryCount))
        
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.sendWithRetry(request: request, events: events, retryCount: retryCount + 1, completion: completion)
        }
    }
}

// MARK: - Transport Delegate (Certificate Pinning)

private class TransportDelegate: NSObject, URLSessionDelegate {
    
    private let certificatePinningEnabled: Bool
    private let publicKeyHashes: Set<String>
    
    init(certificatePinningEnabled: Bool, publicKeyHashes: Set<String>) {
        self.certificatePinningEnabled = certificatePinningEnabled
        self.publicKeyHashes = publicKeyHashes
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        guard certificatePinningEnabled,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Evaluate server trust
        var secresult = SecTrustResultType.invalid
        let status = SecTrustEvaluate(serverTrust, &secresult)
        
        guard status == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Extract public key
        guard let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let serverPublicKey = SecCertificateCopyKey(serverCertificate),
              let serverPublicKeyData = SecKeyCopyExternalRepresentation(serverPublicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Hash the public key
        let serverKeyHash = sha256(data: serverPublicKeyData)
        
        // Check if hash matches any pinned hashes
        if publicKeyHashes.isEmpty || publicKeyHashes.contains(serverKeyHash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            print("[Active Reach] Certificate pinning failed")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func sha256(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Batch Payload

private struct BatchPayload: Codable {
    let batch: [AegisEvent]
}

// MARK: - Gzip Compression

import Compression

extension Data {
    func gzipped() throws -> Data {
        var result = Data()
        
        try self.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) in
            let sourceBuffer = sourcePtr.bindMemory(to: UInt8.self)
            let destinationBufferSize = self.count
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
            defer { destinationBuffer.deallocate() }
            
            let algorithm = COMPRESSION_ZLIB
            let compressedSize = compression_encode_buffer(destinationBuffer, destinationBufferSize,
                                                          sourceBuffer.baseAddress!, self.count,
                                                          nil, algorithm)
            
            guard compressedSize > 0 else {
                throw NSError(domain: "Aegis", code: -1, userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
            }
            
            result = Data(bytes: destinationBuffer, count: compressedSize)
        }
        
        return result
    }
}

// Import CommonCrypto for SHA256
import CommonCrypto
