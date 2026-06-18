//
//  JSON_AssistantTests.swift
//  JSON AssistantTests
//
//  Created by Facundo Goñi on 19/08/2024.
//

import XCTest
import Combine
import SwiftUI
import AppKit
@testable import JSON_Assistant

final class JSON_AssistantTests: XCTestCase {

    func testParserSupportsUnicodeSurrogatePairs() throws {
        var parser = OrderedJSONParser("{\"emoji\":\"\\uD83D\\uDE00\"}")
        let parsed = try parser.parse()
        let dictionary = try XCTUnwrap(parsed as? OrderedDictionary)

        XCTAssertEqual(dictionary["emoji"] as? String, "\u{1F600}")
    }

    func testParserRejectsUnescapedControlCharactersInStrings() throws {
        var parser = OrderedJSONParser("{\"name\":\"Coffee\nShop\"}")

        XCTAssertThrowsError(try parser.parse())
    }

    func testPersistenceServiceSavesAndLoadsFromFile() throws {
        let service = try makePersistenceService()
        let savedJSON = ParsedJSON(id: UUID(), date: Date(), name: "Sample", content: "{\"ok\":true}")

        service.save([savedJSON])

        let loadedJSONs = service.load()
        XCTAssertEqual(loadedJSONs.count, 1)
        XCTAssertEqual(loadedJSONs.first?.id, savedJSON.id)
        XCTAssertEqual(loadedJSONs.first?.name, "Sample")
        XCTAssertEqual(loadedJSONs.first?.content, "{\"ok\":true}")
    }

    func testTypingParseDoesNotSaveJSON() async throws {
        let persistenceService = try makePersistenceService()
        let viewModel = await MainActor.run { JSONViewModel(persistenceService: persistenceService) }
        let parsed = expectation(description: "JSON parsed")
        var cancellable: AnyCancellable?

        cancellable = await MainActor.run {
            viewModel.$rootNode
                .dropFirst()
                .sink { rootNode in
                    if rootNode != nil {
                        parsed.fulfill()
                    }
                }
        }

        await MainActor.run {
            viewModel.parseJSON("{\"name\":\"Coffee\"}", autoExpand: false)
        }

        await fulfillment(of: [parsed], timeout: 2.0)

        await MainActor.run {
            XCTAssertTrue(viewModel.parsedJSONs.isEmpty)
            XCTAssertNil(viewModel.selectedJSONID)
        }
        cancellable?.cancel()
    }

    func testBeautifyAndSavePersistsFormattedJSON() async throws {
        let persistenceService = try makePersistenceService()
        let viewModel = await MainActor.run { JSONViewModel(persistenceService: persistenceService) }
        let saved = expectation(description: "JSON saved")
        var cancellable: AnyCancellable?

        cancellable = await MainActor.run {
            viewModel.$parsedJSONs
                .dropFirst()
                .sink { savedJSONs in
                    if !savedJSONs.isEmpty {
                        saved.fulfill()
                    }
                }
        }

        await MainActor.run {
            viewModel.inputJSON = "{\"name\":\"Coffee\"}"
            viewModel.beautifyAndSaveJSON()
        }

        await fulfillment(of: [saved], timeout: 2.0)

        await MainActor.run {
            XCTAssertEqual(viewModel.parsedJSONs.count, 1)
            XCTAssertEqual(viewModel.parsedJSONs.first?.content, """
            {
                "name": "Coffee"
            }
            """)
            XCTAssertEqual(viewModel.selectedJSONID, viewModel.parsedJSONs.first?.id)
        }
        cancellable?.cancel()
    }

    func testExpandAllPublishesExpansionStateOnMainThread() async throws {
        let persistenceService = try makePersistenceService()
        let viewModel = await MainActor.run { JSONViewModel(persistenceService: persistenceService) }
        let rootNode = JSONNode(
            key: "Root",
            value: [
                "a": 1,
                "b": ["c": 2],
                "d": [1, 2, 3]
            ],
            isRoot: true
        )

        let expectedCount = countNodes(from: rootNode)
        await MainActor.run { viewModel.rootNode = rootNode }

        let published = expectation(description: "Expansion state published")
        var cancellable: AnyCancellable?

        cancellable = await MainActor.run {
            viewModel.$expansionState
                .dropFirst()
                .sink { state in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(state.count, expectedCount)
                    XCTAssertTrue(state.values.allSatisfy { $0 })
                    published.fulfill()
                }
        }

        await MainActor.run { viewModel.expandAll() }
        await fulfillment(of: [published], timeout: 2.0)

        cancellable?.cancel()
        await MainActor.run {
            XCTAssertFalse(viewModel.isExpandingOrCollapsing)
        }
    }

