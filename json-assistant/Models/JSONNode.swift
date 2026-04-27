import Foundation
import os
import SwiftUI

class JSONNode: Identifiable, ObservableObject {
    private static let maxDepth = 50
    private static let maxNodes = 5000
    private static var nodeCount = 0
    private static var parseStartTime: Date?
    private static var valueAccessCount = 0

    let id = UUID()
    let key: String
    let isRoot: Bool
    let depth: Int
    @Published var value: Any
    @Published var isExpanded: Bool = false
    @Published var children: [JSONNode] = []
    @Published var isFullyLoaded: Bool = false

    init(key: String, value: Any, isRoot: Bool = false, depth: Int = 0) {
        self.key = key
        self.isRoot = isRoot
        self.value = value
        self.depth = depth
        JSONNode.nodeCount += 1

        if isRoot {
            JSONNode.nodeCount = 1
            JSONNode.valueAccessCount = 0
            JSONNode.parseStartTime = Date()
            os_log("JSONNode: ===== PARSE START =====", log: OSLog.default, type: .debug)
            os_log("JSONNode: Starting to parse root with key: %{public}s", log: OSLog.default, type: .debug, key)
        }

        if JSONNode.nodeCount % 100 == 0 {
            let elapsed = Date().timeIntervalSince(JSONNode.parseStartTime ?? Date())
            os_log("JSONNode: Checkpoint - %d nodes created in %.2f seconds (accesses: %d)",
                   log: OSLog.default, type: .info, JSONNode.nodeCount, elapsed, JSONNode.valueAccessCount)
        }

        if JSONNode.nodeCount > Self.maxNodes {
            os_log("JSONNode: CRITICAL - Max nodes exceeded (%d), aborting parse", log: OSLog.default, type: .error, JSONNode.nodeCount)
            return
        }

        parseValue(value, currentDepth: depth)

        if isRoot {
            let elapsed = Date().timeIntervalSince(JSONNode.parseStartTime ?? Date())
            os_log("JSONNode: Finished parsing. Total: %d nodes, %d value accesses in %.2f seconds",
                   log: OSLog.default, type: .debug, JSONNode.nodeCount, JSONNode.valueAccessCount, elapsed)
            os_log("JSONNode: ===== PARSE END =====", log: OSLog.default, type: .debug)
        }
    }

    private func parseValue(_ value: Any, currentDepth: Int) {
        guard currentDepth < Self.maxDepth else {
            os_log("JSONNode: Max depth (%d) reached", log: OSLog.default, type: .debug, Self.maxDepth)
            return
        }

        guard JSONNode.nodeCount <= Self.maxNodes else { return }

        switch value {
        case let dict as OrderedDictionary:
            let pairs = dict.orderedPairs
            children = pairs.map { JSONNode(key: $0.0, value: $0.1, depth: currentDepth + 1) }
            if pairs.count > 100 {
                os_log("JSONNode: Large OrderedDictionary with %d pairs at depth %d", log: OSLog.default, type: .info, pairs.count, currentDepth)
            }

        case let dict as [String: Any]:
            if dict.count > 100 {
                os_log("JSONNode: Large dictionary (%d keys) at depth %d - potential circular structure", log: OSLog.default, type: .error, dict.count, currentDepth)
            }
            let ordered = OrderedDictionary()
            for (key, val) in dict {
                ordered[key] = val
            }
            let pairs = ordered.orderedPairs
            children = pairs.map { JSONNode(key: $0.0, value: $0.1, depth: currentDepth + 1) }

        case let array as [Any]:
            let arrayCount = array.count
            let limitedArray = arrayCount > 1000 ? Array(array.prefix(1000)) : array
            if arrayCount > 1000 {
                os_log("JSONNode: Truncating array from %d to 1000 elements", log: OSLog.default, type: .info, arrayCount)
            }
            children = limitedArray.enumerated().map { JSONNode(key: "[\($0)]", value: $1, depth: currentDepth + 1) }

        default:
            break
        }
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
