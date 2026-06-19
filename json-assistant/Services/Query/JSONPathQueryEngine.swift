import Foundation

/// Hand-rolled JSONPath engine operating directly on the app's `Any` JSON model
/// (`OrderedDictionary` / `[Any]` / `NSNumber` / `String` / `NSNull`). Working on
/// the model directly — instead of going through a third-party library — keeps
/// key order and number/bool/null semantics intact and avoids a serialize /
/// re-parse round-trip, matching the approach of the hand-written jq engine.
///
/// Supported subset:
///   - root `$`
///   - child `.key` and `['key']` / `["key"]`
///   - index `[n]` (negative counts from the end)
///   - wildcard `[*]` and `.*`
///   - recursive descent `..key`, `..*`, `..[*]`, `..[n]`, …
///   - slice `[start:end:step]` (Python semantics, negative bounds/step)
///   - union `['a','b']`, `[0,1]` (selectors concatenated in order)
///   - filter `[?(@.field)]` (existence) and `[?(@.field OP literal)]`
///     with OP in == != < <= > >= and string/number/bool literals
///
/// JSONPath produces a node list, mapped directly onto `QueryResult.values`
/// (so `count` is the number of matches, like jq's stream).
struct JSONPathQueryEngine: QueryEngine {
    func run(query: String, on input: Any) throws -> QueryResult {
        var parser = JSONPathParser(query)
        let steps = try parser.parse()
        let values = JSONPathEvaluator.evaluate(steps, root: input)
        return QueryResult(values: values)
    }
}

// MARK: - Model

/// One selector applied to a node, optionally preceded by recursive descent.
private struct JSONPathStep {
    let recursive: Bool
    let selector: JSONPathSelector
}

private indirect enum JSONPathSelector {
    case wildcard
    case child(String)
    case index(Int)
    case slice(start: Int?, end: Int?, step: Int?)
    case union([JSONPathSelector])
    case filter(JSONPathFilter)
}

private enum JSONPathOp {
    case eq, neq, lt, lte, gt, gte
}

private enum JSONPathLiteral {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

/// `@.a.b` relative lookup, with an optional comparison against a literal.
/// With no comparison the filter is an existence test (present and not null).
private struct JSONPathFilter {
    let relativePath: [String]
    let comparison: (op: JSONPathOp, literal: JSONPathLiteral)?
}

// MARK: - Parser

private struct JSONPathParser {
    private let chars: [Character]
    private var pos = 0