    // MARK: - Parser: structure & ordering

    func testParserPreservesObjectKeyOrder() throws {
        var parser = OrderedJSONParser("{\"z\":1,\"a\":2,\"m\":3}")
        let dict = try XCTUnwrap(try parser.parse() as? OrderedDictionary)
        XCTAssertEqual(dict.orderedPairs.map { $0.0 }, ["z", "a", "m"])
    }

    func testParserDuplicateKeysKeepLastValueAtFirstPosition() throws {
        var parser = OrderedJSONParser("{\"a\":1,\"b\":2,\"a\":3}")
        let dict = try XCTUnwrap(try parser.parse() as? OrderedDictionary)
        XCTAssertEqual(dict.orderedPairs.map { $0.0 }, ["a", "b"])
        XCTAssertEqual(dict["a"] as? NSNumber, 3)
    }

    func testParserParsesEmptyContainers() throws {
        var objParser = OrderedJSONParser("{}")
        XCTAssertEqual(try XCTUnwrap(try objParser.parse() as? OrderedDictionary).orderedPairs.count, 0)
        var arrParser = OrderedJSONParser("[]")
        XCTAssertEqual(try XCTUnwrap(try arrParser.parse() as? [Any]).count, 0)
    }

    func testParserParsesTopLevelScalars() throws {
        var numberParser = OrderedJSONParser("42")
        XCTAssertEqual(try numberParser.parse() as? NSNumber, 42)
        var stringParser = OrderedJSONParser("\"hi\"")
        XCTAssertEqual(try stringParser.parse() as? String, "hi")
        var boolParser = OrderedJSONParser("true")
        XCTAssertEqual(try boolParser.parse() as? NSNumber, NSNumber(value: true))
        var nullParser = OrderedJSONParser("null")
        XCTAssertTrue(try nullParser.parse() is NSNull)
    }

    // MARK: - Parser: numeric precision & escapes

    func testParserPreservesLargeIntegerPrecision() throws {
        var parser = OrderedJSONParser("{\"big\":9223372036854775807}")
        let dict = try XCTUnwrap(try parser.parse() as? OrderedDictionary)
        let number = try XCTUnwrap(dict["big"] as? NSNumber)
        XCTAssertEqual(number.stringValue, "9223372036854775807")
    }

    func testParserPreservesDecimalValues() throws {
        var parser = OrderedJSONParser("[0.1, 1.5, -2.25]")
        let array = try XCTUnwrap(try parser.parse() as? [Any])
        XCTAssertEqual((array[0] as? NSNumber)?.stringValue, "0.1")
        XCTAssertEqual((array[1] as? NSNumber)?.stringValue, "1.5")
        XCTAssertEqual((array[2] as? NSNumber)?.stringValue, "-2.25")
    }

    func testParserDecodesEscapeSequences() throws {
        var parser = OrderedJSONParser("{\"s\":\"line1\\nline2\\ttab\\\"quote\\\\slash\\/fwd\"}")
        let dict = try XCTUnwrap(try parser.parse() as? OrderedDictionary)
        XCTAssertEqual(dict["s"] as? String, "line1\nline2\ttab\"quote\\slash/fwd")
    }

    func testParserDecodesBMPUnicodeEscape() throws {
        var parser = OrderedJSONParser("{\"s\":\"caf\\u00e9\"}")
        let dict = try XCTUnwrap(try parser.parse() as? OrderedDictionary)
        XCTAssertEqual(dict["s"] as? String, "café")
    }

    // MARK: - Parser: invalid input diagnostics

    func testParserRejectsTrailingObjectComma() {
        var parser = OrderedJSONParser("{\"a\":1,}")
        XCTAssertThrowsError(try parser.parse())
    }

