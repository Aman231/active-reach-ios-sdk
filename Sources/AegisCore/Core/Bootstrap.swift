import Foundation

/// SDK bootstrap handshake. Parity port of
/// the web SDK source.
///
/// A successful bootstrap resolves writeKey → propertyId, returns the
/// VAPID public key (mobile ignores), workspace + organisation ids,
/// allowed origins, and the event-governance hint that drives the
/// client-side NameGovernor. A failed bootstrap (401/403) aborts SDK
/// init — the SDK refuses to emit events against an origin/install it
/// cannot prove ownership of.
///
/// iOS substitutes the application's bundle identifier as the origin
/// assertion (the gateway whitelists `aegis-ios://<bundle.id>` per
/// property).

public struct BootstrapRequest {
    public let writeKey: String
    public let bundleIdentifier: String
    public let deviceFingerprint: String?
    public let attestationToken: String?
    public let userAgent: String?

    public init(
        writeKey: String,
        bundleIdentifier: String,
        deviceFingerprint: String? = nil,
        attestationToken: String? = nil,
        userAgent: String? = nil
    ) {
        self.writeKey = writeKey
        self.bundleIdentifier = bundleIdentifier
        self.deviceFingerprint = deviceFingerprint
        self.attestationToken = attestationToken
        self.userAgent = userAgent
    }
}

public struct BootstrapResult {
    public let propertyId: String
    public let organizationId: String
    public let workspaceId: String
    public let propertyType: String
    public let pushEnabled: Bool
    public let inAppEnabled: Bool
    public let transportMode: String
    public let allowedOrigins: [String]
    public let locationCodes: [String]
    public let eventGovernance: EventGovernanceHint?
}

public enum BootstrapError: Error {
    case sdkNotInitialised
    case httpError(status: Int, body: String)
    case decodeError(String)
    case networkError(Error)
}

public enum Bootstrap {

    /// Perform the bootstrap handshake. Runs on a background URLSession;
    /// callers receive the result/error on the calling-thread completion.
    public static func perform(
        apiHost: String,
        request: BootstrapRequest,
        session: URLSession = .shared,
        completion: @escaping (Swift.Result<BootstrapResult, BootstrapError>) -> Void
    ) {
        guard let url = URL(string: "\(apiHost)/v1/sdk/bootstrap") else {
            completion(.failure(.decodeError("invalid apiHost")))
            return
        }

        var body: [String: Any] = [
            "writeKey": request.writeKey,
            "currentOrigin": "aegis-ios://\(request.bundleIdentifier)",
            "platform": "ios",
        ]
        request.deviceFingerprint.map { body["deviceFingerprint"] = $0 }
        request.attestationToken.map { body["attestationToken"] = $0 }
        request.userAgent.map { body["userAgent"] = $0 }

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.decodeError("failed to encode bootstrap body")))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = payload
        req.setValue(request.writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(
            request.userAgent ?? "ActiveReach-iOS-SDK/\(AegisVersion.current)",
            forHTTPHeaderField: "User-Agent"
        )

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data = data else {
                completion(.failure(.httpError(status: status, body: "")))
                return
            }
            guard (200..<300).contains(status) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(.httpError(status: status, body: body)))
                return
            }
            do {
                let result = try Self.decode(data: data)
                completion(.success(result))
            } catch {
                completion(.failure(.decodeError(error.localizedDescription)))
            }
        }.resume()
    }

    private static func decode(data: Data) throws -> BootstrapResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BootstrapError.decodeError("response not a JSON object")
        }
        let allowedOrigins = (json["allowedOrigins"] as? [String]) ?? []
        // locationCodes wins post-P15.1 (2026-05-26); workspaceCodes is the
        // legacy alias kept for the deprecation window.
        let locationCodes = (json["locationCodes"] as? [String])
            ?? (json["workspaceCodes"] as? [String])
            ?? []

        var hint: EventGovernanceHint?
        if let obj = json["eventGovernance"] as? [String: Any] {
            hint = EventGovernanceHint(
                bloomAlgo: (obj["bloom_algo"] as? String) ?? "mmh3_x86_32_km",
                seedA: UInt32((obj["seed_a"] as? Int) ?? 0),
                seedB: UInt32((obj["seed_b"] as? Int) ?? 0),
                k: (obj["k"] as? Int) ?? 0,
                m: (obj["m"] as? Int) ?? 0,
                bloomB64: (obj["bloom_b64"] as? String) ?? "",
                remainingNewNames: obj["remaining_new_names"] as? Int,
                graceActive: (obj["grace_active"] as? Bool) ?? false,
                ttlSeconds: (obj["ttl_seconds"] as? Int) ?? 300
            )
        }

        return BootstrapResult(
            propertyId: (json["propertyId"] as? String) ?? "",
            organizationId: (json["organizationId"] as? String) ?? "",
            workspaceId: (json["workspaceId"] as? String) ?? "",
            propertyType: (json["propertyType"] as? String) ?? "mobile_app",
            pushEnabled: (json["pushEnabled"] as? Bool) ?? false,
            inAppEnabled: (json["inAppEnabled"] as? Bool) ?? true,
            transportMode: (json["transportMode"] as? String) ?? "http_batch",
            allowedOrigins: allowedOrigins,
            locationCodes: locationCodes,
            eventGovernance: hint
        )
    }
}

/// SDK version constant. Kept in lockstep with the web SDK per
/// the cross-SDK parity matrix — when web ships a minor, the iOS SDK
/// matches in the same release window.
public enum AegisVersion {
    public static let current = "1.6.0"
    public static var userAgent: String { "ActiveReach-iOS-SDK/\(current)" }
}
