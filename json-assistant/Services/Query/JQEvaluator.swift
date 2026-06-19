import Foundation

/// Evaluates a `JQFilter` against the app's `Any`-typed JSON values, returning
/// a stream of output values (jq's core model).
///
/// Object values are produced as `OrderedDictionary` so key order from object
/// construction is preserved end-to-end — the main reason for a hand-written
/// engine over a re-serializing third-party one.
struct JQEvaluator {
    /// Runs `filter` against `input`, producing the full output stream.
    func evaluate(_ filter: JQFilter, _ input: Any) throws -> [Any] {
        switch filter {
        case .identity:
            return [input]

        case let .field(name):
            return [try access(input, key: name)]

        case let .indexKey(key):
            return [try access(input, key: key)]

        case let .index(position):
            return [try index(input, at: position)]

        case .iterateAll:
            return try iterate(input)

        case let .pipe(lhs, rhs):
            var results: [Any] = []
            for value in try evaluate(lhs, input) {
                results.append(contentsOf: try evaluate(rhs, value))
            }
            return results

        case let .comma(lhs, rhs):
            return try evaluate(lhs, input) + evaluate(rhs, input)

        case let .optional(inner):
            do {
                return try evaluate(inner, input)
            } catch JQError.runtime {
                return []
            }

        case let .objectConstruction(entries):
            return try constructObjects(entries, input)

        case let .arrayConstruction(inner):
            guard let inner else { return [[Any]()] }
            return [try evaluate(inner, input)]

        case let .literal(literal):
            return [literal.anyValue]

        case let .call(name, arguments):
            return try evaluateCall(name, arguments, input)

        case let .binary(op, lhs, rhs):
            return try evaluateBinary(op, lhs, rhs, input)
        }
    }

    // MARK: - Access

    private func access(_ input: Any, key: String) throws -> Any {
        switch input {
        case let dict as OrderedDictionary:
            return dict[key] ?? NSNull()
        case let dict as [String: Any]:
            return dict[key] ?? NSNull()
        case is NSNull:
            return NSNull()
        default:
            throw JQError.runtime("Cannot index \(JQEvaluator.typeName(input)) with \"\(key)\"")
        }
    }

    private func index(_ input: Any, at position: Int) throws -> Any {
        switch input {
        case let array as [Any]:
            let resolved = position < 0 ? array.count + position : position
            guard resolved >= 0, resolved < array.count else { return NSNull() }
            return array[resolved]
        case is NSNull:
            return NSNull()
        default:
            throw JQError.runtime("Cannot index \(JQEvaluator.typeName(input)) with number")
        }
    }

    private func iterate(_ input: Any) throws -> [Any] {
        switch input {
        case let array as [Any]:
            return array
        case let dict as OrderedDictionary:
            return dict.orderedPairs.map { $0.1 }
        case let dict as [String: Any]:
            return Array(dict.values)
        default:
            throw JQError.runtime("Cannot iterate over \(JQEvaluator.typeName(input))")
        }
    }

    // MARK: - Object construction

    private func constructObjects(_ entries: [JQObjectEntry], _ input: Any) throws -> [Any] {
        // Build the cartesian product of entry value streams as ordered pair
        // lists, then materialize each into an OrderedDictionary. Working with
        // pair arrays (not the class) avoids aliasing across product branches.
        var partials: [[(String, Any)]] = [[]]
        for entry in entries {
            let values = try evaluate(entry.value, input)
            var next: [[(String, Any)]] = []
            next.reserveCapacity(partials.count * max(values.count, 1))
            for partial in partials {
                for value in values {
                    next.append(partial + [(entry.key, value)])
                }
            }
            partials = next
        }

        return partials.map { pairs in
            let dict = OrderedDictionary()
            for (key, value) in pairs {
                dict[key] = value
            }
            return dict
        }
    }

    // MARK: - Builtins

    private func evaluateCall(_ name: String, _ arguments: [JQFilter], _ input: Any) throws -> [Any] {
        switch name {
        case "length":
            return [try length(of: input)]
        case "keys":
            return [try keys(of: input, sorted: true)]
        case "keys_unsorted":
            return [try keys(of: input, sorted: false)]
        case "values":
            return try iterate(input)
        case "type":
            return [JQEvaluator.typeName(input)]
        case "has":
            return [try has(input, argument: try singleArgument(name, arguments, input))]
        case "map":
            return [try map(input, filter: try requireFilter(name, arguments))]
        case "select":
            return try select(input, filter: try requireFilter(name, arguments))
        case "first":
            return [try index(input, at: 0)]
        case "last":
            return [try index(input, at: -1)]
        case "add":
            return [try add(input)]
        case "not":
            return [NSNumber(value: !JQEvaluator.isTruthy(input))]
        case "empty":
            return []
        default:
            throw JQError.runtime("Unknown function '\(name)'")
        }
    }

