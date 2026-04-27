import Foundation

struct OrderedJSONParser {
    private let input: String
    private var index: String.Index

    init(_ input: String) {
        self.input = input
        self.index = input.startIndex
    }

    mutating func parse() throws -> Any {
        skipWhitespace()
        guard !isAtEnd else {
            throw OrderedJSONParserError.unexpectedEndOfInput
        }

        let value = try parseValue()
        skipWhitespace()
        if !isAtEnd {
            let character = currentCharacter ?? Character(" ")
            throw OrderedJSONParserError.unexpectedCharacter(character, position)
        }
        return value
    }

    private mutating func parseValue() throws -> Any {
        skipWhitespace()
        guard let character = currentCharacter else {
            throw OrderedJSONParserError.unexpectedEndOfInput
        }

        switch character {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return try parseString()
        case "-", "0"..."9": return try parseNumber()
        case "t", "f", "n": return try parseLiteral()
        default:
            throw OrderedJSONParserError.unexpectedCharacter(character, position)
        }
    }

    private mutating func parseObject() throws -> OrderedDictionary {
        try expect("{")
        skipWhitespace()

        let dictionary = OrderedDictionary()
        if match("}") {
            return dictionary
        }

        repeat {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(":")
            let value = try parseValue()
            dictionary[key] = value
            skipWhitespace()
        } while match(",")

        try expect("}")
        return dictionary
    }

    private mutating func parseArray() throws -> [Any] {
        try expect("[")
        skipWhitespace()

        var array: [Any] = []
        if match("]") {
            return array
        }

        repeat {
            let value = try parseValue()
            array.append(value)
            skipWhitespace()
        } while match(",")

        try expect("]")
        return array
    }

    private mutating func parseString() throws -> String {
        try expect("\"")
        var result = ""

        while !isAtEnd {
            guard let character = currentCharacter else {
                throw OrderedJSONParserError.unexpectedEndOfInput
            }

            if character == "\"" {
                advance()
                return result
            }

            if character == "\\" {
                advance()
                guard let escaped = currentCharacter else {
                    throw OrderedJSONParserError.unexpectedEndOfInput
                }

                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    result.append(try parseUnicodeEscape())
                    continue
                default:
                    throw OrderedJSONParserError.invalidLiteral("\\\(escaped)", position)
                }
                advance()
                continue
            }

            guard character.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else {
                throw OrderedJSONParserError.invalidLiteral(String(character), position)
            }

            result.append(character)
            advance()
        }

        throw OrderedJSONParserError.unexpectedEndOfInput
    }

    private mutating func parseUnicodeEscape() throws -> String {
        advance() // move past 'u'
        let value = try parseUnicodeHexValue()

        if (0xD800...0xDBFF).contains(value) {
            guard currentCharacter == "\\" else {
                throw OrderedJSONParserError.invalidLiteral(String(format: "\\u%04X", value), position)
            }
            advance()
            guard currentCharacter == "u" else {
                throw OrderedJSONParserError.invalidLiteral("\\", position)
            }
            advance()
            let lowSurrogate = try parseUnicodeHexValue()
            guard (0xDC00...0xDFFF).contains(lowSurrogate) else {
                throw OrderedJSONParserError.invalidLiteral(String(format: "\\u%04X", lowSurrogate), position)
            }

            let high = value - 0xD800
            let low = lowSurrogate - 0xDC00
            let scalarValue = 0x10000 + ((high << 10) | low)
            guard let scalar = UnicodeScalar(scalarValue) else {
                throw OrderedJSONParserError.invalidLiteral(String(format: "\\u%04X\\u%04X", value, lowSurrogate), position)
            }
            return String(Character(scalar))
        }

        guard !(0xDC00...0xDFFF).contains(value), let scalar = UnicodeScalar(value) else {
            throw OrderedJSONParserError.invalidLiteral(String(format: "\\u%04X", value), position)
        }

        return String(Character(scalar))
    }

    private mutating func parseUnicodeHexValue() throws -> UInt32 {
        var hex = ""
        for _ in 0..<4 {
            guard let character = currentCharacter else {
                throw OrderedJSONParserError.unexpectedEndOfInput
            }
            guard character.isHexDigit else {
                throw OrderedJSONParserError.invalidLiteral(String(character), position)
            }
            hex.append(character)
            advance()
        }

        guard let value = UInt32(hex, radix: 16) else {
            throw OrderedJSONParserError.invalidLiteral("\\u\(hex)", position)
        }
        return value
    }

    private mutating func parseLiteral() throws -> Any {
        if match(string: "true") {
            return NSNumber(value: true)
        }
        if match(string: "false") {
            return NSNumber(value: false)
        }
        if match(string: "null") {
            return NSNull()
        }
        let character = currentCharacter ?? Character(" ")
        throw OrderedJSONParserError.invalidLiteral(String(character), position)
    }

    private mutating func parseNumber() throws -> Any {
        let start = index
        var tempIndex = index
        let allowedCharacters = CharacterSet(charactersIn: "-+0123456789.eE")

        while tempIndex < input.endIndex,
              let scalar = input[tempIndex].unicodeScalars.first,
              allowedCharacters.contains(scalar) {
            tempIndex = input.index(after: tempIndex)
        }

        let numberString = String(input[start..<tempIndex])
        guard !numberString.isEmpty else {
            throw OrderedJSONParserError.invalidNumber(numberString, position)
        }

        let wrapped = "[\(numberString)]"
        guard
            let data = wrapped.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
            let value = parsed.first
        else {
            throw OrderedJSONParserError.invalidNumber(numberString, position)
        }

        index = tempIndex
        return value
    }

    private mutating func expect(_ character: Character) throws {
        guard currentCharacter == character else {
            let found = currentCharacter ?? Character(" ")
            throw OrderedJSONParserError.unexpectedCharacter(found, position)
        }
        advance()
    }

    private mutating func match(_ character: Character) -> Bool {
        if currentCharacter == character {
            advance()
            return true
        }
        return false
    }

    private mutating func match(string: String) -> Bool {
        var tempIndex = index
        for character in string {
            if tempIndex == input.endIndex || input[tempIndex] != character {
                return false
            }
            tempIndex = input.index(after: tempIndex)
        }
        index = tempIndex
        return true
    }

    private mutating func advance() {
        if !isAtEnd {
            index = input.index(after: index)
        }
    }

    private mutating func skipWhitespace() {
        while let character = currentCharacter, character.isWhitespace {
            advance()
        }
    }

    private var currentCharacter: Character? {
        guard !isAtEnd else { return nil }
        return input[index]
    }

    private var position: Int {
        input.distance(from: input.startIndex, to: index) + 1
    }

    private var isAtEnd: Bool {
        index >= input.endIndex
    }
}
