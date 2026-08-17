import Foundation

/// How dangerous a tool is. `.confirm` tools require explicit user approval before running.
public enum ToolRisk: String, Codable, Sendable {
    case safe
    case confirm
}

/// A minimal JSON Schema for describing tool parameters to the model and validating its calls.
public struct JSONSchema: Codable, Equatable, Sendable {
    public enum SchemaType: String, Codable, Sendable {
        case object, string, number, integer, boolean, array
    }

    public var type: SchemaType
    public var description: String?
    public var properties: [String: JSONSchema]?
    public var required: [String]?
    /// Element type for `array` schemas. Nested objects inside arrays are intentionally unsupported.
    public var itemType: SchemaType?
    public var enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description, properties, required
        case itemType = "items"
        case enumValues = "enum"
    }

    public init(
        type: SchemaType,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        itemType: SchemaType? = nil,
        enumValues: [String]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.itemType = itemType
        self.enumValues = enumValues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(SchemaType.self, forKey: .type)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        properties = try container.decodeIfPresent([String: JSONSchema].self, forKey: .properties)
        required = try container.decodeIfPresent([String].self, forKey: .required)
        enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
        // "items" is serialized as a schema object per JSON Schema convention
        if let items = try container.decodeIfPresent(ItemsSchema.self, forKey: .itemType) {
            itemType = items.type
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(properties, forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
        try container.encodeIfPresent(enumValues, forKey: .enumValues)
        if let itemType {
            try container.encode(ItemsSchema(type: itemType), forKey: .itemType)
        }
    }

    private struct ItemsSchema: Codable {
        var type: SchemaType
    }
}

/// The full description of one tool the model may call.
public struct ToolSpec: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONSchema
    public let risk: ToolRisk

    public init(name: String, description: String, parameters: JSONSchema, risk: ToolRisk) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.risk = risk
    }
}
