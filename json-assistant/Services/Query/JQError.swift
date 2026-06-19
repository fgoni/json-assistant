import Foundation

/// Errors surfaced while lexing, parsing, or evaluating a jq query.
/// `errorDescription` is shown inline beneath the query bar, so messages are
/// kept short and user-facing rather than developer-oriented.
enum JQError: Error, LocalizedError, Equatable {
    /// Tokenizer hit an unexpected character at a 1-based column.
    case syntax(String, column: Int)
    /// Parser reached an unexpected token / end of input.
    case parse(String)
    /// Evaluation failed (e.g. iterating over a number, indexing a string with a key).
    case runtime(String)

    var errorDescription: String? {
        switch self {
        case let .syntax(message, column):
            return "Syntax error at \(column): \(message)"
        case let .parse(message):
            return message
        case let .runtime(message):
            return message
        }
    }
}
