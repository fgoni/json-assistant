import Foundation
#if canImport(JMESPath)
import JMESPath
#endif

/// Runs JMESPath expressions against the app's `Any`-typed JSON model.
///
/// jmespath.swift matches native Swift scalars (`BinaryInteger`,
/// `BinaryFloatingPoint`, `Bool`, `String`), `[String: Any]`, `[Any]`, and its
/// own `JMESNull` — but **not** `NSNumber` / `NSNull`, which the app's parser
/// produces. So input is bridged to native types (and `JMESNull`) before the
/// search, and the result is bridged back to the app's canonical model
/// (`OrderedDictionary` for objects, `NSNumber` for scalars, `NSNull` for null)
/// so the tree renderer behaves identically to a normal document.
///
/// JMESPath yields a single value (or `nil` for no match) rather than jq's
/// value stream: a match becomes a one-element stream, no match an empty one.
struct JMESPathQueryEngine: QueryEngine {
    func run(query: String, on input: Any) throws -> QueryResult {
        #if canImport(JMESPath)
        let expression: JMESExpression
        do {
            expression = try JMESExpression.compile(query)
        } catch {
            throw JQError.parse(Self.message(from: error))
        }

        let bridgedInput = Self.toJMESInput(input)
        let raw: Any?
        do {
            raw = try expression.search(object: bridgedInput)
        } catch {
            throw JQError.runtime(Self.message(from: error))
        }

        // JMESPath returns nil for "no match" (and for an explicit null result);
        // both map to an empty stream so the UI reads "0 results".
        guard let raw else { return QueryResult(values: []) }
        return QueryResult(values: [Self.toAppModel(raw)])
        #else
        throw JQError.runtime(
            "JMESPath isn't available in this build. Add the package in Xcode "
                + "(File ▸ Add Package Dependencies… ▸ https://github.com/jmespath/jmespath.swift)."
        )
        #endif
    }

    #if canImport(JMESPath)
    private static func message(from error: Error) -> String {
        // jmespath errors carry their detail in their textual description rather
        // than `localizedDescription`, so prefer that.
        let described = String(describing: error)
        return described.isEmpty ? error.localizedDescription : described
    }

    // MARK: - Input bridge (app model -> jmespath-native)

    /// Converts the app's JSON value into types jmespath.swift matches natively.
    private static func toJMESInput(_ value: Any) -> Any {
        switch value {
        case let dict as OrderedDictionary:
            var out: [String: Any] = [:]
            for (key, element) in dict.orderedPairs { out[key] = toJMESInput(element) }
            return out
        case let dict as [String: Any]:
            return dict.mapValues { toJMESInput($0) }
        case let array as [Any]:
            return array.map { toJMESInput($0) }
        case is NSNull:
            // jmespath.swift matches `NSNull` natively (maps to its null), so it
            // passes straight through.
            return NSNull()
        case let number as NSNumber:
            return scalar(from: number)
        default:
            // Native String / Bool / Int / Double pass straight through.
            return value
        }
    }

    /// Unwraps an `NSNumber` into a native `Bool`, `Int`, or `Double` so it hits
    /// the right case in jmespath's initializer (booleans must not be coerced to
    /// numbers, and vice versa).
    private static func scalar(from number: NSNumber) -> Any {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        if CFNumberIsFloatType(number) {
            return number.doubleValue
        }
        return number.intValue
    }
    #endif

    // MARK: - Output bridge (jmespath result -> app model)

    /// Converts a jmespath result back into the app's canonical JSON model so the
    /// tree renderer treats it exactly like a parsed document.
    static func toAppModel(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]:
            let ordered = OrderedDictionary()
            for (key, element) in dict { ordered[key] = toAppModel(element) }
            return ordered
        case let dict as [AnyHashable: Any]:
            let ordered = OrderedDictionary()
            for (key, element) in dict { ordered["\(key)"] = toAppModel(element) }
            return ordered
        case let array as [Any]:
            return array.map { toAppModel($0) }
        case let bool as Bool:
            return NSNumber(value: bool)
        case let int as Int:
            return NSNumber(value: int)
        case let double as Double:
            return NSNumber(value: double)
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        case is NSNull:
            return NSNull()
        default:
            return value
        }
    }
}
