//
//  JQEngineTests.swift
//  JSON AssistantTests
//
//  Coverage for the jq-subset query engine: lexing/parsing, evaluation
//  semantics, key-order preservation on reshape, and error handling.
//

import XCTest
@testable import JSON_Assistant

final class JQEngineTests: XCTestCase {

    // MARK: - Helpers

    private func parse(_ json: String) throws -> Any {
        var parser = OrderedJSONParser(json)
        return try parser.parse()
    }

    private func run(_ query: String, on json: String) throws -> QueryResult {
        let input = try parse(json)
        return try JQEngine.run(query: query, on: input)
    }

    /// Pretty-prints a query's single display value for stable comparison,
    /// preserving object key order via the app's formatter.
    private func runFormatted(_ query: String, on json: String) throws -> String {
        let result = try run(query, on: json)
        return OrderedJSONFormatter.prettyPrinted(result.displayValue)
    }

    // MARK: - Field access & chaining

    func testIdentityReturnsInput() throws {
        let result = try run(".", on: "{\"a\":1}")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result.values[0] as? OrderedDictionary)?["a"] as? NSNumber, 1)
    }

    func testFieldAccess() throws {
        let result = try run(".name", on: "{\"name\":\"Ada\",\"age\":42}")
        XCTAssertEqual(result.values.first as? String, "Ada")
    }

    func testNestedChaining() throws {
        let result = try run(".a.b.c", on: "{\"a\":{\"b\":{\"c\":7}}}")
        XCTAssertEqual(result.values.first as? NSNumber, 7)
    }

    func testMissingKeyIsNull() throws {
        let result = try run(".missing", on: "{\"a\":1}")
        XCTAssertTrue(result.values.first is NSNull)
    }

    func testFieldOnNullIsNull() throws {
        let result = try run(".a.b", on: "{\"a\":null}")
        XCTAssertTrue(result.values.first is NSNull)
    }

    func testQuotedKeyAccess() throws {
        let result = try run(".[\"weird key\"]", on: "{\"weird key\":99}")
        XCTAssertEqual(result.values.first as? NSNumber, 99)
    }

    // MARK: - Indexing & iteration

    func testArrayIndex() throws {
        let result = try run(".items[1]", on: "{\"items\":[10,20,30]}")
        XCTAssertEqual(result.values.first as? NSNumber, 20)
    }

    func testNegativeIndex() throws {
        let result = try run(".[-1]", on: "[1,2,3]")
        XCTAssertEqual(result.values.first as? NSNumber, 3)
    }

    func testOutOfRangeIndexIsNull() throws {
        let result = try run(".[5]", on: "[1,2,3]")
        XCTAssertTrue(result.values.first is NSNull)
    }

    func testIterateArrayProducesStream() throws {
        let result = try run(".[]", on: "[1,2,3]")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.values.map { $0 as? NSNumber }, [1, 2, 3])
    }

    func testIterateObjectProducesValues() throws {
        let result = try run(".[]", on: "{\"a\":1,\"b\":2}")
        XCTAssertEqual(result.values.map { $0 as? NSNumber }, [1, 2])
    }

    // MARK: - Pipe & object construction (the headline use case)

    func testPipeIntoObjectReshape() throws {
        let json = "{\"results\":[{\"id\":1,\"name\":\"A\",\"extra\":true},{\"id\":2,\"name\":\"B\",\"extra\":false}]}"
        let result = try run(".results[] | {id, name}", on: json)
        XCTAssertEqual(result.count, 2)

        let first = try XCTUnwrap(result.values[0] as? OrderedDictionary)
        XCTAssertEqual(first.orderedPairs.map { $0.0 }, ["id", "name"])
        XCTAssertEqual(first["id"] as? NSNumber, 1)
        XCTAssertEqual(first["name"] as? String, "A")
    }

    func testObjectConstructionPreservesDeclaredKeyOrder() throws {
        // Declared order (name, id) must win over the source order (id, name).
        let result = try run("{name, id}", on: "{\"id\":1,\"name\":\"A\"}")
        let object = try XCTUnwrap(result.values.first as? OrderedDictionary)
        XCTAssertEqual(object.orderedPairs.map { $0.0 }, ["name", "id"])
    }

    func testObjectConstructionWithExplicitValues() throws {
        let result = try run("{label: .name, n: .count}", on: "{\"name\":\"x\",\"count\":3}")
        let object = try XCTUnwrap(result.values.first as? OrderedDictionary)
        XCTAssertEqual(object["label"] as? String, "x")
        XCTAssertEqual(object["n"] as? NSNumber, 3)
    }

    func testArrayConstructionCollectsStream() throws {
        let result = try run("[.users[].name]", on: "{\"users\":[{\"name\":\"a\"},{\"name\":\"b\"}]}")
        XCTAssertEqual(result.count, 1)
        let array = try XCTUnwrap(result.values.first as? [Any])
        XCTAssertEqual(array.map { $0 as? String }, ["a", "b"])
    }

    // MARK: - select & comparisons

    func testSelectFiltersByComparison() throws {
        let json = "[{\"age\":20},{\"age\":40},{\"age\":60}]"
        let result = try run(".[] | select(.age > 30)", on: json)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual((result.values[0] as? OrderedDictionary)?["age"] as? NSNumber, 40)
    }

    func testSelectEqualityOnString() throws {
        let json = "[{\"type\":\"a\"},{\"type\":\"b\"}]"
        let result = try run(".[] | select(.type == \"b\")", on: json)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result.values[0] as? OrderedDictionary)?["type"] as? String, "b")
    }

    func testSelectWithAndOr() throws {
        let json = "[{\"a\":1,\"b\":1},{\"a\":1,\"b\":2},{\"a\":3,\"b\":2}]"
        let result = try run(".[] | select(.a == 1 and .b == 2)", on: json)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Builtins

    func testLength() throws {
        XCTAssertEqual(try run(".items | length", on: "{\"items\":[1,2,3,4]}").values.first as? NSNumber, 4)
        XCTAssertEqual(try run("length", on: "\"hello\"").values.first as? NSNumber, 5)
        XCTAssertEqual(try run("length", on: "{\"a\":1,\"b\":2}").values.first as? NSNumber, 2)
    }

    func testKeysAreSorted() throws {
        let result = try run("keys", on: "{\"b\":1,\"a\":2,\"c\":3}")
        let keys = try XCTUnwrap(result.values.first as? [Any])
        XCTAssertEqual(keys.map { $0 as? String }, ["a", "b", "c"])
    }

    func testKeysUnsortedPreservesOrder() throws {
        let result = try run("keys_unsorted", on: "{\"b\":1,\"a\":2,\"c\":3}")
        let keys = try XCTUnwrap(result.values.first as? [Any])
        XCTAssertEqual(keys.map { $0 as? String }, ["b", "a", "c"])
    }

    func testTypeBuiltin() throws {
        XCTAssertEqual(try run("type", on: "[1]").values.first as? String, "array")
        XCTAssertEqual(try run("type", on: "\"x\"").values.first as? String, "string")
        XCTAssertEqual(try run("type", on: "null").values.first as? String, "null")
        XCTAssertEqual(try run("type", on: "true").values.first as? String, "boolean")
        XCTAssertEqual(try run("type", on: "3").values.first as? String, "number")
        XCTAssertEqual(try run("type", on: "{}").values.first as? String, "object")
    }

    func testHas() throws {
        XCTAssertEqual(try run("has(\"a\")", on: "{\"a\":1}").values.first as? NSNumber, true)
        XCTAssertEqual(try run("has(\"z\")", on: "{\"a\":1}").values.first as? NSNumber, false)
    }

    func testMap() throws {
        let result = try run("map(.x)", on: "[{\"x\":1},{\"x\":2}]")
        let array = try XCTUnwrap(result.values.first as? [Any])
        XCTAssertEqual(array.map { $0 as? NSNumber }, [1, 2])
    }

    func testAddNumbers() throws {
        XCTAssertEqual(try run("add", on: "[1,2,3,4]").values.first as? NSNumber, 10)
    }

    func testAddStrings() throws {
        XCTAssertEqual(try run("add", on: "[\"a\",\"b\",\"c\"]").values.first as? String, "abc")
    }

    func testFirstAndLast() throws {
        XCTAssertEqual(try run("first", on: "[7,8,9]").values.first as? NSNumber, 7)
        XCTAssertEqual(try run("last", on: "[7,8,9]").values.first as? NSNumber, 9)
    }

    // MARK: - Optional & comma

    func testOptionalSuppressesError() throws {
        // Iterating a number errors; the `?` turns it into an empty stream.
        let result = try run(".[]?", on: "42")
        XCTAssertEqual(result.count, 0)
    }

    func testCommaConcatenatesStreams() throws {
        let result = try run(".a, .b", on: "{\"a\":1,\"b\":2}")
        XCTAssertEqual(result.values.map { $0 as? NSNumber }, [1, 2])
    }

    // MARK: - Result normalization

    func testMultiValueStreamWrappedAsArray() throws {
        let result = try run(".[]", on: "[1,2,3]")
        let display = try XCTUnwrap(result.displayValue as? [Any])
        XCTAssertEqual(display.count, 3)
    }

    func testEmptyStreamDisplaysAsEmptyArray() throws {
        let result = try run(".[] | select(.x > 100)", on: "[{\"x\":1}]")
        XCTAssertTrue(result.isEmpty)
        let display = try XCTUnwrap(result.displayValue as? [Any])
        XCTAssertTrue(display.isEmpty)
    }

    // MARK: - Errors

    func testSyntaxErrorThrows() throws {
        XCTAssertThrowsError(try run(".foo ==", on: "{}"))
    }

    func testUnterminatedStringThrows() throws {
        XCTAssertThrowsError(try run(".[\"abc", on: "{}"))
    }

    func testRuntimeErrorOnIndexingStringWithKey() throws {
        XCTAssertThrowsError(try run(".name.x", on: "{\"name\":\"Ada\"}")) { error in
            guard case JQError.runtime = error else {
                return XCTFail("Expected runtime error, got \(error)")
            }
        }
    }

    func testEmptyQueryThrows() throws {
        XCTAssertThrowsError(try JQEngine.run(query: "   ", on: NSNull()))
    }

    // MARK: - End-to-end formatting (key order through the formatter)

    func testReshapeFormattingPreservesOrder() throws {
        let json = "{\"results\":[{\"id\":1,\"name\":\"A\"}]}"
        let formatted = try runFormatted(".results[] | {name, id}", on: json)
        XCTAssertEqual(formatted, "{\n    \"name\": \"A\",\n    \"id\": 1\n}")
    }

    // MARK: - Differential conformance against the real jq CLI
    //
    // For every query our hand-rolled engine supports, the output value stream
    // must match `jq -c` exactly. Comparison is semantic (via jq's total order)
    // so number/whitespace formatting differences never cause false failures.
    // Skipped automatically when no `jq` binary is installed.

    private static let jqPath: String? = {
        ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private func runRealJQ(_ query: String, _ input: String) throws -> [Any] {
        guard let jqPath = Self.jqPath else { throw XCTSkip("jq CLI not installed") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: jqPath)
        process.arguments = ["-c", query]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        stdin.fileHandleForWriting.closeFile()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return try text.split(whereSeparator: \.isNewline).map { line in
            var parser = OrderedJSONParser(String(line))
            return try parser.parse()
        }
    }

    /// Asserts our engine's value stream equals real jq's for `query`.
    private func assertMatchesJQ(_ query: String, on input: String,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let mine = try JQEngine.run(query: query, on: parse(input)).values
        let theirs = try runRealJQ(query, input)
        XCTAssertEqual(mine.count, theirs.count,
                       "stream length differs for `\(query)` — mine=\(mine) jq=\(theirs)",
                       file: file, line: line)
        for (m, t) in zip(mine, theirs) {
            XCTAssertEqual(JQEvaluator.compare(m, t), 0,
                           "value differs for `\(query)` — mine=\(m) jq=\(t)",
                           file: file, line: line)
        }
    }

    func testConformanceIdentityAndFields() throws {
        let obj = #"{"a":1,"b":{"c":2},"arr":[10,20,30]}"#
        try assertMatchesJQ(".", on: obj)
        try assertMatchesJQ(".a", on: obj)
        try assertMatchesJQ(".b.c", on: obj)
        try assertMatchesJQ(".missing", on: obj)
        try assertMatchesJQ(".arr[0]", on: obj)
        try assertMatchesJQ(".arr[-1]", on: obj)
        try assertMatchesJQ(#".["a"]"#, on: obj)
    }

    func testConformanceIteration() throws {
        try assertMatchesJQ(".[]", on: "[1,2,3]")
        try assertMatchesJQ(".[]", on: #"{"x":1,"y":2,"z":3}"#)   // object values, key order
        try assertMatchesJQ(".a[]", on: #"{"a":[1,2,3]}"#)
    }

    func testConformancePipeAndComma() throws {
        try assertMatchesJQ(".a, .b", on: #"{"a":1,"b":2}"#)
        try assertMatchesJQ(".users[] | .name", on: #"{"users":[{"name":"A"},{"name":"B"}]}"#)
        try assertMatchesJQ(".a, .b, .a", on: #"{"a":1,"b":2}"#)
    }

    func testConformanceBuiltins() throws {
        try assertMatchesJQ(".v | length", on: "[1,2,3]".wrappedAsV)
        try assertMatchesJQ(".v | length", on: #""hello""#.wrappedAsV)
        try assertMatchesJQ(".v | length", on: "null".wrappedAsV)
        try assertMatchesJQ(".v | length", on: "-5".wrappedAsV)          // abs value
        try assertMatchesJQ("keys", on: #"{"b":1,"a":2,"c":3}"#)         // sorted
        try assertMatchesJQ("keys_unsorted", on: #"{"b":1,"a":2}"#)
        try assertMatchesJQ(".v | type", on: "[1]".wrappedAsV)
        try assertMatchesJQ(".v | type", on: "true".wrappedAsV)
        try assertMatchesJQ(#"has("a")"#, on: #"{"a":1,"b":2}"#)
        try assertMatchesJQ(#"has("z")"#, on: #"{"a":1}"#)
        try assertMatchesJQ("add", on: "[1,2,3]")
        try assertMatchesJQ("add", on: #"["a","b","c"]"#)
        try assertMatchesJQ("first", on: "[5,6,7]")
        try assertMatchesJQ("last", on: "[5,6,7]")
    }

    func testConformanceMapSelect() throws {
        try assertMatchesJQ("map(.price)", on: #"[{"price":1},{"price":2}]"#)
        try assertMatchesJQ(".[] | select(.active)", on: #"[{"active":true,"n":1},{"active":false,"n":2}]"#)
        try assertMatchesJQ(".[] | select(.n > 1)", on: #"[{"n":1},{"n":2},{"n":3}]"#)
        try assertMatchesJQ(".[] | select(.n >= 2) | .n", on: #"[{"n":1},{"n":2},{"n":3}]"#)
    }

    func testConformanceComparisonsTypeOrdering() throws {
        // jq total order: null < false < true < numbers < strings < arrays < objects
        try assertMatchesJQ(".a < .b", on: #"{"a":null,"b":false}"#)
        try assertMatchesJQ(".a < .b", on: #"{"a":false,"b":true}"#)
        try assertMatchesJQ(".a < .b", on: #"{"a":true,"b":1}"#)
        try assertMatchesJQ(".a < .b", on: #"{"a":99,"b":"x"}"#)
        try assertMatchesJQ(".a == .b", on: #"{"a":1,"b":1}"#)
        try assertMatchesJQ(".a != .b", on: #"{"a":1,"b":2}"#)
        try assertMatchesJQ(".a and .b", on: #"{"a":true,"b":false}"#)
        try assertMatchesJQ(".a or .b", on: #"{"a":false,"b":1}"#)
    }

    func testConformanceConstruction() throws {
        try assertMatchesJQ("{x: .a, y: .b}", on: #"{"a":1,"b":2}"#)
        try assertMatchesJQ("[.a, .b]", on: #"{"a":1,"b":2}"#)
        try assertMatchesJQ("[.[]]", on: "[1,2,3]")
        try assertMatchesJQ(".results[] | {name, id}", on: #"{"results":[{"id":1,"name":"A"},{"id":2,"name":"B"}]}"#)
    }
}

private extension String {
    /// Wraps a JSON fragment as the value of `{"v": …}` so a query can reach a
    /// top-level scalar via `.v` (keeps inputs valid for both engines).
    var wrappedAsV: String { #"{"v":"# + self + "}" }
}