    private func requireFilter(_ name: String, _ arguments: [JQFilter]) throws -> JQFilter {
        guard let filter = arguments.first else {
            throw JQError.runtime("\(name) requires an argument, e.g. \(name)(.field)")
        }
        return filter
    }

    private func singleArgument(_ name: String, _ arguments: [JQFilter], _ input: Any) throws -> Any {
        let filter = try requireFilter(name, arguments)
        let values = try evaluate(filter, input)
        guard let value = values.first else {
            throw JQError.runtime("\(name) argument produced no value")
        }
        return value
    }

    private func length(of input: Any) throws -> Any {
        switch input {
        case let array as [Any]:
            return NSNumber(value: array.count)
        case let string as String:
            return NSNumber(value: string.count)
        case let dict as OrderedDictionary:
            return NSNumber(value: dict.orderedPairs.count)
        case let dict as [String: Any]:
            return NSNumber(value: dict.count)
        case is NSNull:
            return NSNumber(value: 0)
        case let number as NSNumber where !number.isBool:
            return NSNumber(value: abs(number.doubleValue))
        default:
            throw JQError.runtime("\(JQEvaluator.typeName(input)) has no length")
        }
    }

    private func keys(of input: Any, sorted: Bool) throws -> Any {
        switch input {
        case let dict as OrderedDictionary:
            let keys = dict.orderedPairs.map { $0.0 }
            return (sorted ? keys.sorted() : keys) as [Any]
        case let dict as [String: Any]:
            let keys = Array(dict.keys)
            return (sorted ? keys.sorted() : keys) as [Any]
        case let array as [Any]:
            return Array(0..<array.count).map { NSNumber(value: $0) } as [Any]
        default:
            throw JQError.runtime("\(JQEvaluator.typeName(input)) has no keys")
        }
    }

    private func has(_ input: Any, argument: Any) throws -> Any {
        switch input {
        case let dict as OrderedDictionary:
            guard let key = argument as? String else {
                throw JQError.runtime("has() on an object expects a string key")
            }
            return NSNumber(value: dict[key] != nil)
        case let dict as [String: Any]:
            guard let key = argument as? String else {
                throw JQError.runtime("has() on an object expects a string key")
            }
            return NSNumber(value: dict[key] != nil)
        case let array as [Any]:
            guard let number = argument as? NSNumber, !number.isBool else {
                throw JQError.runtime("has() on an array expects a number index")
            }
            let position = number.intValue
            return NSNumber(value: position >= 0 && position < array.count)
        default:
            throw JQError.runtime("Cannot check has() on \(JQEvaluator.typeName(input))")
        }
    }

    private func map(_ input: Any, filter: JQFilter) throws -> Any {
        guard let array = input as? [Any] else {
            throw JQError.runtime("Cannot map over \(JQEvaluator.typeName(input))")
        }
        var results: [Any] = []
        for element in array {
            results.append(contentsOf: try evaluate(filter, element))
        }
        return results
    }

    private func select(_ input: Any, filter: JQFilter) throws -> [Any] {
        let conditions = try evaluate(filter, input)
        return conditions.contains { JQEvaluator.isTruthy($0) } ? [input] : []
    }

    private func add(_ input: Any) throws -> Any {
        guard let array = input as? [Any] else {
            throw JQError.runtime("Cannot add \(JQEvaluator.typeName(input))")
        }
        guard let first = array.first else { return NSNull() }

        if first is String {
            var result = ""
            for element in array {
                guard let string = element as? String else {
                    throw JQError.runtime("Cannot add mixed types")
                }
                result.append(string)
            }
            return result
        }

        if first is [Any] {
            var result: [Any] = []
            for element in array {
                guard let nested = element as? [Any] else {
                    throw JQError.runtime("Cannot add mixed types")
                }
                result.append(contentsOf: nested)
            }
            return result
        }

        var sum = 0.0
        for element in array {
            guard let number = element as? NSNumber, !number.isBool else {
                throw JQError.runtime("Cannot add mixed types")
            }
            sum += number.doubleValue
        }
        return NSNumber(value: sum)
    }

    // MARK: - Comparisons & booleans

