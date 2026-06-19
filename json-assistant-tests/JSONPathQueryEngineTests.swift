//
//  JSONPathQueryEngineTests.swift
//  JSON AssistantTests
//
//  Conformance coverage for the hand-rolled JSONPath subset: selectors,
//  wildcards, recursive descent, slices, unions, and filters — including the
//  edge cases flagged during design (negative slices, NSNumber bool vs number,
//  missing fields, special-character keys).
//

import XCTest
@testable import JSON_Assistant

final class JSONPathQueryEngineTests: XCTestCase {

    private let engine = JSONPathQueryEngine()

    private func parse(_ json: String) throws -> Any {
        var parser = OrderedJSONParser(json)
        return try parser.parse()
    }

    private func run(_ query: String, on json: String) throws -> QueryResult {
        try engine.run(query: query, on: try parse(json))
    }

    /// Convenience: the result's values as strings (nil for non-strings).
    private func strings(_ query: String, on json: String) throws -> [String?] {
        try run(query, on: json).values.map { $0 as? String }
    }

    /// Convenience: the result's values as Doubles via NSNumber.
    private func numbers(_ query: String, on json: String) throws -> [Double?] {
        try run(query, on: json).values.map { ($0 as? NSNumber)?.doubleValue }
    }

    private let store = """
    {
      "store": {
        "books": [
          {"title": "A", "price": 10, "tags": ["x", "y"]},
          {"title": "B", "price": 25, "tags": ["y"]},
          {"title": "C", "price": 5}
        ],
        "bicycle": {"color": "red", "price": 100}
      }
    }
    """

    // MARK: - Root & child

    func testRootReturnsWholeDocument() throws {
        let result = try run("$", on: #"{"a": 1}"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.displayValue is OrderedDictionary)
    }

    func testChildDotAndBracketEquivalent() throws {
        XCTAssertEqual(try numbers("$.store.bicycle.price", on: store), [100])
        XCTAssertEqual(try numbers("$['store']['bicycle']['price']", on: store), [100])
    }

    func testMissingChildYieldsNoResults() throws {
        XCTAssertEqual(try run("$.store.nope", on: store).count, 0)
    }

    // MARK: - Index

    func testIndexAndNegativeIndex() throws {
        XCTAssertEqual(try strings("$.store.books[0].title", on: store), ["A"])
        XCTAssertEqual(try strings("$.store.books[-1].title", on: store), ["C"])
        XCTAssertEqual(try run("$.store.books[9]", on: store).count, 0)
    }

    // MARK: - Wildcard

    func testWildcardOverArray() throws {
        XCTAssertEqual(try strings("$.store.books[*].title", on: store), ["A", "B", "C"])
    }

    func testWildcardOverObjectKeepsKeyOrder() throws {
        // store has keys books, bicycle (in that order)
        let result = try run("$.store.*", on: store)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.values[0] is [Any])           // books array
        XCTAssertTrue(result.values[1] is OrderedDictionary) // bicycle object
    }

    // MARK: - Recursive descent

    func testRecursiveDescentByKey() throws {
        // every "price" at any depth: 10, 25, 5, 100
        XCTAssertEqual(try numbers("$..price", on: store), [10, 25, 5, 100])
    }

    func testRecursiveWildcardDoesNotDuplicateNodes() throws {
        let nested = #"{"a": {"b": 1}}"#
        // $..* => {b:1}, 1  (each member once)
        XCTAssertEqual(try run("$..*", on: nested).count, 2)
    }

    // MARK: - Slices

    func testPositiveSlice() throws {
        XCTAssertEqual(try numbers("$[0:2]", on: "[10,20,30,40]"), [10, 20])
    }

    func testSliceWithStep() throws {
        XCTAssertEqual(try numbers("$[0:4:2]", on: "[10,20,30,40]"), [10, 30])
    }

    func testNegativeSliceBounds() throws {
        XCTAssertEqual(try numbers("$[-2:]", on: "[10,20,30,40]"), [30, 40])
    }

    func testNegativeStepReverses() throws {
        XCTAssertEqual(try numbers("$[::-1]", on: "[10,20,30]"), [30, 20, 10])
    }

    func testZeroStepYieldsEmpty() throws {
        XCTAssertEqual(try run("$[::0]", on: "[10,20,30]").count, 0)
    }

    // MARK: - Union

    func testUnionOfKeys() throws {
        let json = #"{"a": 1, "b": 2, "c": 3}"#
        XCTAssertEqual(try numbers("$['a','c']", on: json), [1, 3])
    }

    func testUnionOfIndices() throws {
        XCTAssertEqual(try numbers("$[0,2]", on: "[10,20,30]"), [10, 30])
    }

    // MARK: - Filters

    func testFilterExistence() throws {
        // only books with a "tags" field
        XCTAssertEqual(try strings("$.store.books[?(@.tags)].title", on: store), ["A", "B"])
    }

