import Foundation

/// Keeps fields from newer Android/native releases during editable round trips.
public enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }

    public static func decode(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String, _ fallback: String = "") -> String { self[key]?.string ?? fallback }
    func number(_ key: String, _ fallback: Double = 0) -> Double { self[key]?.number ?? fallback }
    func flag(_ key: String, _ fallback: Bool = false) -> Bool { self[key]?.bool ?? fallback }
    func list(_ key: String) -> [JSONValue] { self[key]?.array ?? [] }
}

public enum FolioError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw FolioError.invalid(message) }
}

public enum Identity {
    public static func new() -> String { UUID().uuidString.lowercased() }
    public static func valid(_ value: String) -> Bool {
        value.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value
    }
    public static func asset(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let name = String(parts[1]), ext = (name as NSString).pathExtension
        return ((parts[0] == "pdfs" && ext == "pdf") || (parts[0] == "audio" && ext == "m4a"))
            && valid((name as NSString).deletingPathExtension)
    }
}