    private func evaluateBinary(_ op: JQBinaryOp, _ lhs: JQFilter, _ rhs: JQFilter, _ input: Any) throws -> [Any] {
        var results: [Any] = []
        for leftValue in try evaluate(lhs, input) {
            for rightValue in try evaluate(rhs, input) {
                results.append(NSNumber(value: try apply(op, leftValue, rightValue)))
            }
        }
        return results
    }

    private func apply(_ op: JQBinaryOp, _ lhs: Any, _ rhs: Any) throws -> Bool {
        switch op {
        case .eq: return JQEvaluator.compare(lhs, rhs) == 0
        case .neq: return JQEvaluator.compare(lhs, rhs) != 0
        case .lt: return JQEvaluator.compare(lhs, rhs) < 0
        case .lte: return JQEvaluator.compare(lhs, rhs) <= 0
        case .gt: return JQEvaluator.compare(lhs, rhs) > 0
        case .gte: return JQEvaluator.compare(lhs, rhs) >= 0
        case .and: return JQEvaluator.isTruthy(lhs) && JQEvaluator.isTruthy(rhs)
        case .or: return JQEvaluator.isTruthy(lhs) || JQEvaluator.isTruthy(rhs)
        }
    }

    // MARK: - Value helpers

    /// jq truthiness: everything is true except `false` and `null`.
    static func isTruthy(_ value: Any) -> Bool {
        switch value {
        case is NSNull:
            return false
        case let number as NSNumber where number.isBool:
            return number.boolValue
        default:
            return true
        }
    }

    static func typeName(_ value: Any) -> String {
        switch value {
        case is NSNull: return "null"
        case let number as NSNumber: return number.isBool ? "boolean" : "number"
        case is String: return "string"
        case is [Any]: return "array"
        case is OrderedDictionary, is [String: Any]: return "object"
        default: return "value"
        }
    }

    /// jq's total ordering across types: null < booleans < numbers < strings <
    /// arrays < objects. Returns negative / zero / positive like `compare`.
    static func compare(_ lhs: Any, _ rhs: Any) -> Int {
        let leftRank = typeRank(lhs)
        let rightRank = typeRank(rhs)
        if leftRank != rightRank {
            return leftRank < rightRank ? -1 : 1
        }

        switch leftRank {
        case 0: // null
            return 0
        case 1: // boolean
            let left = (lhs as? NSNumber)?.boolValue ?? false
            let right = (rhs as? NSNumber)?.boolValue ?? false
            if left == right { return 0 }
            return (!left && right) ? -1 : 1
        case 2: // number
            let left = (lhs as? NSNumber)?.doubleValue ?? 0
            let right = (rhs as? NSNumber)?.doubleValue ?? 0
            if left == right { return 0 }
            return left < right ? -1 : 1
        case 3: // string
            let left = lhs as? String ?? ""
            let right = rhs as? String ?? ""
            if left == right { return 0 }
            return left < right ? -1 : 1
        case 4: // array
            let left = lhs as? [Any] ?? []
            let right = rhs as? [Any] ?? []
            let count = min(left.count, right.count)
            for offset in 0..<count {
                let elementComparison = compare(left[offset], right[offset])
                if elementComparison != 0 { return elementComparison }
            }
            if left.count == right.count { return 0 }
            return left.count < right.count ? -1 : 1
        default: // object — compare by sorted keys, then values
            let left = orderedPairs(lhs)
            let right = orderedPairs(rhs)
            let leftKeys = left.map { $0.0 }.sorted()
            let rightKeys = right.map { $0.0 }.sorted()
            let keyComparison = compare(leftKeys as [Any], rightKeys as [Any])
            if keyComparison != 0 { return keyComparison }
            let leftMap = Dictionary(left, uniquingKeysWith: { first, _ in first })
            let rightMap = Dictionary(right, uniquingKeysWith: { first, _ in first })
            for key in leftKeys {
                let valueComparison = compare(leftMap[key] ?? NSNull(), rightMap[key] ?? NSNull())
                if valueComparison != 0 { return valueComparison }
            }
            return 0
        }
    }

    private static func typeRank(_ value: Any) -> Int {
        switch value {
        case is NSNull: return 0
        case let number as NSNumber: return number.isBool ? 1 : 2
        case is String: return 3
        case is [Any]: return 4
        default: return 5
        }
    }

    private static func orderedPairs(_ value: Any) -> [(String, Any)] {
        if let dict = value as? OrderedDictionary {
            return dict.orderedPairs
        }
        if let dict = value as? [String: Any] {
            return Array(dict)
        }
        return []
    }
}
