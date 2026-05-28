import Foundation

/// Event types supported by Active Reach SDK
public enum EventType: String, Codable {
    case track
    case identify
    case screen
    case group
    case alias
}

/// Main event structure.
///
/// Conforms to `Codable` because `EventQueue` reads persisted events back
/// from local SQLite (offline replay) and decodes them. The `[String: Any]?`
/// properties dict can't be auto-synthesized; both `encode(to:)` and
/// `init(from:)` are implemented below using the AnyCodable helper.
public struct AegisEvent: Codable {
    public let messageId: String
    public let type: EventType
    public let name: String
    public let properties: [String: Any]?
    public let userId: String?
    public let anonymousId: String
    public let groupId: String?
    public let sessionId: String?
    public let context: EventContext?
    public let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case type
        case name
        case properties
        case userId = "user_id"
        case anonymousId = "anonymous_id"
        case groupId = "group_id"
        case sessionId = "session_id"
        case context
        case timestamp
    }
    
    public init(
        type: EventType,
        name: String,
        properties: [String: Any]? = nil,
        userId: String? = nil,
        anonymousId: String,
        groupId: String? = nil,
        sessionId: String? = nil,
        context: EventContext? = nil,
        timestamp: Date = Date()
    ) {
        self.messageId = UUID().uuidString
        self.type = type
        self.name = name
        self.properties = properties
        self.userId = userId
        self.anonymousId = anonymousId
        self.groupId = groupId
        self.sessionId = sessionId
        self.context = context
        self.timestamp = timestamp
    }
    
    // Custom encoding for [String: Any]
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(anonymousId, forKey: .anonymousId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encode(timestamp, forKey: .timestamp)

        if let properties = properties {
            let jsonData = try JSONSerialization.data(withJSONObject: properties)
            let jsonObject = try JSONDecoder().decode(AnyCodable.self, from: jsonData)
            try container.encode(jsonObject, forKey: .properties)
        }
    }

    // Custom decoding for [String: Any]? properties — inverse of encode(to:).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messageId = try container.decode(String.self, forKey: .messageId)
        self.type = try container.decode(EventType.self, forKey: .type)
        self.name = try container.decode(String.self, forKey: .name)
        self.userId = try container.decodeIfPresent(String.self, forKey: .userId)
        self.anonymousId = try container.decode(String.self, forKey: .anonymousId)
        self.groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.context = try container.decodeIfPresent(EventContext.self, forKey: .context)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Round-trip [String: Any]? via AnyCodable.
        if let anyCodable = try container.decodeIfPresent(AnyCodable.self, forKey: .properties) {
            let jsonData = try JSONEncoder().encode(anyCodable)
            self.properties = (try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        } else {
            self.properties = nil
        }
    }
}

/// Event context structure
public struct EventContext: Codable {
    public let library: LibraryInfo
    public let device: DeviceInfo?
    public let os: OSInfo?
    public let app: AppInfo?
    public let screen: ScreenInfo?
    public let network: NetworkInfo?
    public let battery: BatteryInfo?
    public let locale: String?
    public let timezone: String?
    public let cell: CellInfo?
    
    enum CodingKeys: String, CodingKey {
        case library, device, os, app, screen, network, battery, locale, timezone, cell
    }
}

public struct LibraryInfo: Codable {
    public let name: String
    public let version: String
}

public struct DeviceInfo: Codable {
    public let type: String
    public let manufacturer: String
    public let model: String
    public let id: String
    public let advertisingId: String?
    
    enum CodingKeys: String, CodingKey {
        case type, manufacturer, model, id
        case advertisingId = "advertising_id"
    }
}

public struct OSInfo: Codable {
    public let name: String
    public let version: String
}

public struct AppInfo: Codable {
    public let name: String
    public let version: String
    public let build: String
}

public struct ScreenInfo: Codable {
    public let width: Int
    public let height: Int
    public let density: Double
}

public struct NetworkInfo: Codable {
    public let carrier: String?
    public let connectionType: String
    public let effectiveType: String?
    
    enum CodingKeys: String, CodingKey {
        case carrier
        case connectionType = "connection_type"
        case effectiveType = "effective_type"
    }
}

public struct BatteryInfo: Codable {
    public let level: Double
    public let isCharging: Bool
    
    enum CodingKeys: String, CodingKey {
        case level
        case isCharging = "is_charging"
    }
}

public struct CellInfo: Codable {
    public let region: String
    public let endpoint: String
}

// Helper for encoding Any type
private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictValue = value as? [String: Any] {
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
