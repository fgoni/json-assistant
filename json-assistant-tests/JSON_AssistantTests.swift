//
//  JSON_AssistantTests.swift
//  JSON AssistantTests
//
//  Created by Facundo Goñi on 19/08/2024.
//

import XCTest
import Combine
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