    func testParserRejectsTrailingArrayComma() {
        var parser = OrderedJSONParser("[1,2,]")
        XCTAssertThrowsError(try parser.parse())
    }

    func testParserRejectsUnclosedObject() {
        var parser = OrderedJSONParser("{\"a\":1")
        XCTAssertThrowsError(try parser.parse())
    }

    func testParserRejectsLeadingZeroNumber() {
        var parser = OrderedJSONParser("01")
        XCTAssertThrowsError(try parser.parse())
    }

    func testParserRejectsTrailingGarbage() {
        var parser = OrderedJSONParser("{\"a\":1} extra")
        XCTAssertThrowsError(try parser.parse())
    }

    func testParserRejectsUnquotedKey() {
        var parser = OrderedJSONParser("{a:1}")
        XCTAssertThrowsError(try parser.parse())
    }

    // MARK: - Formatter

    func testFormatterPreservesKeyOrderAndIndentation() throws {
        var parser = OrderedJSONParser("{\"b\":1,\"a\":{\"d\":2}}")
        let value = try parser.parse()
        let pretty = OrderedJSONFormatter.prettyPrinted(value)
        XCTAssertEqual(pretty, """
        {
            "b": 1,
            "a": {
                "d": 2
            }
        }
        """)
    }

    func testFormatterRoundTripsThroughParser() throws {
        let source = "{\"name\":\"Coffee\",\"tags\":[\"a\",\"b\"],\"open\":true,\"n\":null}"
        var parser = OrderedJSONParser(source)
        let pretty = OrderedJSONFormatter.prettyPrinted(try parser.parse())
        var reparser = OrderedJSONParser(pretty)
        let dict = try XCTUnwrap(try reparser.parse() as? OrderedDictionary)
        XCTAssertEqual(dict.orderedPairs.map { $0.0 }, ["name", "tags", "open", "n"])
        XCTAssertEqual(dict["name"] as? String, "Coffee")
        XCTAssertEqual((dict["tags"] as? [Any])?.count, 2)
    }

    func testFormatterEmptyContainers() {
        XCTAssertEqual(OrderedJSONFormatter.prettyPrinted(OrderedDictionary()), "{}")
        XCTAssertEqual(OrderedJSONFormatter.prettyPrinted([Any]()), "[]")
    }

    func testFormatterEscapesControlCharacters() {
        let dict = OrderedDictionary()
        dict["s"] = "tab\tnewline\n"
        XCTAssertEqual(OrderedJSONFormatter.prettyPrinted(dict), """
        {
            "s": "tab\\tnewline\\n"
        }
        """)
    }

    // MARK: - Truncation limits

    func testLargeArrayIsTruncatedAndRecorded() {
        let root = JSONNode(key: "Array", value: Array(0..<1500), isRoot: true)
        XCTAssertEqual(root.children.count, JSONNode.maxArrayElements)
        XCTAssertEqual(root.truncatedArrayTotal, 1500)
        XCTAssertEqual(root.truncation?.truncatedArrayCount, 1)
        XCTAssertTrue(root.truncation?.didTruncate ?? false)
    }

    func testSmallDocumentReportsNoTruncation() {
        let root = JSONNode(key: "Object", value: ["a": 1, "b": [1, 2, 3]], isRoot: true)
        XCTAssertNil(root.truncation)
    }

    func testDeepNestingHitsDepthLimit() {
        var value: Any = 1
        for _ in 0...(JSONNode.maxDepth + 2) { value = [value] }
        let root = JSONNode(key: "Array", value: value, isRoot: true)
        XCTAssertTrue(root.truncation?.depthLimitReached ?? false)
    }

    func testManyNodesHitNodeLimit() {
        var dict: [String: Any] = [:]
        for index in 0..<(JSONNode.maxNodes + 500) { dict["k\(index)"] = index }
        let root = JSONNode(key: "Object", value: dict, isRoot: true)
        XCTAssertTrue(root.truncation?.nodeLimitReached ?? false)
    }

