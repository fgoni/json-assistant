import Foundation

struct ParsedJSON: Identifiable, Codable {
    let id: UUID
    let date: Date
    var name: String
    let content: String
    /// Per-file query workbench text, restored when the file is reopened.
    /// Optional so documents saved before this field shipped decode cleanly.
    var query: String?
    /// Per-file query engine (`QueryEngineKind` rawValue), restored on reopen.
    var queryEngine: String?
    /// Per-file Formatted-tab search text, restored on reopen.
    var searchQuery: String?
}
