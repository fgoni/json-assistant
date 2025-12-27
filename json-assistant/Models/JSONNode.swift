import SwiftUI
import Foundation

struct JSONNode: Identifiable {
    let id: UUID
    let key: String
    let isRoot: Bool
    let value: Any
    let children: [JSONNode]

    init(key: String, value: Any, isRoot: Bool = false) {
        self.id = UUID()
        self.key = key
        self.isRoot = isRoot
        self.value = value

        // Parse children immediately
        var parsedChildren: [JSONNode] = []
        switch value {
        case let dict as OrderedDictionary:
            parsedChildren = dict.orderedPairs.map { JSONNode(key: $0.0, value: $0.1) }
        case let dict as [String: Any]:
            let ordered = OrderedDictionary()
            for (key, value) in dict {
                ordered[key] = value
            }
            parsedChildren = ordered.orderedPairs.map { JSONNode(key: $0.0, value: $0.1) }
        case let array as [Any]:
            parsedChildren = array.enumerated().map { JSONNode(key: "[\($0)]", value: $1) }
        default:
            break
        }
        self.children = parsedChildren
    }

    var displayValue: String {
        if !children.isEmpty { return "" }
        switch value {
        case is OrderedDictionary, is [String: Any]:
            return "Object"
        case is [Any]:
            return "Array"
        case let stringValue as String: return "\"\(stringValue)\""
        case is NSNull: return "null"
        case let number as NSNumber:
            return number.isBool ? (number.boolValue ? "true" : "false") : number.stringValue
        default: return "\(value)"
        }
    }

    var typeDescription: String {
        return JSONNode.describeType(of: value)
    }

    static func describeType(of value: Any) -> String {
        switch value {
        case is OrderedDictionary, is [String: Any]:
            return "Object"
        case is [Any]:
            return "Array"
        case let number as NSNumber:
            return number.isBool ? "Boolean" : "Number"
        case is String:
            return "String"
        case is NSNull:
            return "Null"
        case is Bool:
            return "Boolean"
        default:
            return String(describing: type(of: value))
        }
    }
}
