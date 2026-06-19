//
//  JMESPathQueryEngineTests.swift
//  JSON AssistantTests
//
//  Coverage for the JMESPath engine and its OrderedDictionary <-> Foundation
//  bridge: scalar type round-trips, object/array reshaping, no-match handling,
//  and error surfacing.
//

import XCTest
@testable import JSON_Assistant

final class JMESPathQueryEngineTests: XCTestCase {

    private let engine = JMESPathQueryEngine()

    private func parse(_ json: String) throws -> Any {
        var parser = OrderedJSONParser(json)
        return try parser.parse()
    }

    private func run(_ query: String, on json: String) throws -> QueryResult {
        try engine.run(query: query, on: try parse(json))
    }

    // MARK: - Field access & scalar round-trips

    func testFieldAccessString() throws {
        let result = try run("a.b", on: #"{"a": {"b": "hello"}}"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.displayValue as? String, "hello")
    }

    func testIntegerRoundTripsAsNumber() throws {
        let value = try XCTUnwrap(run("a", on: #"{"a": 42}"#).displayValue as? NSNumber)
        XCTAssertEqual(value, NSNumber(value: 42))
        // Must not be coerced into a boolean.
        XCTAssertFalse(CFGetTypeID(value) == CFBooleanGetTypeID())
    }

    func testDoubleRoundTripsAsNumber() throws {
        let value = try XCTUnwrap(run("a", on: #"{"a": 3.5}"#).displayValue as? NSNumber)
        XCTAssertEqual(value.doubleValue, 3.5, accuracy: 0.0001)
    }

    func testBooleanRoundTripsAsBool() throws {
        let value = try XCTUnwrap(run("a", on: #"{"a": true}"#).displayValue as? NSNumber)
        XCTAssertTrue(CFGetTypeID(value) == CFBooleanGetTypeID())
        XCTAssertEqual(value.boolValue, true)
    }

    // MARK: - Filtering & projection

    func testFilterProjection() throws {
        let json = #"{"people": [{"name": "Ann", "age": 40}, {"name": "Bob", "age": 20}]}"#
        let result = try run("people[?age > `30`].name", on: json)
        let names = try XCTUnwrap(result.displayValue as? [Any])
        XCTAssertEqual(names.map { $0 as? String }, ["Ann"])
    }

    func testMultiselectHashReshape() throws {
        let json = #"{"a": 1, "b": 2, "c": 3}"#
        let result = try run("{x: a, y: c}", on: json)
        let dict = try XCTUnwrap(result.displayValue as? OrderedDictionary)
        XCTAssertEqual(dict["x"] as? NSNumber, NSNumber(value: 1))
        XCTAssertEqual(dict["y"] as? NSNumber, NSNumber(value: 3))
    }

    // MARK: - No match & null

    func testNoMatchYieldsEmptyStream() throws {
        let result = try run("missing", on: #"{"a": 1}"#)
        XCTAssertEqual(result.count, 0)
        XCTAssertTrue(result.isEmpty)
    }

    func testNullValueYieldsEmptyStream() throws {
        // JMESPath returns null for an explicit null, which we treat as no result.
        let result = try run("a", on: #"{"a": null}"#)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Errors

    func testInvalidExpressionThrows() {
        XCTAssertThrowsError(try run("a[", on: #"{"a": [1]}"#))
    }
}
