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
                    let scalar = try parseUnicodeScalar()
                    result.append(Character(scalar))
                    continue
                default:
                    throw OrderedJSONParserError.invalidLiteral("\\\(escaped)", position)
                }
                advance()
                continue
            }

            result.append(character)
            advance()
        }

        throw OrderedJSONParserError.unexpectedEndOfInput
    }

    private mutating func parseUnicodeScalar() throws -> UnicodeScalar {
        advance() // move past 'u'
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

        guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else {
            throw OrderedJSONParserError.invalidLiteral("\\u\(hex)", position)
        }
        return scalar
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

        guard let doubleValue = Double(numberString) else {
            throw OrderedJSONParserError.invalidNumber(numberString, position)
        }

        index = tempIndex
        return NSNumber(value: doubleValue)
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
