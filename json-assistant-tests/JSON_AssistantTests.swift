//
//  JSON_AssistantTests.swift
//  JSON AssistantTests
//
//  Created by Facundo Goñi on 19/08/2024.
//

import XCTest
import Combine
@testable import json_assistant

final class JSON_AssistantTests: XCTestCase {

    func testExpandAllPublishesExpansionStateOnMainThread() async throws {
        let viewModel = await MainActor.run { JSONViewModel() }
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
