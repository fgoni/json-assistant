import Foundation

/// Facade over the jq lexer → parser → evaluator pipeline.
///
/// Parsed ASTs are cached by query string so repeated runs of the same query
/// (e.g. when the input JSON is re-parsed while a query is active) skip lexing
/// and parsing. `NSCache` makes the cache safe to touch from the background
/// queue the view model evaluates on.
enum JQEngine {
    private static let astCache = NSCache<NSString, ASTBox>()

    private final class ASTBox {
        let filter: JQFilter
        init(_ filter: JQFilter) { self.filter = filter }
    }

    /// Runs `query` against `input`. Throws `JQError` on syntax, parse, or
    /// runtime failure. An empty / whitespace-only query throws `.parse`.
    static func run(query: String, on input: Any) throws -> QueryResult {
        let filter = try compile(query)
        let values = try JQEvaluator().evaluate(filter, input)
        return QueryResult(values: values)
    }

    /// Parses `query` into a filter, returning a cached AST when available.
    static func compile(_ query: String) throws -> JQFilter {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JQError.parse("Empty query")
        }

        let cacheKey = trimmed as NSString
        if let cached = astCache.object(forKey: cacheKey) {
            return cached.filter
        }

        var lexer = JQLexer(trimmed)
        let tokens = try lexer.tokenize()
        var parser = JQParser(tokens: tokens)
        let filter = try parser.parse()

        astCache.setObject(ASTBox(filter), forKey: cacheKey)
        return filter
    }
}