    init(_ query: String) {
        self.chars = Array(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    mutating func parse() throws -> [JSONPathStep] {
        guard !chars.isEmpty else { throw JQError.parse("Empty query") }
        // A leading `$` is optional but, if present, must be first.
        if peek() == "$" { advance() }

        var steps: [JSONPathStep] = []
        while pos < chars.count {
            let recursive = consumeDotsForRecursion()
            if pos >= chars.count {
                if recursive { throw JQError.parse("Dangling '..' at end of path") }
                break
            }
            let selector = try parseSelector(afterRecursive: recursive)
            steps.append(JSONPathStep(recursive: recursive, selector: selector))
        }
        return steps
    }

    /// Consumes a leading `.` / `..` for the next segment. Returns true when the
    /// segment is a recursive-descent (`..`) segment.
    private mutating func consumeDotsForRecursion() -> Bool {
        if peek() == "." && peekAhead(1) == "." {
            advance(); advance()
            return true
        }
        if peek() == "." {
            advance()
            return false
        }
        return false
    }

    private mutating func parseSelector(afterRecursive recursive: Bool) throws -> JSONPathSelector {
        switch peek() {
        case "*":
            advance()
            return .wildcard
        case "[":
            return try parseBracket()
        case .some(let ch) where isNameStart(ch):
            return .child(parseDotName())
        default:
            // `..[...]` lands here with recursive already consumed and a `[`
            // handled above; anything else is invalid.
            throw JQError.parse("Unexpected character in path: '\(peek().map(String.init) ?? "")'")
        }
    }

    // MARK: dot name

    private mutating func parseDotName() -> String {
        var name = ""
        while let ch = peek(), isNameChar(ch) {
            name.append(ch)
            advance()
        }
        return name
    }

    // MARK: bracket

    private mutating func parseBracket() throws -> JSONPathSelector {
        expect("[")
        skipSpaces()

        if peek() == "?" {
            let filter = try parseFilter()
            skipSpaces()
            try expectClosing()
            return .filter(filter)
        }

        if peek() == "*" {
            advance()
            skipSpaces()
            try expectClosing()
            return .wildcard
        }

        // One or more comma-separated selectors (quoted names, ints, slices).
        var selectors: [JSONPathSelector] = []
        repeat {
            skipSpaces()
            selectors.append(try parseBracketSelector())
            skipSpaces()
        } while consumeIf(",")

        try expectClosing()
        return selectors.count == 1 ? selectors[0] : .union(selectors)
    }

    private mutating func parseBracketSelector() throws -> JSONPathSelector {
        if let ch = peek(), ch == "'" || ch == "\"" {
            return .child(try parseQuotedString())
        }
        // number, slice, or negative index
        return try parseIndexOrSlice()
    }

    private mutating func parseIndexOrSlice() throws -> JSONPathSelector {
        let first = parseOptionalInt()

        if peek() == ":" {
            advance()
            let second = parseOptionalInt()
            var step: Int?
            if peek() == ":" {
                advance()
                step = parseOptionalInt()
            }
            return .slice(start: first, end: second, step: step)
        }

        guard let index = first else {
            throw JQError.parse("Expected index or slice inside '[]'")
        }
        return .index(index)
    }

    private mutating func parseOptionalInt() -> Int? {
        skipSpaces()
        var digits = ""
        if peek() == "-" {
            digits.append("-")
            advance()
        }
        while let ch = peek(), ch.isNumber {
            digits.append(ch)
            advance()
        }
        skipSpaces()
        return Int(digits)
    }

    private mutating func parseQuotedString() throws -> String {
        guard let quote = peek(), quote == "'" || quote == "\"" else {
            throw JQError.parse("Expected quoted key")
        }
        advance()
        var value = ""
        while let ch = peek() {
            if ch == "\\" {
                advance()
                guard let escaped = peek() else { break }
                value.append(escaped)
                advance()
                continue
            }
            if ch == quote {
                advance()
                return value
            }
            value.append(ch)
            advance()
        }
        throw JQError.parse("Unterminated quoted key")
    }

    // MARK: filter

    private mutating func parseFilter() throws -> JSONPathFilter {
        expect("?")
        skipSpaces()
        guard consumeIf("(") else { throw JQError.parse("Expected '(' after '?' in filter") }
        skipSpaces()
        guard consumeIf("@") else { throw JQError.parse("Filter must start with '@'") }

        var path: [String] = []
        while peek() == "." {
            advance()
            let name = parseDotName()
            guard !name.isEmpty else { throw JQError.parse("Expected field name after '.' in filter") }
            path.append(name)
        }
        guard !path.isEmpty else { throw JQError.parse("Filter requires a field reference like @.field") }

        skipSpaces()
        var comparison: (op: JSONPathOp, literal: JSONPathLiteral)?
        if let op = parseOperator() {
            skipSpaces()
            let literal = try parseLiteral()
            comparison = (op, literal)
        }

        skipSpaces()
        guard consumeIf(")") else { throw JQError.parse("Expected ')' to close filter") }
        return JSONPathFilter(relativePath: path, comparison: comparison)
    }

    private mutating func parseOperator() -> JSONPathOp? {
        switch peek() {
        case "=":
            if peekAhead(1) == "=" { advance(); advance(); return .eq }
            return nil
        case "!":
            if peekAhead(1) == "=" { advance(); advance(); return .neq }
            return nil
        case "<":
            if peekAhead(1) == "=" { advance(); advance(); return .lte }
            advance(); return .lt
        case ">":
            if peekAhead(1) == "=" { advance(); advance(); return .gte }
            advance(); return .gt
        default:
            return nil
        }
    }

    private mutating func parseLiteral() throws -> JSONPathLiteral {
        if let ch = peek(), ch == "'" || ch == "\"" {
            return .string(try parseQuotedString())
        }
        // bareword: true / false / null / number
        var word = ""
        while let ch = peek(), !ch.isWhitespace, ch != ")" {
            word.append(ch)
            advance()
        }
        switch word {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default:
            if let number = Double(word) { return .number(number) }
            throw JQError.parse("Invalid literal in filter: '\(word)'")
        }
    }

    // MARK: scanning helpers

    private func peek() -> Character? { pos < chars.count ? chars[pos] : nil }
    private func peekAhead(_ n: Int) -> Character? { pos + n < chars.count ? chars[pos + n] : nil }
    private mutating func advance() { pos += 1 }
    private mutating func skipSpaces() { while let ch = peek(), ch == " " { advance() } }

    private mutating func consumeIf(_ ch: Character) -> Bool {
        if peek() == ch { advance(); return true }
        return false
    }

    private mutating func expect(_ ch: Character) {
        if peek() == ch { advance() }
    }

    private mutating func expectClosing() throws {
        guard consumeIf("]") else { throw JQError.parse("Expected ']'") }
    }

    private func isNameStart(_ ch: Character) -> Bool { ch.isLetter || ch == "_" }
    private func isNameChar(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber || ch == "_" }
}

// MARK: - Evaluator

private enum JSONPathEvaluator {
    static func evaluate(_ steps: [JSONPathStep], root: Any) -> [Any] {
        var current: [Any] = [root]
        for step in steps {
            let bases = step.recursive ? current.flatMap { descendants(of: $0) } : current
            var next: [Any] = []
            for node in bases {
                next.append(contentsOf: apply(step.selector, to: node))
            }
            current = next
        }
        return current
    }

    /// Pre-order list of a node and all of its descendants (each node once).
    private static func descendants(of node: Any) -> [Any] {
        var result: [Any] = [node]
        switch node {
        case let dict as OrderedDictionary:
            for (_, value) in dict.orderedPairs { result.append(contentsOf: descendants(of: value)) }
        case let array as [Any]:
            for value in array { result.append(contentsOf: descendants(of: value)) }
        default:
            break
        }
        return result
    }

    private static func apply(_ selector: JSONPathSelector, to node: Any) -> [Any] {
        switch selector {
        case .wildcard:
            return childrenValues(of: node)

        case let .child(name):
            if let dict = node as? OrderedDictionary, let value = dict[name] {
                return [value]
            }
            return []

        case let .index(index):
            guard let array = node as? [Any] else { return [] }
            let resolved = index < 0 ? array.count + index : index
            guard resolved >= 0, resolved < array.count else { return [] }
            return [array[resolved]]

        case let .slice(start, end, step):
            guard let array = node as? [Any] else { return [] }
            return slice(array, start: start, end: end, step: step)

        case let .union(selectors):
            return selectors.flatMap { apply($0, to: node) }

        case let .filter(filter):
            return childrenValues(of: node).filter { matches(filter, $0) }
        }
    }

    /// The values directly contained in a node: object values (key order) or
    /// array elements.
    private static func childrenValues(of node: Any) -> [Any] {
        switch node {
        case let dict as OrderedDictionary:
            return dict.orderedPairs.map { $0.1 }
        case let array as [Any]:
            return array
        default:
            return []
        }
    }

    // MARK: slice (Python semantics)

    private static func slice(_ array: [Any], start: Int?, end: Int?, step: Int?) -> [Any] {
        let n = array.count
        let st = step ?? 1
        if st == 0 { return [] }

        func clamp(_ value: Int, lower: Int, upper: Int) -> Int { min(max(value, lower), upper) }

        var result: [Any] = []
        if st > 0 {
            var lo = start ?? 0
            var hi = end ?? n
            if lo < 0 { lo += n }
            if hi < 0 { hi += n }
            lo = clamp(lo, lower: 0, upper: n)
            hi = clamp(hi, lower: 0, upper: n)
            var i = lo
            while i < hi {
                result.append(array[i])
                i += st
            }
        } else {
            var lo = start ?? (n - 1)
            var hi = end ?? -(n + 1)   // sentinel meaning "before index 0"
            if lo < 0 { lo += n }
            if let _ = end, hi < 0 { hi += n }
            lo = clamp(lo, lower: -1, upper: n - 1)
            // when end omitted, hi stays at -(n+1) which clamps to -1 exclusive
            hi = max(hi, -1)
            var i = lo
            while i > hi {
                if i >= 0 && i < n { result.append(array[i]) }
                i += st
            }
        }
        return result
    }

    // MARK: filter matching

    private static func matches(_ filter: JSONPathFilter, _ node: Any) -> Bool {
        guard let value = resolve(filter.relativePath, in: node) else { return false }
        guard let comparison = filter.comparison else {
            // Bare `[?(@.field)]` is a truthiness test, matching jq's
            // `select(.field)` in the same app: only `false` and `null` are falsy.
            return isTruthy(value)
        }
        return compare(value, comparison.op, comparison.literal)
    }

    /// jq-style truthiness: everything is truthy except `null` and boolean `false`.
    private static func isTruthy(_ value: Any) -> Bool {
        if value is NSNull { return false }
        if let flag = boolValue(value) { return flag }
        return true
    }

    private static func resolve(_ path: [String], in node: Any) -> Any? {
        var current: Any = node
        for key in path {
            guard let dict = current as? OrderedDictionary, let value = dict[key] else { return nil }
            current = value
        }
        return current
    }

    private static func compare(_ value: Any, _ op: JSONPathOp, _ literal: JSONPathLiteral) -> Bool {
        switch literal {
        case let .string(text):
            guard let actual = value as? String else { return op == .neq }
            return apply(op, actual.compare(text))
        case let .number(number):
            guard let actual = numericValue(value) else { return op == .neq }
            return apply(op, compareDoubles(actual, number))
        case let .bool(flag):
            guard let actual = boolValue(value) else { return op == .neq }
            return op == .eq ? (actual == flag) : (op == .neq ? actual != flag : false)
        case .null:
            let isNull = value is NSNull
            return op == .eq ? isNull : (op == .neq ? !isNull : false)
        }
    }

    private static func apply(_ op: JSONPathOp, _ order: ComparisonResult) -> Bool {
        switch op {
        case .eq: return order == .orderedSame
        case .neq: return order != .orderedSame
        case .lt: return order == .orderedAscending
        case .lte: return order != .orderedDescending
        case .gt: return order == .orderedDescending
        case .gte: return order != .orderedAscending
        }
    }

    private static func compareDoubles(_ a: Double, _ b: Double) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }

    /// A numeric `NSNumber` as Double, excluding booleans (so `true` never equals 1).
    private static func numericValue(_ value: Any) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.doubleValue
    }

    private static func boolValue(_ value: Any) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
}
