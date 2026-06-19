import Foundation

/// Outcome of running a query: the full output stream plus a single value
/// suitable for rendering in the JSON tree.
///
/// jq is the only engine that natively produces a *stream* of values; JMESPath
/// and JSONPath yield a single value (or a list), which each engine maps into
/// this same shape so the rest of the app stays engine-agnostic.
struct QueryResult {
    /// Every value the query produced, in order.
    let values: [Any]

    var count: Int { values.count }
    var isEmpty: Bool { values.isEmpty }

    /// The value handed to the tree renderer. A lone result is shown as-is; a
    /// multi-value stream is wrapped in an array; an empty stream renders as an
    /// empty array.
    var displayValue: Any {
        if values.count == 1 { return values[0] }
        return values as [Any]
    }
}

/// A query language backend. Each engine takes a query string and the app's
/// `Any`-typed JSON value and returns a `QueryResult`. Implementations must be
/// safe to call from a background queue.
protocol QueryEngine {
    func run(query: String, on input: Any) throws -> QueryResult
}

/// The query languages the app can run, used to drive the engine picker and to
/// resolve the concrete `QueryEngine` for a selection.
enum QueryEngineKind: String, CaseIterable, Identifiable {
    case jq
    case jmespath
    case jsonpath

    var id: String { rawValue }

    /// Short label shown in the engine picker.
    var displayName: String {
        switch self {
        case .jq: return "jq"
        case .jmespath: return "JMESPath"
        case .jsonpath: return "JSONPath"
        }
    }

    /// Placeholder text suggesting the syntax for each language.
    var placeholder: String {
        switch self {
        case .jq: return ".items[] | select(.active)"
        case .jmespath: return "items[?active].name"
        case .jsonpath: return "$.items[?(@.active)].name"
        }
    }

    /// The concrete engine backing this selection.
    var engine: QueryEngine {
        switch self {
        case .jq: return JQQueryEngine()
        case .jmespath: return JMESPathQueryEngine()
        case .jsonpath: return JSONPathQueryEngine()
        }
    }

    /// Engines available in the current build. JMESPath/JSONPath depend on
    /// optional SPM modules; when those are not linked the corresponding engine
    /// throws a friendly error, but we still keep the cases discoverable so the
    /// picker reflects intent.
    static var available: [QueryEngineKind] { allCases }
}

/// Adapts the hand-written jq engine to the `QueryEngine` protocol.
struct JQQueryEngine: QueryEngine {
    func run(query: String, on input: Any) throws -> QueryResult {
        try JQEngine.run(query: query, on: input)
    }
}
