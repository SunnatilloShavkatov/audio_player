import Foundation

/// The JSON form of the messages exchanged with Dart. The writer is hand-made because `JSONSerialization` raises
/// an Objective-C exception (a crash) on `nil` optionals and NaN, both of which player state can contain.
enum NativeJSON {
    /// Decodes a JSON object; empty text is an empty map, anything unreadable is `nil`.
    static func decodeMap(_ text: String) -> [String: Any]? {
        if text.isEmpty { return [:] }
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8))
        return object as? [String: Any]
    }

    static func encode(_ value: Any?) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    /// The text of an error's details: JSON for maps and lists, else the plain text; `nil` stays `nil`.
    static func encodeDetails(_ details: Any?) -> String? {
        guard let details = unwrap(details), !(details is NSNull) else { return nil }
        if let text = details as? String { return text }
        if details is [String: Any] || details is [Any] { return encode(details) }
        return "\(details)"
    }

    private static func unwrap(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.flatMap { unwrap($0.value) }
    }

    private static func write(_ raw: Any?, into out: inout String) {
        guard let value = unwrap(raw), !(value is NSNull) else {
            out += "null"
            return
        }
        switch value {
        case let v as Bool: out += v ? "true" : "false"
        case let v as Int: out += String(v)
        case let v as Int64: out += String(v)
        case let v as Int32: out += String(v)
        case let v as UInt: out += String(v)
        case let v as Double: writeDouble(v, into: &out)
        case let v as Float: writeDouble(Double(v), into: &out)
        case let v as NSNumber: writeNumber(v, into: &out)
        case let v as String: writeString(v, into: &out)
        case let v as [String: Any]:
            out += "{"
            var first = true
            for (key, entry) in v {
                if !first { out += "," }
                first = false
                writeString(key, into: &out)
                out += ":"
                write(entry, into: &out)
            }
            out += "}"
        case let v as [Any]:
            out += "["
            for (offset, entry) in v.enumerated() {
                if offset > 0 { out += "," }
                write(entry, into: &out)
            }
            out += "]"
        default:
            writeString("\(value)", into: &out)
        }
    }

    private static func writeDouble(_ value: Double, into out: inout String) {
        out += value.isFinite ? String(value) : "null"
    }

    private static func writeNumber(_ value: NSNumber, into out: inout String) {
        if String(cString: value.objCType) == "c" {
            out += value.boolValue ? "true" : "false"
        } else {
            writeDouble(value.doubleValue, into: &out)
        }
    }

    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
