import Foundation

/// Comparison / boolean operators supported in conditions, e.g. `.age > 30`.
enum JQBinaryOp {
    case eq, neq, lt, lte, gt, gte, and, or
}

/// Abstract syntax tree for the supported subset of jq.
///
/// A filter maps a single input value to a *stream* of output values (jq's core
/// model). Composition (`a | b`) feeds each value of `a` into `b`; comma
/// (`a, b`) concatenates their streams. The evaluator in `JQEvaluator`
/// interprets these cases directly over the app's `Any`-typed JSON values.
indirect enum JQFilter: Equatable {
    /// `.` — emits the input unchanged.
    case identity
    /// `.foo` applied to the input (object lookup, or `null` passthrough).
    case field(String)
    /// `[<int>]` index suffix, e.g. `.items[0]`. Negative indexes count from the end.
    case index(Int)
    /// `["key"]` string-index suffix, equivalent to `.key` but for arbitrary keys.
    case indexKey(String)
    /// `.[]` — iterate an array's elements or an object's values.
    case iterateAll
    /// `a | b` — pipe each output of `a` into `b`.
    case pipe(JQFilter, JQFilter)
    /// `a, b` — concatenate the streams of `a` and `b`.
    case comma(JQFilter, JQFilter)
    /// `expr?` — suppress runtime errors from `expr`, yielding an empty stream instead.
    case optional(JQFilter)
    /// `{ k: v, ... }` — construct an object (key order preserved).
    case objectConstruction([JQObjectEntry])
    /// `[ expr ]` — collect the stream of `expr` into a single array (`nil` = `[]`).
    case arrayConstruction(JQFilter?)
    /// A literal value: number (`NSNumber`), string, bool (`NSNumber`), or `null` (`NSNull`).
    case literal(JQLiteral)
    /// A builtin call such as `length`, `keys`, `map(f)`, `select(f)`, `has("k")`.
    case call(String, [JQFilter])
    /// A comparison or boolean combination, e.g. `.a == 1`, `.a and .b`.
    case binary(JQBinaryOp, JQFilter, JQFilter)
}

/// One entry of an object-construction filter.
struct JQObjectEntry: Equatable {
    let key: String
    /// Filter producing the value for `key`, applied to the construction's input.
    let value: JQFilter
}

/// A literal value embedded in a query. Wrapped so `JQFilter` can stay `Equatable`
/// without forcing the heterogeneous `Any` payload to be comparable directly.
enum JQLiteral: Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case null

    /// The bridged `Any` value used during evaluation, matching the parser's types.
    var anyValue: Any {
        switch self {
        case let .number(value): return NSNumber(value: value)
        case let .string(value): return value
        case let .bool(value): return NSNumber(value: value)
        case .null: return NSNull()
        }
    }
}