    func testViewModelPublishesTruncationSummary() async throws {
        let service = try makePersistenceService()
        let viewModel = await MainActor.run { JSONViewModel(persistenceService: service) }
        let root = JSONNode(key: "Array", value: Array(0..<1200), isRoot: true)
        await MainActor.run { viewModel.rootNode = root }
        await MainActor.run {
            XCTAssertNotNil(viewModel.truncationSummary)
            XCTAssertEqual(viewModel.truncationSummary?.truncatedArrayCount, 1)
        }
    }

    // MARK: - Node JSONPath

    func testNodePathUsesDotAndBracketNotation() throws {
        var parser = OrderedJSONParser("{\"users\":[{\"name\":\"A\"},{\"name\":\"B\"}]}")
        let root = JSONNode(key: "Object", value: try parser.parse(), isRoot: true)
        XCTAssertEqual(root.path, "$")
        let users = try XCTUnwrap(root.children.first { $0.key == "users" })
        XCTAssertEqual(users.path, "$.users")
        let firstUser = try XCTUnwrap(users.children.first)
        XCTAssertEqual(firstUser.path, "$.users[0]")
        let name = try XCTUnwrap(firstUser.children.first { $0.key == "name" })
        XCTAssertEqual(name.path, "$.users[0].name")
    }

    func testNodePathQuotesNonIdentifierKeys() throws {
        var parser = OrderedJSONParser("{\"a-b\":1}")
        let root = JSONNode(key: "Object", value: try parser.parse(), isRoot: true)
        let child = try XCTUnwrap(root.children.first)
        XCTAssertEqual(child.path, "$[\"a-b\"]")
    }

    // MARK: - Performance benchmarks

    /// Builds a synthetic value of roughly `objectCount * 5` nodes, under the parser caps.
    private func makeLargeValue(objectCount: Int = 800) -> [Any] {
        var array: [Any] = []
        array.reserveCapacity(objectCount)
        for index in 0..<objectCount {
            array.append([
                "id": index,
                "name": "Item \(index)",
                "active": index % 2 == 0,
                "score": Double(index) * 1.5
            ])
        }
        return array
    }

    /// Appends a benchmark result line to a file under the app container so the
    /// harness can read it (NSLog/measure output does not reach xcodebuild stdout).
    private func recordBench(_ line: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("json_bench.txt")
        let entry = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
        NSLog("%@", line)
    }

