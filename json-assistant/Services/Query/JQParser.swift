import Foundation

/// Recursive-descent parser for the supported jq subset.
///
/// Precedence, lowest to highest: pipe `|`, comma `,`, `or`, `and`, comparison,
/// then postfix suffixes (`.field`, `[idx]`, `[]`, `?`) on a primary term.
/// Produces a `JQFilter` AST consumed by `JQEvaluator`.
struct JQParser {
    private let tokens: [JQToken]
    private var position: Int = 0

    init(tokens: [JQToken]) {
        self.tokens = tokens
    }

    /// Parses the full token stream into a single filter, requiring all input
    /// to be consumed.
    mutating func parse() throws -> JQFilter {
        if peek == .eof {
            throw JQError.parse("Empty query")
        }
        let filter = try parsePipe()
        guard peek == .eof else {
            throw JQError.parse("Unexpected '\(describe(peek))'")
        }
        return filter
    }

    // MARK: - Grammar levels

    private mutating func parsePipe() throws -> JQFilter {
        var left = try parseComma()
        while peek == .pipe {
            advance()
            let right = try parseComma()
            left = .pipe(left, right)
        }
        return left
    }

    private mutating func parseComma() throws -> JQFilter {
        var left = try parseOr()
        while peek == .comma {
            advance()
            let right = try parseOr()
            left = .comma(left, right)
        }
        return left
    }

    private mutating func parseOr() throws -> JQFilter {
        var left = try parseAnd()
        while case let .identifier(name) = peek, name == "or" {
            advance()
            let right = try parseAnd()
            left = .binary(.or, left, right)
        }
        return left
    }

    private mutating func parseAnd() throws -> JQFilter {
        var left = try parseComparison()
        while case let .identifier(name) = peek, name == "and" {
            advance()
            let right = try parseComparison()
            left = .binary(.and, left, right)
        }
        return left
    }

    private mutating func parseComparison() throws -> JQFilter {
        let left = try parsePostfix()
        if let op = comparisonOperator(for: peek) {
            advance()
            let right = try parsePostfix()
            return .binary(op, left, right)
        }
        return left
    }

    private mutating func parsePostfix() throws -> JQFilter {
        var node = try parsePrimary()
        loop: while true {
            switch peek {
            case .dot:
                // `.field` / `["key"]` chained access after a primary.
                advance()
                node = .pipe(node, try parseDotSuffix())
            case .lBracket:
                advance()
                node = .pipe(node, try parseBracketSuffix())
            case .question:
                advance()
                node = .optional(node)
            default:
                break loop
            }
        }
        return node
    }

    /// Parses the part after a `.` used as a suffix: an identifier or a quoted key.
    private mutating func parseDotSuffix() throws -> JQFilter {
        switch peek {
        case let .identifier(name):
            advance()
            return .field(name)
        case let .string(key):
            advance()
            return .indexKey(key)
        default:
            throw JQError.parse("Expected a field name after '.'")
        }
    }

    /// Parses a `[...]` suffix: `[]` (iterate), `[<int>]`, or `["key"]`.
    private mutating func parseBracketSuffix() throws -> JQFilter {
        if peek == .rBracket {
            advance()
            return .iterateAll
        }
        switch peek {
        case let .number(value):
            advance()
            try expect(.rBracket, context: "after array index")
            return .index(Int(value))
        case let .string(key):
            advance()
            try expect(.rBracket, context: "after object key")
            return .indexKey(key)
        default:
            throw JQError.parse("Expected a number, string, or ']' inside '[ ]'")
        }
    }

    // MARK: - Primary terms

    private mutating func parsePrimary() throws -> JQFilter {
        switch peek {
        case .dot:
            advance()
            // `.foo` / `."key"` start a field access; a bare `.` is identity and
            // lets a following `[ ]` suffix attach (e.g. `.[]`, `.[0]`).
            switch peek {
            case let .identifier(name):
                advance()
                return .field(name)
            case let .string(key):
                advance()
                return .indexKey(key)
            default:
                return .identity
            }
        case let .identifier(name):
            advance()
            return try parseIdentifierPrimary(name)
        case let .number(value):
            advance()
            return .literal(.number(value))
        case let .string(value):
            advance()
            return .literal(.string(value))
        case .lParen:
            advance()
            let inner = try parsePipe()
            try expect(.rParen, context: "after '('")
            return inner
        case .lBrace:
            return try parseObjectConstruction()
        case .lBracket:
            return try parseArrayConstruction()
        default:
            throw JQError.parse("Unexpected '\(describe(peek))'")
        }
    }

