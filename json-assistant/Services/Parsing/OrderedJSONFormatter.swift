import Foundation

enum OrderedJSONFormatter {
    static func prettyPrinted(_ value: Any, indent: Int = 0) -> String {
        return format(value, indentLevel: indent)
    }

    private static func format(_ value: Any, indentLevel: Int) -> String {
        let indentUnit = "    "
        let currentIndent = String(repeating: indentUnit, count: indentLevel)
        let nextIndentLevel = indentLevel + 1
        let nextIndent = String(repeating: indentUnit, count: nextIndentLevel)

        switch value {
        case let dictionary as OrderedDictionary:
            let pairs = dictionary.orderedPairs
            guard !pairs.isEmpty else { return "{}" }
            var lines = ["{"]
            for (index, pair) in pairs.enumerated() {
                let formattedValue = format(pair.1, indentLevel: nextIndentLevel)
                var line = "\(nextIndent)\"\(escape(pair.0))\": \(formattedValue)"
                if index < pairs.count - 1 {
                    line += ","
                }
                lines.append(line)
            }
            lines.append("\(currentIndent)}")
            return lines.joined(separator: "\n")

        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            var lines = ["["]
            for (index, element) in array.enumerated() {
                var line = "\(nextIndent)\(format(element, indentLevel: nextIndentLevel))"
                if index < array.count - 1 {
                    line += ","
                }
                lines.append(line)
            }
            lines.append("\(currentIndent)]")
            return lines.joined(separator: "\n")

        case let string as String:
            return "\"\(escape(string))\""

        case let number as NSNumber:
            if number.isBool {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue

        case _ as NSNull:
            return "null"

        case let bool as Bool:
            return bool ? "true" : "false"

        case let double as Double:
            return NSNumber(value: double).stringValue

        case let int as Int:
            return "\(int)"

        default:
            return "\"\(escape(String(describing: value)))\""
        }
    }

    private static func escape(_ string: String) -> String {
        var escaped = ""
        for character in string {
            switch character {
            case "\"": escaped.append("\\\"")
            case "\\": escaped.append("\\\\")
            case "\u{08}": escaped.append("\\b")
            case "\u{0C}": escaped.append("\\f")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default:
                if character.unicodeScalars.allSatisfy({ $0.value < 0x20 }) {
                    for scalar in character.unicodeScalars {
                        let value = String(format: "%04X", scalar.value)
                        escaped.append("\\u\(value)")
                    }
                } else {
                    escaped.append(character)
                }
            }
        }
        return escaped
    }
}
