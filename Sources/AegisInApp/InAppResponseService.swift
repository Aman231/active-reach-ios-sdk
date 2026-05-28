import Foundation

/// Shared service for submitting in-app interactive responses
/// (NPS, poll, quiz, rating, spin, scratch, form, countdown)
public class InAppResponseService {

    let apiHost: String
    let writeKey: String?
    let organizationId: String?
    let userId: String?
    let contactId: String?

    public init(apiHost: String, writeKey: String?, organizationId: String?, userId: String?, contactId: String?) {
        self.apiHost = apiHost
        self.writeKey = writeKey
        self.organizationId = organizationId
        self.userId = userId
        self.contactId = contactId
    }

    /// Submit an interactive response (NPS, poll, quiz, rating, form, countdown).
    /// POST /api/v1/in_app/responses
    public func submitResponse(
        campaignId: String,
        responseType: String,
        payload: [String: Any],
        variantId: String? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let writeKey = writeKey else {
            completion(.failure(NSError(domain: "AegisInApp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing write key"])))
            return
        }

        var body: [String: Any] = [
            "campaign_id": campaignId,
            "response_type": responseType,
            "platform": "ios",
            "payload": payload
        ]
        if let userId = userId { body["user_id"] = userId }
        if let contactId = contactId { body["contact_id"] = contactId }
        if let variantId = variantId { body["variant_id"] = variantId }

        post(endpoint: "\(apiHost)/api/v1/in_app/responses", body: body, writeKey: writeKey, completion: completion)
    }

    /// Submit spin wheel play.
    /// POST /v1/widgets/spin-wheel/submit
    public func submitSpinWheel(
        phone: String,
        email: String? = nil,
        name: String? = nil,
        cartTotal: Double = 0,
        cartCurrency: String = "USD",
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let writeKey = writeKey else {
            completion(.failure(NSError(domain: "AegisInApp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing write key"])))
            return
        }

        var body: [String: Any] = [
            "phone": phone,
            "cart_id": "ios_\(Int(Date().timeIntervalSince1970 * 1000))",
            "cart_total": cartTotal,
            "cart_currency": cartCurrency,
            "cart_items": [] as [Any],
            "platform": "ios",
            "geo_region": detectGeoRegion(),
            "device_type": "mobile"
        ]
        if let email = email { body["email"] = email }
        if let name = name { body["name"] = name }

        post(endpoint: "\(apiHost)/v1/widgets/spin-wheel/submit", body: body, writeKey: writeKey, completion: completion)
    }

    /// Generate scratch card prize.
    /// POST /v1/widgets/gamification/generate-prize
    public func generateScratchPrize(
        configId: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let writeKey = writeKey else {
            completion(.failure(NSError(domain: "AegisInApp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing write key"])))
            return
        }

        let body: [String: Any] = ["config_id": configId]
        post(endpoint: "\(apiHost)/v1/widgets/gamification/generate-prize", body: body, writeKey: writeKey, completion: completion)
    }

    // MARK: - Private

    private func post(endpoint: String, body: [String: Any], writeKey: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(.failure(NSError(domain: "AegisInApp", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(writeKey, forHTTPHeaderField: "X-Aegis-Write-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let orgId = organizationId { request.setValue(orgId, forHTTPHeaderField: "X-Organization-ID") }
        if let uid = userId { request.setValue(uid, forHTTPHeaderField: "X-User-ID") }
        if let cid = contactId { request.setValue(cid, forHTTPHeaderField: "X-Contact-ID") }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AegisInApp", code: httpCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpCode)"])))
                }
                return
            }
            DispatchQueue.main.async { completion(.success(dict)) }
        }.resume()
    }

    private func detectGeoRegion() -> String {
        let tz = TimeZone.current.identifier
        if tz.contains("America") { return "north_america" }
        if tz.contains("Europe") { return "europe" }
        if tz.contains("Asia/Kolkata") || tz.contains("Asia/Calcutta") { return "india" }
        if tz.contains("Asia/Singapore") || tz.contains("Asia/Bangkok") || tz.contains("Asia/Jakarta") { return "southeast_asia" }
        if tz.contains("Asia/Dubai") || tz.contains("Asia/Riyadh") { return "middle_east" }
        if tz.contains("Sao_Paulo") || tz.contains("Buenos_Aires") { return "latin_america" }
        if tz.contains("Australia") || tz.contains("Pacific/Auckland") { return "oceania" }
        return "north_america"
    }
}