    func testBareFilterIsTruthinessNotMereExistence() throws {
        // active is present on all three (true/false/true); a bare filter is a
        // truthiness test (like jq select), so the `false` book is excluded.
        let json = #"{"books":[{"t":"A","active":true},{"t":"B","active":false},{"t":"C","active":true}]}"#
        XCTAssertEqual(try strings("$.books[?(@.active)].t", on: json), ["A", "C"])
    }

    func testFilterNumericComparison() throws {
        XCTAssertEqual(try strings("$.store.books[?(@.price > 8)].title", on: store), ["A", "B"])
        XCTAssertEqual(try strings("$.store.books[?(@.price <= 10)].title", on: store), ["A", "C"])
    }

    func testFilterStringEquality() throws {
        XCTAssertEqual(try numbers("$.store.books[?(@.title == 'B')].price", on: store), [25])
    }

    func testFilterBoolDoesNotMatchNumberOne() throws {
        let json = #"{"items": [{"on": true, "n": 1}, {"on": false, "n": 2}]}"#
        // == true must match the boolean, never the number 1
        XCTAssertEqual(try numbers("$.items[?(@.on == true)].n", on: json), [1])
        XCTAssertEqual(try numbers("$.items[?(@.on == false)].n", on: json), [2])
    }

    func testFilterMissingFieldExcludes() throws {
        // book C has no tags -> excluded, no throw
        XCTAssertEqual(try run("$.store.books[?(@.tags == 'x')]", on: store).count, 0)
    }

    // MARK: - Special keys & errors

    func testSpecialCharacterKeyViaBracket() throws {
        let json = #"{"a.b": {"c d": 7}}"#
        XCTAssertEqual(try numbers("$['a.b']['c d']", on: json), [7])
    }

    func testNoMatchIsEmptyNotError() throws {
        XCTAssertEqual(try run("$.store.books[?(@.price > 999)]", on: store).count, 0)
    }

    func testInvalidSyntaxThrows() {
        XCTAssertThrowsError(try run("$.store.books[", on: store))
    }

    // MARK: - Goessner canonical conformance
    //
    // The original JSONPath bookstore example and its widely-agreed results
    // (Goessner reference + cross-implementation consensus). Our dialect is
    // Goessner-style (`[?(...)]` with parens). Two deliberate choices: a bare
    // `[?(@.x)]` filter is a truthiness test (like jq's select, not RFC 9535's
    // pure existence), and slices use Python semantics.

    private let goessner = """
    { "store": {
        "book": [
          { "category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century", "price": 8.95 },
          { "category": "fiction", "author": "Evelyn Waugh", "title": "Sword of Honour", "price": 12.99 },
          { "category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99 },
          { "category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", "isbn": "0-395-19395-8", "price": 22.99 }
        ],
        "bicycle": { "color": "red", "price": 19.95 }
    } }
    """

    func testGoessnerAuthorsViaWildcard() throws {
        XCTAssertEqual(try strings("$.store.book[*].author", on: goessner),
                       ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"])
    }

    func testGoessnerAuthorsViaRecursiveDescent() throws {
        XCTAssertEqual(try strings("$..author", on: goessner),
                       ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"])
    }

    func testGoessnerAllThingsInStore() throws {
        // $.store.* -> the book array and the bicycle object (2 nodes)
        let result = try run("$.store.*", on: goessner)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.values[0] is [Any])
        XCTAssertTrue(result.values[1] is OrderedDictionary)
    }

    func testGoessnerAllPrices() throws {
        XCTAssertEqual(try numbers("$.store..price", on: goessner),
                       [8.95, 12.99, 8.99, 22.99, 19.95])
    }

    func testGoessnerThirdBookTitle() throws {
        XCTAssertEqual(try strings("$..book[2].title", on: goessner), ["Moby Dick"])
    }

    func testGoessnerLastBookTitle() throws {
        XCTAssertEqual(try strings("$..book[-1].title", on: goessner), ["The Lord of the Rings"])
    }

    func testGoessnerFirstTwoViaUnion() throws {
        XCTAssertEqual(try strings("$..book[0,1].author", on: goessner), ["Nigel Rees", "Evelyn Waugh"])
    }

    func testGoessnerFirstTwoViaSlice() throws {
        XCTAssertEqual(try strings("$..book[:2].author", on: goessner), ["Nigel Rees", "Evelyn Waugh"])
    }

    func testGoessnerBooksWithIsbn() throws {
        // isbn present (truthy non-empty strings) -> Moby Dick and LOTR
        XCTAssertEqual(try strings("$..book[?(@.isbn)].title", on: goessner),
                       ["Moby Dick", "The Lord of the Rings"])
    }

    func testGoessnerCheapBooks() throws {
        XCTAssertEqual(try strings("$..book[?(@.price < 10)].title", on: goessner),
                       ["Sayings of the Century", "Moby Dick"])
    }

    func testGoessnerPriceAtMost899() throws {
        XCTAssertEqual(try strings("$..book[?(@.price <= 8.99)].title", on: goessner),
                       ["Sayings of the Century", "Moby Dick"])
    }
}