    /// Measures tree construction time. Sensitive to eager vs lazy child building (Perf #3).
    func testBenchmarkTreeBuild() {
        let value = makeLargeValue()
        let iterations = 20
        let start = Date()
        for _ in 0..<iterations {
            _ = JSONNode(key: "Array", value: value, isRoot: true)
        }
        let avgMs = Date().timeIntervalSince(start) / Double(iterations) * 1000
        recordBench(String(format: "BENCH treeBuild nodes~4000 avgMs=%.2f", avgMs))
    }

#if DEBUG
    private func spinRunLoop(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Renders the tree in an offscreen host, fully expanded, then flips a single
    /// search match and counts how many row bodies re-evaluate. With row-render
    /// gating (Perf #1) this should be a small constant; without it, ~all rows.
    @MainActor
    func testBenchmarkRowRendersOnSearchChange() throws {
        let viewModel = JSONViewModel(persistenceService: try makePersistenceService())
        var dict: [String: Any] = [:]
        for index in 0..<120 { dict["key\(index)"] = ["a": index, "b": "value\(index)"] }
        let root = JSONNode(key: "Object", value: dict, isRoot: true)
        viewModel.rootNode = root

        // Expand everything synchronously so all rows are laid out.
        var stack: [JSONNode] = [root]
        while let node = stack.popLast() {
            viewModel.setExpanded(true, for: node.id)
            stack.append(contentsOf: node.children)
        }

        let themeSettings = ThemeSettings()
        let palette = ThemePalette.palette(for: .light)
        let view = JSONTreeView(rootNode: root, viewModel: viewModel, palette: palette, themeSettings: themeSettings)
            .environmentObject(themeSettings)
        let host = NSHostingView(rootView: AnyView(view))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        spinRunLoop(0.5)

        let initialRows = JSONRowRenderProbe.bodyCount

        // Flip a single row into a search match and re-render.
        JSONRowRenderProbe.reset()
        if let target = root.children.first {
            viewModel.formattedSearchMatches = [target.id]
        }
        host.layoutSubtreeIfNeeded()
        spinRunLoop(0.5)
        let rerenders = JSONRowRenderProbe.bodyCount

        recordBench("BENCH rowRendersOnSearchChange initialRows=\(initialRows) rerendersOnOneMatch=\(rerenders)")
        window.orderOut(nil)
        window.contentView = nil
    }
#endif

    // MARK: - Search index

    func testSearchIndexMatchesQueriesLongerThanEightCharacters() {
        var index = JSONViewModel.SearchIndex()
        let nodeID = UUID()
        index.addTokensForNode(nodeID, tokens: ["cruisetour"])

        // A 10-char value must match — the index used to store only 3–8 char
        // prefixes, so searching the full "CruiseTour" returned nothing.
        let longMatches = index.getMatchingTokens(for: "cruisetour")
        XCTAssertFalse(longMatches.isEmpty, "query longer than 8 chars should match")
        XCTAssertTrue(longMatches.contains { index.getMatchingNodeIDs(for: $0).contains(nodeID) })

        // Partial and mid-token substrings still match.
        XCTAssertFalse(index.getMatchingTokens(for: "cruise").isEmpty)
        XCTAssertFalse(index.getMatchingTokens(for: "tour").isEmpty)
        XCTAssertTrue(index.getMatchingTokens(for: "zzz").isEmpty)
    }

    @MainActor
    func testSearchMatchesMultiWordAndLongValues() {
        let root = JSONNode(
            key: "Object",
            value: ["cruiseLine": "Celebrity Cruises", "cruiseType": "CruiseTour"],
            isRoot: true
        )
        let cruiseLine = try! XCTUnwrap(root.children.first { $0.key == "cruiseLine" })
        let cruiseType = try! XCTUnwrap(root.children.first { $0.key == "cruiseType" })

        // Multi-word / phrase query.
        XCTAssertTrue(JSONViewModel._searchMatchingNodeIDs(for: "Celebrity Cruises", in: root).contains(cruiseLine.id))
        // Single word within a multi-word value.
        XCTAssertTrue(JSONViewModel._searchMatchingNodeIDs(for: "celebrity", in: root).contains(cruiseLine.id))
        // Full value longer than 8 characters.
        XCTAssertTrue(JSONViewModel._searchMatchingNodeIDs(for: "CruiseTour", in: root).contains(cruiseType.id))
        // Non-matching phrase.
        XCTAssertTrue(JSONViewModel._searchMatchingNodeIDs(for: "Royal Caribbean", in: root).isEmpty)
    }

    func testLoadJSONFromFileReadsAndSavesNewEntry() async throws {
        let persistenceService = try makePersistenceService()
        let viewModel = await MainActor.run { JSONViewModel(persistenceService: persistenceService) }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-\(UUID().uuidString).json")
        try #"{"line":"Celebrity Cruises","shipIds":[13524]}"#.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let saved = expectation(description: "dropped file parsed and saved")
        var cancellable: AnyCancellable?
        cancellable = await MainActor.run {
            viewModel.$parsedJSONs.dropFirst().sink { entries in
                if !entries.isEmpty { saved.fulfill() }
            }
        }

        await MainActor.run { viewModel.loadJSON(from: url) }
        await fulfillment(of: [saved], timeout: 3.0)

        await MainActor.run {
            XCTAssertEqual(viewModel.parsedJSONs.count, 1)
            XCTAssertNotNil(viewModel.rootNode)
            XCTAssertTrue(viewModel.parsedJSONs.first?.content.contains("Celebrity Cruises") ?? false)
        }
        cancellable?.cancel()
    }

    private func makePersistenceService() throws -> JSONPersistenceService {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("JSON_AssistantTests.\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("SavedJSONs.json")
        let suiteName = "JSON_AssistantTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return JSONPersistenceService(fileURL: fileURL, userDefaults: userDefaults)
    }

    private func countNodes(from root: JSONNode) -> Int {
        var count = 0
        var stack: [JSONNode] = [root]
        while let node = stack.popLast() {
            count += 1
            stack.append(contentsOf: node.children)
        }
        return count
    }

}