    /// Resolves a bare identifier into a literal keyword or a builtin call.
    private mutating func parseIdentifierPrimary(_ name: String) throws -> JQFilter {
        switch name {
        case "true": return .literal(.bool(true))
        case "false": return .literal(.bool(false))
        case "null": return .literal(.null)
        case "not": return .call("not", [])
        default:
            if peek == .lParen {
                advance()
                let argument = try parsePipe()
                try expect(.rParen, context: "after function argument")
                return .call(name, [argument])
            }
            return .call(name, [])
        }
    }

    private mutating func parseArrayConstruction() throws -> JQFilter {
        try expect(.lBracket, context: "at array start")
        if peek == .rBracket {
            advance()
            return .arrayConstruction(nil)
        }
        let inner = try parsePipe()
        try expect(.rBracket, context: "after array contents")
        return .arrayConstruction(inner)
    }

    private mutating func parseObjectConstruction() throws -> JQFilter {
        try expect(.lBrace, context: "at object start")
        var entries: [JQObjectEntry] = []
        if peek == .rBrace {
            advance()
            return .objectConstruction(entries)
        }
        repeat {
            entries.append(try parseObjectEntry())
        } while consume(.comma)
        try expect(.rBrace, context: "after object entries")
        return .objectConstruction(entries)
    }

    private mutating func parseObjectEntry() throws -> JQObjectEntry {
        switch peek {
        case let .identifier(name):
            advance()
            if consume(.colon) {
                return JQObjectEntry(key: name, value: try parseObjectValue())
            }
            // `{ foo }` is shorthand for `{ foo: .foo }`.
            return JQObjectEntry(key: name, value: .field(name))
        case let .string(key):
            advance()
            if consume(.colon) {
                return JQObjectEntry(key: key, value: try parseObjectValue())
            }
            // `{ "a b" }` is shorthand for `{ "a b": .["a b"] }`.
            return JQObjectEntry(key: key, value: .indexKey(key))
        default:
            throw JQError.parse("Expected a key in object construction")
        }
    }

    /// Parses an object value: everything up to the next `,` or `}`. Pipe is
    /// allowed (e.g. `{ a: .b | .c }`) but binds looser than the value itself.
    private mutating func parseObjectValue() throws -> JQFilter {
        var left = try parseOr()
        while peek == .pipe {
            advance()
            let right = try parseOr()
            left = .pipe(left, right)
        }
        return left
    }

    // MARK: - Token helpers

    private var peek: JQToken {
        position < tokens.count ? tokens[position] : .eof
    }

    private mutating func advance() {
        if position < tokens.count { position += 1 }
    }

    @discardableResult
    private mutating func consume(_ token: JQToken) -> Bool {
        if peek == token {
            advance()
            return true
        }
        return false
    }

    private mutating func expect(_ token: JQToken, context: String) throws {
        guard peek == token else {
            throw JQError.parse("Expected '\(describe(token))' \(context)")
        }
        advance()
    }

    private func comparisonOperator(for token: JQToken) -> JQBinaryOp? {
        switch token {
        case .eq: return .eq
        case .neq: return .neq
        case .lt: return .lt
        case .lte: return .lte
        case .gt: return .gt
        case .gte: return .gte
        default: return nil
        }
    }

    private func describe(_ token: JQToken) -> String {
        switch token {
        case .dot: return "."
        case .pipe: return "|"
        case .comma: return ","
        case .colon: return ":"
        case .question: return "?"
        case .lParen: return "("
        case .rParen: return ")"
        case .lBracket: return "["
        case .rBracket: return "]"
        case .lBrace: return "{"
        case .rBrace: return "}"
        case .eq: return "=="
        case .neq: return "!="
        case .lt: return "<"
        case .lte: return "<="
        case .gt: return ">"
        case .gte: return ">="
        case let .identifier(name): return name
        case let .string(value): return "\"\(value)\""
        case let .number(value): return NSNumber(value: value).stringValue
        case .eof: return "end of query"
        }
    }
}
