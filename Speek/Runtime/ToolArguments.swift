import Foundation
import CoreFoundation

enum ToolArguments {
    static func validate(_ value: Any, schema: [String: Any], path: String = "Arguments") throws {
        func invalid(_ detail: String) -> ActionClientError { .requestFailed(path + ": " + detail) }
        if let variants = schema["anyOf"] as? [[String: Any]] ?? schema["oneOf"] as? [[String: Any]] {
            guard variants.contains(where: { (try? validate(value, schema: $0, path: path)) != nil }) else { throw invalid("value does not match the tool's accepted format.") }
        }
        if let options = schema["enum"] as? [Any] {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
            guard options.contains(where: { (try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys])) == data }) else { throw invalid("choose an allowed value.") }
        }
        let types = (schema["type"] as? String).map { [$0] } ?? schema["type"] as? [String] ?? []
        if !types.isEmpty {
            let matched = types.contains { type in
                switch type {
                case "object": return value is [String: Any]
                case "array": return value is [Any]
                case "string": return value is String
                case "boolean": return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
                case "number", "integer":
                    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
                    return type == "number" || number.doubleValue.rounded() == number.doubleValue
                case "null": return value is NSNull
                default: return true
                }
            }
            guard matched else { throw invalid("expected " + types.joined(separator: " or ") + ".") }
        }
        if let object = value as? [String: Any] {
            let required = schema["required"] as? [String] ?? []
            guard required.allSatisfy({ object[$0] != nil }) else { throw invalid("missing a required field.") }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            if schema["additionalProperties"] as? Bool == false, !Set(object.keys).isSubset(of: Set(properties.keys)) { throw invalid("contains an unknown field.") }
            for (key, child) in object { if let spec = properties[key] { try validate(child, schema: spec, path: path + "." + key) } }
        }
        if let array = value as? [Any], let items = schema["items"] as? [String: Any] {
            for (index, child) in array.enumerated() { try validate(child, schema: items, path: path + "[\(index)]") }
        }
        if let string = value as? String {
            if let minimum = schema["minLength"] as? Int, string.count < minimum { throw invalid("text is too short.") }
            if let maximum = schema["maxLength"] as? Int, string.count > maximum { throw invalid("text is too long.") }
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, number.doubleValue < minimum { throw invalid("number is below the minimum.") }
            if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, number.doubleValue > maximum { throw invalid("number is above the maximum.") }
        }
    }
}
