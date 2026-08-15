import Foundation

/// A small dynamic JSON value.
///
/// The MCP server speaks JSON-RPC, where the shape of a message is not known
/// until it is read, so a concrete `Codable` type per message would be more
/// ceremony than it is worth. This is the pragmatic middle: typed enough to be
/// safe, loose enough to route.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Reading

    public subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(value)
        case .string(let value): Int(value)
        default: nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    // MARK: Parsing

    public init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        self = JSONValue(any: object)
    }

    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // NSNumber erases Bool into a number, so check the ObjC type tag.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map(JSONValue.init(any:)))
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    // MARK: Encoding

    /// Hand-rolled so keys come out sorted (stable output for tests and diffs)
    /// and so encoding never throws in the middle of a JSON-RPC reply.
    public func encodedString(pretty: Bool = false, indent: Int = 0) -> String {
        let pad = pretty ? String(repeating: " ", count: indent * 2) : ""
        let innerPad = pretty ? String(repeating: " ", count: (indent + 1) * 2) : ""
        let newline = pretty ? "\n" : ""
        let space = pretty ? " " : ""

        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            guard value.isFinite else { return "null" }
            // Print integral doubles without a trailing ".0" — cleaner for readers.
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int(value))
            }
            return String(format: "%.4f", value)
        case .string(let value):
            return Self.quote(value)
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let body = values
                .map { innerPad + $0.encodedString(pretty: pretty, indent: indent + 1) }
                .joined(separator: "," + newline)
            return "[" + newline + body + newline + pad + "]"
        case .object(let fields):
            guard !fields.isEmpty else { return "{}" }
            let body = fields.keys.sorted()
                .map { key in
                    innerPad + Self.quote(key) + ":" + space
                        + (fields[key] ?? .null).encodedString(pretty: pretty, indent: indent + 1)
                }
                .joined(separator: "," + newline)
            return "{" + newline + body + newline + pad + "}"
        }
    }

    static func quote(_ value: String) -> String {
        var output = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if character.value < 0x20 {
                    output += String(format: "\\u%04x", character.value)
                } else {
                    output.unicodeScalars.append(character)
                }
            }
        }
        return output + "\""
    }
}
