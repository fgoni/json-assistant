import Foundation

/// A single lexical token produced by `JQLexer`.
enum JQToken: Equatable {
    case dot                // .
    case pipe               // |
    case comma              // ,
    case colon              // :
    case question           // ?
    case lParen             // (
    case rParen             // )
    case lBracket           // [
    case rBracket           // ]
    case lBrace             // {
    case rBrace             // }
    case eq                 // ==
    case neq                // !=
    case lt                 // <
    case lte                // <=
    case gt                 // >
    case gte                // >=
    case identifier(String) // foo, length, keys, and, or, not, true, false, null
    case string(String)     // "..."
    case number(Double)     // 12, -3.5, 1e4
    case eof
}

/// Tokenizes a jq query string into `JQToken`s.
///
/// Whitespace is insignificant and skipped. Keywords (`and`, `or`, `not`,
/// `true`, `false`, `null`) are returned as `identifier` tokens and resolved by
/// the parser, keeping the lexer free of grammar knowledge.
struct JQLexer {
    private let scalars: [Character]
    private var position: Int = 0

    init(_ input: String) {
        self.scalars = Array(input)
    }

    /// Returns every token including the terminating `.eof`.
    mutating func tokenize() throws -> [JQToken] {
        var tokens: [JQToken] = []
        while true {
            let token = try next()
            tokens.append(token)
            if token == .eof { break }
        }
        return tokens
    }

    private mutating func next() throws -> JQToken {
        skipWhitespace()
        guard let character = current else { return .eof }

        switch character {
        case ".": advance(); return .dot
        case "|": advance(); return .pipe
        case ",": advance(); return .comma
        case ":": advance(); return .colon
        case "?": advance(); return .question
        case "(": advance(); return .lParen
        case ")": advance(); return .rParen
        case "[": advance(); return .lBracket
        case "]": advance(); return .rBracket
        case "{": advance(); return .lBrace
        case "}": advance(); return .rBrace
        case "=":
            advance()
            guard current == "=" else { throw JQError.syntax("expected '=='", column: column) }
            advance()
            return .eq
        case "!":
            advance()
            guard current == "=" else { throw JQError.syntax("expected '!='", column: column) }
            advance()
            return .neq
        case "<":
            advance()
            if current == "=" { advance(); return .lte }
            return .lt
        case ">":
            advance()
            if current == "=" { advance(); return .gte }
            return .gt
        case "\"":
            return .string(try lexString())
        default:
            if character == "-" || character.isNumber {
                return try lexNumber()
            }
            if character.isLetter || character == "_" {
                return .identifier(lexIdentifier())
            }
            throw JQError.syntax("unexpected character '\(character)'", column: column)
        }
    }

    private mutating func lexIdentifier() -> String {
        var result = ""
        while let character = current, character.isLetter || character.isNumber || character == "_" {
            result.append(character)
            advance()
        }
        return result
    }

    private mutating func lexNumber() throws -> JQToken {
        var result = ""
        if current == "-" { result.append("-"); advance() }
        while let character = current,
              character.isNumber || character == "." || character == "e" || character == "E"
                || character == "+" || character == "-" {
            // Only consume +/- when they form an exponent (e.g. 1e-5).
            if character == "+" || character == "-" {
                let previous = result.last
                if previous != "e" && previous != "E" { break }
            }
            result.append(character)
            advance()
        }
        guard let value = Double(result) else {
            throw JQError.syntax("invalid number '\(result)'", column: column)
        }
        return .number(value)
    }

    private mutating func lexString() throws -> String {
        advance() // consume opening quote
        var result = ""
        while let character = current {
            if character == "\"" {
                advance()
                return result
            }
            if character == "\\" {
                advance()
                guard let escaped = current else { break }
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                default:
                    throw JQError.syntax("invalid escape '\\\(escaped)'", column: column)
                }
                advance()
                continue
            }
            result.append(character)
            advance()
        }
        throw JQError.syntax("unterminated string", column: column)
    }

    private mutating func skipWhitespace() {
        while let character = current, character.isWhitespace {
            advance()
        }
    }

    private var current: Character? {
        position < scalars.count ? scalars[position] : nil
    }

    private var column: Int { position + 1 }

    private mutating func advance() {
        if position < scalars.count { position += 1 }
    }
}
