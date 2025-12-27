import Foundation

enum OrderedJSONParserError: LocalizedError {
    case unexpectedCharacter(Character, Int)
    case unexpectedEndOfInput
    case invalidLiteral(String, Int)
    case invalidNumber(String, Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let character, let position):
            return "Unexpected character '\(character)' at position \(position)."
        case .unexpectedEndOfInput:
            return "Unexpected end of JSON input."
        case .invalidLiteral(let literal, let position):
            return "Invalid literal '\(literal)' at position \(position)."
        case .invalidNumber(let literal, let position):
            return "Invalid number '\(literal)' at position \(position)."
        }
    }
}
