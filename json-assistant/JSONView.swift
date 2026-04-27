import SwiftUI
import Foundation
import os

struct CollapsibleJSONView: View {
    let node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    let depth: Int
    @ObservedObject var themeSettings: ThemeSettings
    @State private var visibleChildrenCount: Int = 30
    @State private var renderStartTime: Date?

    init(node: JSONNode, viewModel: JSONViewModel, palette: ThemePalette, depth: Int = 0, themeSettings: ThemeSettings) {
        self.node = node
        self.viewModel = viewModel
        self.palette = palette
        self.depth = depth
        self.themeSettings = themeSettings
    }

    private var wordWrap: Bool {
        themeSettings.formattedJSONWordWrap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JSONNodeView(node: node, viewModel: viewModel, palette: palette, wordWrap: wordWrap)

            // Only render children when expanded, and limit depth to prevent excessive nesting
            if viewModel.isExpanded(node.id) && !node.children.isEmpty && depth < 50 {
                // Compute children to render
                let childrenToRender = node.isFullyLoaded
                    ? node.children
                    : Array(node.children.prefix(visibleChildrenCount))

                // Use regular VStack instead of LazyVStack to avoid constant view creation/destruction during scroll
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(childrenToRender) { child in
                        // Use offset instead of padding to avoid nested layout containers
                        CollapsibleJSONView(node: child, viewModel: viewModel, palette: palette, depth: depth + 1, themeSettings: themeSettings)
                            .offset(x: 16)
                            .id(child.id)
                    }

                    // Show "Load More" button if there are hidden children and not fully loaded
                    if !node.isFullyLoaded && node.children.count > visibleChildrenCount {
                        loadMoreButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .id(node.id)
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        Button {
            // Increase visible count by 50
            visibleChildrenCount = min(visibleChildrenCount + 50, node.children.count)
        } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle.fill")
                    .foregroundColor(palette.accent)
                Text("Show \(min(50, node.children.count - visibleChildrenCount)) more...")
                    .foregroundColor(palette.accent)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


struct JSONNodeView: View {
    let node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    let wordWrap: Bool
    @State private var renderCount = 0

    var body: some View {
        let isHighlighted = viewModel.formattedSearchMatches.contains(node.id)
        let isFocused = viewModel.formattedSearchFocusedID == node.id
        let isNodeExpanded = viewModel.isExpanded(node.id)

        let (keyColor, punctuationColor, keyWeight): (Color, Color, Font.Weight) = {
            if isFocused {
                return (palette.surface, palette.surface.opacity(0.95), .semibold)
            } else if isHighlighted {
                return (palette.accent, palette.accent.opacity(0.9), .semibold)
            } else {
                return (palette.key, palette.punctuation, .regular)
            }
        }()

        let backgroundColor = isFocused
            ? palette.accent.opacity(0.32)
            : (isHighlighted ? palette.accent.opacity(0.18) : Color.clear)
        let borderColor = isFocused
            ? palette.accent.opacity(0.6)
            : (isHighlighted ? palette.accent.opacity(0.35) : Color.clear)
        let hasBorder = isFocused || isHighlighted

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isNodeExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                .foregroundColor(palette.muted)
                .opacity(node.children.isEmpty ? 0 : 1)
                .onTapGesture {
                    guard !node.children.isEmpty else { return }
                    viewModel.toggleExpansion(for: node.id)
                }
            
            if node.isRoot {
                Text(node.typeDescription)
                    .foregroundColor(isFocused ? palette.surface : palette.muted)
                    .fontWeight(isFocused ? .semibold : .regular)
                    .formattedLineWrap(wordWrap)
            } else {
                Text(node.key)
                    .foregroundColor(keyColor)
                    .fontWeight(keyWeight)
                    .formattedLineWrap(wordWrap)
                Text(":")
                    .foregroundColor(punctuationColor)
                    .fontWeight(keyWeight)
            }
            
            if node.children.isEmpty {
                leafValueView
            } else if !node.isRoot {
                Text(node.typeDescription)
                    .foregroundColor(palette.muted)
            }
            
            if wordWrap {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
    }
    
    @ViewBuilder
    private var leafValueView: some View {
        if node.value is OrderedDictionary || node.value is [String: Any] {
            Text("Object")
                .foregroundColor(palette.muted)
                .textSelection(.enabled)
                .formattedLineWrap(wordWrap)
        } else if node.value is [Any] {
            Text("Array")
                .foregroundColor(palette.muted)
                .textSelection(.enabled)
                .formattedLineWrap(wordWrap)
        } else if let stringValue = node.value as? String {
            if let url = URL(string: stringValue),
               let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()) {
                Link(destination: url) {
                    Text(node.displayValue)
                        .foregroundColor(palette.accent)
                        .formattedLineWrap(wordWrap)
                }
                .textSelection(.enabled)
            } else {
                Text(node.displayValue)
                    .foregroundColor(palette.string)
                    .textSelection(.enabled)
                    .formattedLineWrap(wordWrap)
            }
        } else if let number = node.value as? NSNumber {
            if number.isBool {
                Text(node.displayValue)
                    .foregroundColor(number.boolValue ? palette.boolTrue : palette.boolFalse)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
                    .formattedLineWrap(wordWrap)
            } else {
                Text(node.displayValue)
                    .foregroundColor(palette.number)
                    .textSelection(.enabled)
                    .formattedLineWrap(wordWrap)
            }
        } else if node.value is NSNull {
            Text(node.displayValue)
                .foregroundColor(palette.null)
                .italic()
                .textSelection(.enabled)
                .formattedLineWrap(wordWrap)
        } else {
            Text(node.displayValue)
                .foregroundColor(palette.number)
                .textSelection(.enabled)
                .formattedLineWrap(wordWrap)
        }
    }
}

private extension View {
    func formattedLineWrap(_ wordWrap: Bool) -> some View {
        lineLimit(wordWrap ? nil : 1)
            .fixedSize(horizontal: !wordWrap, vertical: false)
    }
}




@MainActor
class JSONViewModel: ObservableObject {
    @Published var inputJSON: String = ""
    @Published var rootNode: JSONNode? {
        didSet { rebuildNodeLookup() }
    }
    @Published var errorMessage: String?
    @Published var isLoadingJSON: Bool = false
    @Published var parsedJSONs: [ParsedJSON] = []
    @Published var selectedJSONID: UUID?
    @Published var isSubmittingFeedback: Bool = false
    @Published var feedbackSubmissionMessage: String?
    @Published var feedbackSubmissionIsError: Bool = false
    @Published var formattedSearchQuery: String = ""
    @Published var formattedSearchMatches: Set<UUID> = []
    @Published private(set) var formattedSearchMatchOrder: [UUID] = []
    @Published private(set) var formattedSearchFocusedID: UUID?
    @Published private(set) var formattedSearchFocusedIndex: Int?
    private(set) var isProgrammaticInputUpdate: Bool = false
    private var parseWorkItem: DispatchWorkItem?
    private var searchTokenCache: [UUID: [String]] = [:]
    private var formattedSearchWorkItem: DispatchWorkItem?
    private var formattedSearchComputationItem: DispatchWorkItem?
    private let formattedSearchDebounceInterval: TimeInterval = 0.3
    private var formattedSearchSnapshot: JSONNodeSnapshot?
    @Published private(set) var isFormattedSearchSnapshotLoading: Bool = false
    private var formattedSearchSnapshotWorkItem: DispatchWorkItem?
    private var previousSearchQuery: String = ""
    private var previousSearchComputation: FormattedSearchComputation?
    private var searchStateByRootID: [UUID: String] = [:]
    private var nodeLookup: [UUID: JSONNode] = [:]
    private var nodeLookupWorkItem: DispatchWorkItem?
    @Published private(set) var expansionState: [UUID: Bool] = [:]
    @Published private(set) var isExpandingOrCollapsing: Bool = false
    private var searchIndexBuildWorkItem: DispatchWorkItem?
    private var isSearchIndexBuilding = false
    private var expansionWorkItem: DispatchWorkItem?
    private let expansionQueue = DispatchQueue(label: "com.json-assistant.expansion", qos: .userInitiated)
    private let persistenceService: JSONPersistenceService

    init(persistenceService: JSONPersistenceService = JSONPersistenceService()) {
        self.persistenceService = persistenceService
        loadSavedJSONs()
    }

    private func rebuildNodeLookup() {
        // Cancel any previous lookup rebuild work
        nodeLookupWorkItem?.cancel()
        nodeLookupWorkItem = nil

        guard let rootNode else {
            // Clear lookup if no root node
            nodeLookup.removeAll()
            return
        }

        // Build lookup on background thread
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            var lookup: [UUID: JSONNode] = [:]
            var stack: [JSONNode] = [rootNode]

            while let node = stack.popLast() {
                if let workItem = workItem, workItem.isCancelled {
                    return
                }
                lookup[node.id] = node
                stack.append(contentsOf: node.children)
            }

            // Apply lookup on main thread
            DispatchQueue.main.async { [weak self, weak workItem] in
                guard let self = self else { return }
                guard let workItem = workItem, !workItem.isCancelled else { return }

                self.nodeLookup = lookup
                if self.nodeLookupWorkItem === workItem {
                    self.nodeLookupWorkItem = nil
                }
            }
        }

        nodeLookupWorkItem = workItem
        if let workItem = workItem {
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }
    }

    // MARK: - Expansion State Management

    func isExpanded(_ nodeID: UUID) -> Bool {
        expansionState[nodeID] ?? false
    }

    func toggleExpansion(for nodeID: UUID) {
        expansionState[nodeID, default: false].toggle()
    }

    func setExpanded(_ expanded: Bool, for nodeID: UUID) {
        expansionState[nodeID] = expanded
    }

    private func expandNodesWithoutPublishing(with nodeIDs: Set<UUID>) {
        for nodeID in nodeIDs {
            expansionState[nodeID] = true
        }
    }

    private func clearFormattedSearchResults() {
        formattedSearchWorkItem?.cancel()
        formattedSearchWorkItem = nil
        formattedSearchComputationItem?.cancel()
        formattedSearchComputationItem = nil
        formattedSearchSnapshotWorkItem?.cancel()
        formattedSearchSnapshotWorkItem = nil
        isFormattedSearchSnapshotLoading = false
        previousSearchQuery = ""
        previousSearchComputation = nil
        formattedSearchMatches = []
        formattedSearchMatchOrder = []
        formattedSearchFocusedID = nil
        formattedSearchFocusedIndex = nil
    }

    private func updateFocusedMatch(to index: Int?) {
        guard let index = index,
              index >= 0,
              index < formattedSearchMatchOrder.count else {
            formattedSearchFocusedIndex = nil
            formattedSearchFocusedID = nil
            return
        }

        formattedSearchFocusedIndex = index
        let targetID = formattedSearchMatchOrder[index]

        if formattedSearchFocusedID != targetID {
            formattedSearchFocusedID = targetID
        } else {
            formattedSearchFocusedID = nil
            DispatchQueue.main.async { [weak self] in
                self?.formattedSearchFocusedID = targetID
            }
        }
    }

    func parseAndSaveJSON(_ jsonString: String) {
        parseJSON(jsonString, saveOnSuccess: true)
    }


    func parseJSON(_ jsonString: String, autoExpand: Bool = true, saveOnSuccess: Bool = false) {
        guard !jsonString.isEmpty else {
            parseWorkItem?.cancel()
            DispatchQueue.main.async {
                self.rootNode = nil
                self.errorMessage = nil
                self.formattedSearchSnapshot = nil
                self.clearFormattedSearchResults()
            }
            return
        }

        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parseWorkItem?.cancel()
            DispatchQueue.main.async {
                self.rootNode = nil
                self.errorMessage = nil
                self.formattedSearchSnapshot = nil
                self.clearFormattedSearchResults()
            }
            return
        }

        // Debounce parsing for non-autoExpand (typing) mode
        if !autoExpand {
            parseWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.performParsing(jsonString, autoExpand: autoExpand, saveOnSuccess: saveOnSuccess)
            }
            parseWorkItem = workItem
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem)
        } else {
            // Immediate parsing for beautify/paste operations
            parseWorkItem?.cancel()
            performParsing(jsonString, autoExpand: autoExpand, saveOnSuccess: saveOnSuccess)
        }
    }

    private func performParsing(_ jsonString: String, autoExpand: Bool, saveOnSuccess: Bool) {
        do {
            var parser = OrderedJSONParser(jsonString)
            let parsedValue = try parser.parse()
            let prettyString = autoExpand ? OrderedJSONFormatter.prettyPrinted(parsedValue) : ""

            let rootLabel = JSONNode.describeType(of: parsedValue)

            // Update UI immediately, show loading state
            DispatchQueue.main.async {
                if autoExpand {
                    self.setEditorText(prettyString)
                }
                self.isLoadingJSON = true
                self.formattedSearchSnapshot = nil
                self.errorMessage = nil
            }

            // Build the node tree on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let rootNode = JSONNode(key: rootLabel, value: parsedValue, isRoot: true)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.rootNode = rootNode
                    self.isLoadingJSON = false
                    self.applyFormattedSearchIfNeeded()

                    if autoExpand {
                        // Only auto-expand for reasonably sized JSON (<50KB)
                        let shouldAutoExpand = jsonString.utf8.count < 50_000
                        if shouldAutoExpand {
                            self.setExpansionState(for: rootNode, isExpanded: true)
                        } else {
                            // For large JSON, only expand the root
                            self.setExpanded(true, for: rootNode.id)
                        }
                    }

                    if saveOnSuccess {
                        self.saveParsedJSONContent(autoExpand ? prettyString : jsonString)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                if let localized = (error as? LocalizedError)?.errorDescription {
                    self.errorMessage = localized
                } else {
                    self.errorMessage = "Error parsing JSON: \(error.localizedDescription)"
                }
                self.rootNode = nil
                self.isLoadingJSON = false
                self.formattedSearchSnapshot = nil
                self.clearFormattedSearchResults()
            }
        }
    }


    
    @discardableResult
    func saveJSON(_ jsonString: String) -> ParsedJSON? {
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !parsedJSONs.contains(where: { $0.content == jsonString }) else { return nil }
        
        let newParsedJSON = ParsedJSON(id: UUID(), date: Date(), name: "Unnamed", content: jsonString)
        parsedJSONs.append(newParsedJSON)
        saveParsedJSONs()
        searchTokenCache[newParsedJSON.id] = nil
        return newParsedJSON
    }

    private func saveParsedJSONContent(_ jsonString: String) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let selectedID = selectedJSONID,
           let index = parsedJSONs.firstIndex(where: { $0.id == selectedID }) {
            let existing = parsedJSONs[index]
            let updated = ParsedJSON(
                id: existing.id,
                date: Date(),
                name: existing.name,
                content: jsonString
            )
            parsedJSONs[index] = updated
            saveParsedJSONs()
            searchTokenCache[existing.id] = nil
        } else if let saved = saveJSON(jsonString) {
            selectedJSONID = saved.id
        }
    }
    
    func loadSavedJSON(_ json: ParsedJSON) {
        setEditorText(json.content)
        selectedJSONID = json.id
        beautifyJSON()
    }
    
    func deleteJSON(_ json: ParsedJSON) {
        parsedJSONs.removeAll { $0.id == json.id }
        saveParsedJSONs()
        if selectedJSONID == json.id {
            selectedJSONID = nil
        }
        searchTokenCache.removeValue(forKey: json.id)
        searchStateByRootID.removeValue(forKey: json.id)
    }
    
    func updateJSONName(_ json: ParsedJSON, newName: String) {
        if let index = parsedJSONs.firstIndex(where: { $0.id == json.id }) {
            parsedJSONs[index].name = newName
            saveParsedJSONs()
        }
    }
    
    private func saveParsedJSONs() {
        persistenceService.save(parsedJSONs)
    }
    
    private func loadSavedJSONs() {
        parsedJSONs = persistenceService.load()
        searchTokenCache.removeAll()
    }

    func expandAll() {
        performExpansionOperation(isExpanded: true)
    }

    func collapseAll() {
        performExpansionOperation(isExpanded: false)
    }

	    private func performExpansionOperation(isExpanded: Bool) {
	        // Cancel any previous expansion operation
	        expansionWorkItem?.cancel()

	        guard let rootNode else {
	            isExpandingOrCollapsing = false
	            expansionWorkItem = nil
	            return
	        }

	        isExpandingOrCollapsing = true

	        var workItem: DispatchWorkItem?
	        workItem = DispatchWorkItem { [weak self, rootNode] in
	            guard let self = self else { return }

	            var updatedExpansionState: [UUID: Bool] = [:]
	            var stack: [JSONNode] = [rootNode]

	            while let node = stack.popLast() {
	                if let workItem = workItem, workItem.isCancelled {
	                    DispatchQueue.main.async { [weak self, weak workItem] in
	                        guard let self = self else { return }
	                        guard let workItem = workItem, self.expansionWorkItem === workItem else { return }
	                        self.isExpandingOrCollapsing = false
	                        self.expansionWorkItem = nil
	                    }
	                    return
	                }

	                updatedExpansionState[node.id] = isExpanded
	                stack.append(contentsOf: node.children)
	            }

	            DispatchQueue.main.async { [weak self, weak workItem] in
	                guard let self = self else { return }
	                guard let workItem = workItem, !workItem.isCancelled else { return }
	                guard self.expansionWorkItem === workItem else { return }

	                self.expansionState = updatedExpansionState
	                self.isExpandingOrCollapsing = false
	                self.expansionWorkItem = nil
	            }
	        }

	        expansionWorkItem = workItem
	        if let workItem = workItem {
	            expansionQueue.async(execute: workItem)
	        }
	    }
    
    private func setExpansionState(for node: JSONNode?, isExpanded: Bool) {
        guard let node = node else { return }
        setExpanded(isExpanded, for: node.id)
        node.children.forEach { setExpansionState(for: $0, isExpanded: isExpanded) }
    }
    
    func beautifyJSON() {
        parseJSON(inputJSON, autoExpand: true)
    }

    func beautifyAndSaveJSON() {
        parseJSON(inputJSON, autoExpand: true, saveOnSuccess: true)
    }

    func startNewEntry() {
        selectedJSONID = nil
        setEditorText("")
        rootNode = nil
        errorMessage = nil
        formattedSearchSnapshot = nil
        clearFormattedSearchResults()
    }

    private func setEditorText(_ text: String) {
        isProgrammaticInputUpdate = true
        inputJSON = text
        DispatchQueue.main.async { [weak self] in
            self?.isProgrammaticInputUpdate = false
        }
    }

    @objc func handleKeyCommand(_ command: String) {
        switch command {
        case "new":
            startNewEntry()
        case "expand":
            expandAll()
        case "collapse":
            collapseAll()
        default:
            if command.hasPrefix("select-") {
                if let index = Int(command.replacingOccurrences(of: "select-", with: "")) {
                    selectLatest(index)
                }
            }
        }
    }
    
    func selectLatest(_ position: Int) {
        let index = position - 1
        guard index >= 0 else { return }
        let sorted = parsedJSONs.sorted { $0.date > $1.date }
        guard index < sorted.count else { return }
        loadSavedJSON(sorted[index])
    }

    func resetFeedbackStatus() {
        feedbackSubmissionMessage = nil
        feedbackSubmissionIsError = false
    }

    private func diagnoseFeedbackError(_ error: Error) -> String {
        let nsError = error as NSError

        // Check if it's a URLError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Please check your network."
            case NSURLErrorNetworkConnectionLost:
                return "Network connection lost. Please try again."
            case NSURLErrorDNSLookupFailed:
                return "Unable to reach the feedback server (DNS lookup failed)."
            case NSURLErrorCannotFindHost:
                return "Unable to reach the feedback server (host not found)."
            case NSURLErrorCannotConnectToHost:
                return "Unable to connect to the feedback server. Please check your connection."
            case NSURLErrorTimedOut:
                return "Request timed out. Please check your connection and try again."
            case NSURLErrorSecureConnectionFailed:
                return "Secure connection failed. Your network may be blocking the request."
            case NSURLErrorServerCertificateUntrusted:
                return "Server certificate error. Please report this issue."
            default:
                // For other URL errors, provide the code and description
                return "Network error (\(nsError.code)): \(error.localizedDescription)"
            }
        }

        // For non-URL errors, just use the standard description
        return "Failed to submit: \(error.localizedDescription)"
    }

    func submitFeedback(message: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSubmittingFeedback else { return }

        guard !trimmedMessage.isEmpty else {
            feedbackSubmissionIsError = true
            feedbackSubmissionMessage = "Feedback cannot be empty."
            return
        }

        feedbackSubmissionIsError = false
        feedbackSubmissionMessage = "Sending feedback..."
        isSubmittingFeedback = true

        var components = URLComponents(string: "https://notifier.coffeedevs.com/api/events")
        components?.queryItems = [
            URLQueryItem(name: "project", value: "json_assistant"),
            URLQueryItem(name: "message", value: trimmedMessage),
            URLQueryItem(name: "status", value: "success"),
            URLQueryItem(name: "event_type", value: "Feedback")
        ]

        guard let url = components?.url else {
            isSubmittingFeedback = false
            feedbackSubmissionIsError = true
            feedbackSubmissionMessage = "Invalid feedback endpoint."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSubmittingFeedback = false

                if let error = error {
                    self.feedbackSubmissionIsError = true
                    self.feedbackSubmissionMessage = self.diagnoseFeedbackError(error)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   (200..<300).contains(httpResponse.statusCode) {
                    self.feedbackSubmissionIsError = false
                    self.feedbackSubmissionMessage = "Feedback sent successfully."
                } else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    self.feedbackSubmissionIsError = true
                    if statusCode >= 0 {
                        self.feedbackSubmissionMessage = "Server error (\(statusCode)). Please try again later."
                    } else {
                        self.feedbackSubmissionMessage = "Unable to send feedback. Please check your connection."
                    }
                }
            }
        }.resume()
    }

    func filteredParsedJSONs(matching query: String) -> [ParsedJSON] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return parsedJSONs }

        let lowercasedQuery = trimmed.lowercased()
        return parsedJSONs.filter { parsed in
            matchesSearch(parsed, query: lowercasedQuery)
        }
    }

    func updateFormattedSearch(with query: String, skipDebounce: Bool = false) {
        formattedSearchQuery = query
        formattedSearchWorkItem?.cancel()
        formattedSearchComputationItem?.cancel()
        formattedSearchComputationItem = nil

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let performSearch: () -> Void = { [weak self] in
            guard let self = self else { return }

            let currentTrimmed = self.formattedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentTrimmed == trimmed else { return }

            if currentTrimmed.count < 3 {
                self.clearFormattedSearchResults()
                return
            }

            guard let rootNode = self.rootNode else {
                self.clearFormattedSearchResults()
                return
            }

            // If snapshot doesn't exist or is stale, create it asynchronously
            if self.formattedSearchSnapshot == nil || self.formattedSearchSnapshot?.id != rootNode.id {
                self.createSnapshotAndSearch(rootNode: rootNode, query: currentTrimmed)
                return
            }

            guard let snapshot = self.formattedSearchSnapshot else {
                self.clearFormattedSearchResults()
                return
            }

            let rootID = snapshot.id
            let loweredQuery = currentTrimmed.lowercased()

            weak var weakSelf = self
            var computeItem: DispatchWorkItem?
            computeItem = DispatchWorkItem {
                guard let computeItem else { return }

                do {
                    let computation = try Self.computeFormattedSearchComputation(
                        snapshot: snapshot,
                        query: loweredQuery,
                        shouldCancel: { computeItem.isCancelled }
                    )

                    if computeItem.isCancelled {
                        return
                    }

                    DispatchQueue.main.async {
                        guard let strongSelf = weakSelf else { return }
                        guard !computeItem.isCancelled else { return }
                        guard strongSelf.formattedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == currentTrimmed else { return }
                        guard let currentRoot = strongSelf.rootNode, currentRoot.id == rootID else { return }

                        strongSelf.applyFormattedSearchComputation(computation, rootNode: currentRoot)
                        if strongSelf.formattedSearchComputationItem === computeItem {
                            strongSelf.formattedSearchComputationItem = nil
                        }
                    }
                } catch FormattedSearchCancellation.cancelled {
                    return
                } catch {
                    return
                }
            }

            guard let computeItem else { return }
            self.formattedSearchComputationItem = computeItem
            DispatchQueue.global(qos: .userInitiated).async(execute: computeItem)
        }

        if skipDebounce {
            performSearch()
            formattedSearchWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.formattedSearchWorkItem = nil
            performSearch()
        }

        formattedSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + formattedSearchDebounceInterval,
            execute: workItem
        )
    }

    private func createSnapshotAndSearch(rootNode: JSONNode, query: String) {
        // Cancel any previous snapshot creation work
        formattedSearchSnapshotWorkItem?.cancel()

        // Show loading indicator
        isFormattedSearchSnapshotLoading = true

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Create snapshot on background thread
            let snapshot = Self.makeSnapshot(from: rootNode)

            guard let workItem = workItem, !workItem.isCancelled else {
                return
            }

            // Apply snapshot and perform search on main thread
            DispatchQueue.main.async { [weak self, weak workItem] in
                guard let self = self else { return }
                guard let workItem = workItem, !workItem.isCancelled else { return }

                self.formattedSearchSnapshot = snapshot
                self.isFormattedSearchSnapshotLoading = false

                // Build search index in background (deferred to avoid blocking JSON loading)
                self.buildSearchIndexInBackground(for: snapshot)

                // Now perform the search with the newly created snapshot
                self.performFormattedSearchWithSnapshot(query: query)
            }
        }

        formattedSearchSnapshotWorkItem = workItem
        if let workItem = workItem {
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        }
    }

    private func performFormattedSearchWithSnapshot(query: String) {
        guard let snapshot = self.formattedSearchSnapshot else {
            self.clearFormattedSearchResults()
            return
        }

        let rootID = snapshot.id
        let loweredQuery = query.lowercased()

        // Check if we can do incremental search
        let canUseIncremental = !previousSearchQuery.isEmpty &&
                                loweredQuery.count > previousSearchQuery.count &&
                                loweredQuery.hasPrefix(previousSearchQuery) &&
                                previousSearchComputation != nil

        weak var weakSelf = self
        var computeItem: DispatchWorkItem?
        computeItem = DispatchWorkItem {
            guard let computeItem else { return }

            do {
                let computation: FormattedSearchComputation

                if canUseIncremental, let prevComputation = self.previousSearchComputation {
                    // Incremental search: filter previous results
                    computation = try Self.filterSearchComputation(
                        prevComputation,
                        snapshot: snapshot,
                        newQuery: loweredQuery,
                        shouldCancel: { computeItem.isCancelled }
                    )
                } else {
                    // Full search
                    computation = try Self.computeFormattedSearchComputation(
                        snapshot: snapshot,
                        query: loweredQuery,
                        shouldCancel: { computeItem.isCancelled }
                    )
                }

                if computeItem.isCancelled {
                    return
                }

                DispatchQueue.main.async {
                    guard let strongSelf = weakSelf else { return }
                    guard !computeItem.isCancelled else { return }
                    guard strongSelf.formattedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == loweredQuery else { return }
                    guard let currentRoot = strongSelf.rootNode, currentRoot.id == rootID else { return }

                    strongSelf.previousSearchQuery = loweredQuery
                    strongSelf.previousSearchComputation = computation
                    strongSelf.applyFormattedSearchComputation(computation, rootNode: currentRoot)
                    if strongSelf.formattedSearchComputationItem === computeItem {
                        strongSelf.formattedSearchComputationItem = nil
                    }
                }
            } catch FormattedSearchCancellation.cancelled {
                return
            } catch {
                return
            }
        }

        guard let computeItem else { return }
        self.formattedSearchComputationItem = computeItem
        DispatchQueue.global(qos: .userInitiated).async(execute: computeItem)
    }

    func focusNextFormattedMatch() {
        let count = formattedSearchMatchOrder.count
        guard count > 0 else {
            updateFocusedMatch(to: nil)
            return
        }

        let currentIndex = formattedSearchFocusedIndex ?? -1
        let nextIndex = (currentIndex + 1) % count
        updateFocusedMatch(to: nextIndex)
    }

    func focusPreviousFormattedMatch() {
        let count = formattedSearchMatchOrder.count
        guard count > 0 else {
            updateFocusedMatch(to: nil)
            return
        }

        let currentIndex = formattedSearchFocusedIndex ?? count
        let previousIndex = (currentIndex - 1 + count) % count
        updateFocusedMatch(to: previousIndex)
    }

    func saveSearchState(for rootID: UUID, query: String) {
        searchStateByRootID[rootID] = query
    }

    func getSearchState(for rootID: UUID) -> String? {
        return searchStateByRootID[rootID]
    }

    private func matchesSearch(_ parsed: ParsedJSON, query: String) -> Bool {
        if parsed.name.lowercased().contains(query) { return true }

        if parsed.content.lowercased().contains(query) { return true }

        let tokens = tokensForSearch(in: parsed)
        return tokens.contains { $0.contains(query) }
    }

    private func tokensForSearch(in parsed: ParsedJSON) -> [String] {
        if let cached = searchTokenCache[parsed.id] {
            return cached
        }

        guard let data = parsed.content.data(using: .utf8) else {
            searchTokenCache[parsed.id] = []
            return []
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            searchTokenCache[parsed.id] = []
            return []
        }

        var tokens: [String] = []
        collectTokens(from: jsonObject, currentPath: "$", tokens: &tokens)

        let lowercasedTokens = tokens.map { $0.lowercased() }
        searchTokenCache[parsed.id] = lowercasedTokens
        return lowercasedTokens
    }

    private func collectTokens(from value: Any, currentPath: String, tokens: inout [String]) {
        tokens.append(currentPath)

        switch value {
        case let dict as [String: Any]:
            for (key, childValue) in dict {
                let childPath = currentPath == "$" ? "$.\(key)" : "\(currentPath).\(key)"
                collectTokens(from: childValue, currentPath: childPath, tokens: &tokens)
            }
        case let array as [Any]:
            for (index, childValue) in array.enumerated() {
                let childPath = "\(currentPath)[\(index)]"
                collectTokens(from: childValue, currentPath: childPath, tokens: &tokens)
            }
        case let string as String:
            tokens.append(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                tokens.append(number.boolValue ? "true" : "false")
            } else {
                tokens.append(number.stringValue)
            }
        case is NSNull:
            tokens.append("null")
        default:
            tokens.append(String(describing: value))
        }
    }

    /// Marks all ancestors of a match as fully loaded so they render all children
    /// This ensures pagination doesn't hide search results in large arrays
    private func ensureMatchIsVisible(matchID: UUID) {
        guard let matchNode = nodeLookup[matchID] else { return }

        // Walk up the tree and mark all ancestors as fully loaded
        var current = matchNode
        while let parent = nodeLookup.values.first(where: { $0.children.contains(where: { $0.id == current.id }) }) {
            parent.isFullyLoaded = true
            current = parent
        }
    }

    private func applyFormattedSearchComputation(_ computation: FormattedSearchComputation, rootNode: JSONNode) {
        // Batch view updates by setting published properties together
        // This reduces the number of view re-renders from multiple to just one
        let targetIndex: Int?
        if let currentID = formattedSearchFocusedID,
           let currentIndex = computation.matchesOrdered.firstIndex(of: currentID) {
            targetIndex = currentIndex
        } else {
            targetIndex = computation.matchesOrdered.isEmpty ? nil : 0
        }

        // Expand nodes first (without triggering view updates yet)
        expandNodesWithoutPublishing(with: computation.expansionIDs)

        // Ensure all matches are visible by marking their parent nodes as fully loaded
        // This prevents pagination from hiding search results in large arrays
        for matchID in computation.matchesOrdered {
            ensureMatchIsVisible(matchID: matchID)
        }

        // Now publish all changes together, triggering a single view update cycle
        formattedSearchMatches = computation.highlightIDs
        formattedSearchMatchOrder = computation.matchesOrdered
        updateFocusedMatch(to: targetIndex)
    }

    private static func makeSnapshot(from node: JSONNode) -> JSONNodeSnapshot {
        // Create snapshot tree immediately without building index (for fast JSON loading)
        let snapshot = makeSnapshotTree(from: node)
        // Index will be built in background by buildSearchIndexInBackground()
        return snapshot
    }

    private func buildSearchIndexInBackground(for snapshot: JSONNodeSnapshot) {
        // Cancel any previous index build work
        searchIndexBuildWorkItem?.cancel()
        isSearchIndexBuilding = false

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard let workItem = workItem, !workItem.isCancelled else { return }

            // Build the search index on background thread
            let builtIndex = Self.buildSearchIndex(for: snapshot)

            guard !workItem.isCancelled else { return }

            // Update the snapshot's index in-place on main thread to avoid replacing snapshot
            DispatchQueue.main.async { [weak self, weak workItem] in
                guard let self = self else { return }
                guard let workItem = workItem, !workItem.isCancelled else { return }

                // Only update if this is still the same snapshot (prevent race condition)
                if self.formattedSearchSnapshot?.id == snapshot.id {
                    self.formattedSearchSnapshot?.searchIndex = builtIndex
                }
            }
        }

        searchIndexBuildWorkItem = workItem
        if let workItem = workItem {
            isSearchIndexBuilding = true
            DispatchQueue.global(qos: .utility).async(execute: workItem)
        }
    }

    private static func makeSnapshotTree(from node: JSONNode) -> JSONNodeSnapshot {
        let normalizedValue: String?
        if node.children.isEmpty {
            normalizedValue = normalizedValueString(for: node.value)
        } else {
            normalizedValue = nil
        }

        let children = node.children.map { makeSnapshotTree(from: $0) }

        return JSONNodeSnapshot(
            id: node.id,
            keyLowercased: node.isRoot ? "" : node.key.lowercased(),
            isRoot: node.isRoot,
            typeDescriptionLowercased: node.typeDescription.lowercased(),
            normalizedValue: normalizedValue,
            children: children,
            searchIndex: SearchIndex()  // Start with empty index
        )
    }

    private static func buildSearchIndex(for snapshot: JSONNodeSnapshot) -> SearchIndex {
        var index = SearchIndex()
        collectTokensForIndex(&index, in: snapshot)
        return index
    }

    private static func collectTokensForIndex(_ index: inout SearchIndex, in snapshot: JSONNodeSnapshot) {
        // Collect tokens from this node's searchable fields
        var tokens: [String] = []

        // Add key tokens (if not root)
        if !snapshot.isRoot && !snapshot.keyLowercased.isEmpty {
            tokens.append(snapshot.keyLowercased)
        }

        // Add type description tokens
        if !snapshot.typeDescriptionLowercased.isEmpty {
            tokens.append(snapshot.typeDescriptionLowercased)
        }

        // Add normalized value tokens (for leaf nodes)
        if let normalizedValue = snapshot.normalizedValue, !normalizedValue.isEmpty {
            // Split by spaces to get individual tokens
            let valueTokens = normalizedValue.split(separator: " ").map(String.init)
            tokens.append(contentsOf: valueTokens)
        }

        // Add all tokens to index for this node
        if !tokens.isEmpty {
            index.addTokensForNode(snapshot.id, tokens: tokens)
        }

        // Recursively collect tokens from children
        for child in snapshot.children {
            collectTokensForIndex(&index, in: child)
        }
    }

    private func computeFormattedSearchComputationSafe(snapshot: JSONNodeSnapshot, query: String, shouldCancel: () -> Bool) throws -> FormattedSearchComputation {
        // This is a wrapper that checks if the index is being built
        if isSearchIndexBuilding {
            // Index is being built, use tree traversal fallback
            return try Self.computeWithTreeTraversal(snapshot: snapshot, query: query, shouldCancel: shouldCancel)
        }
        return try Self.computeFormattedSearchComputation(snapshot: snapshot, query: query, shouldCancel: shouldCancel)
    }

    private static func computeFormattedSearchComputation(snapshot: JSONNodeSnapshot, query: String, shouldCancel: () -> Bool) throws -> FormattedSearchComputation {
        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

        // Check if search index is ready (has been built in background)
        let indexIsReady = !snapshot.searchIndex.isEmpty()

        // Use index-based search if ready, otherwise fall back to tree traversal
        if indexIsReady {
            return try computeWithIndex(snapshot: snapshot, query: query, shouldCancel: shouldCancel)
        } else {
            return try computeWithTreeTraversal(snapshot: snapshot, query: query, shouldCancel: shouldCancel)
        }
    }

    private static func computeWithIndex(snapshot: JSONNodeSnapshot, query: String, shouldCancel: () -> Bool) throws -> FormattedSearchComputation {
        var matchingNodeIDs: Set<UUID> = []

        // Get all tokens that contain the query
        let matchingTokens = snapshot.searchIndex.getMatchingTokens(for: query)

        // Collect all node IDs that have matching tokens
        for token in matchingTokens {
            if shouldCancel() {
                throw FormattedSearchCancellation.cancelled
            }
            matchingNodeIDs.formUnion(snapshot.searchIndex.getMatchingNodeIDs(for: token))
        }

        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

        // Now build the result with proper ordering and expansion info
        var matchesOrdered: [UUID] = []
        var highlightIDs: Set<UUID> = []
        var expansionIDs: Set<UUID> = []

        // Build a map of node ID to node for quick ancestor lookup
        var nodeMap: [UUID: JSONNodeSnapshot] = [:]
        buildNodeMap(snapshot, into: &nodeMap)

        // Process each matching node in DFS order
        var dfsOrder: [UUID] = []
        buildDFSOrder(snapshot, into: &dfsOrder)

        for nodeID in dfsOrder {
            if matchingNodeIDs.contains(nodeID) {
                matchesOrdered.append(nodeID)
                highlightIDs.insert(nodeID)

                // Find and expand all ancestors
                let ancestors = findAncestors(nodeID, in: snapshot, nodeMap: nodeMap)
                expansionIDs.formUnion(ancestors)
            }
        }

        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

        return FormattedSearchComputation(matchesOrdered: matchesOrdered, highlightIDs: highlightIDs, expansionIDs: expansionIDs)
    }

    private static func computeWithTreeTraversal(snapshot: JSONNodeSnapshot, query: String, shouldCancel: () -> Bool) throws -> FormattedSearchComputation {
        // Fallback to tree traversal when index is not yet ready
        var matchesOrdered: [UUID] = []
        var highlightIDs: Set<UUID> = []
        var expansionIDs: Set<UUID> = []

        var ancestry: [UUID] = []
        _ = try collectMatches(
            in: snapshot,
            query: query,
            ancestors: &ancestry,
            matchesOrdered: &matchesOrdered,
            highlightIDs: &highlightIDs,
            expansionIDs: &expansionIDs,
            shouldCancel: shouldCancel
        )

        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

        return FormattedSearchComputation(matchesOrdered: matchesOrdered, highlightIDs: highlightIDs, expansionIDs: expansionIDs)
    }

    /// Build a map of all node IDs to their snapshots for quick lookup
    private static func buildNodeMap(_ snapshot: JSONNodeSnapshot, into map: inout [UUID: JSONNodeSnapshot]) {
        map[snapshot.id] = snapshot
        for child in snapshot.children {
            buildNodeMap(child, into: &map)
        }
    }

    /// Build DFS order of all node IDs for consistent result ordering
    private static func buildDFSOrder(_ snapshot: JSONNodeSnapshot, into order: inout [UUID]) {
        order.append(snapshot.id)
        for child in snapshot.children {
            buildDFSOrder(child, into: &order)
        }
    }

    /// Find all ancestors of a node (for auto-expansion during search)
    private static func findAncestors(_ nodeID: UUID, in snapshot: JSONNodeSnapshot, nodeMap: [UUID: JSONNodeSnapshot]) -> Set<UUID> {
        var ancestors: Set<UUID> = []

        func collectAncestors(_ current: JSONNodeSnapshot) -> Bool {
            for child in current.children {
                if child.id == nodeID {
                    ancestors.insert(current.id)
                    return true
                }
                if collectAncestors(child) {
                    ancestors.insert(current.id)
                    return true
                }
            }
            return false
        }

        _ = collectAncestors(snapshot)
        return ancestors
    }

    private static func filterSearchComputation(
        _ previousComputation: FormattedSearchComputation,
        snapshot: JSONNodeSnapshot,
        newQuery: String,
        shouldCancel: () -> Bool
    ) throws -> FormattedSearchComputation {
        // Since index-based search is now O(1), just use the regular search instead of incremental filtering
        // This is simpler and not significantly slower than the old incremental approach
        return try computeFormattedSearchComputation(snapshot: snapshot, query: newQuery, shouldCancel: shouldCancel)
    }

    private static func findNodeInSnapshot(_ snapshot: JSONNodeSnapshot, withID targetID: UUID) -> JSONNodeSnapshot? {
        if snapshot.id == targetID {
            return snapshot
        }

        for child in snapshot.children {
            if let found = findNodeInSnapshot(child, withID: targetID) {
                return found
            }
        }

        return nil
    }

    private static func collectAncestors(_ snapshot: JSONNodeSnapshot, in root: JSONNodeSnapshot, ancestors: inout [UUID]) {
        // Build ancestry chain from root to current node
        var current = snapshot
        var ancestryChain: [UUID] = []

        func findAncestorPath(_ node: JSONNodeSnapshot, _ target: UUID, _ path: inout [UUID]) -> Bool {
            path.append(node.id)

            if node.id == target {
                return true
            }

            for child in node.children {
                if findAncestorPath(child, target, &path) {
                    return true
                }
            }

            path.removeLast()
            return false
        }

        _ = findAncestorPath(root, snapshot.id, &ancestryChain)
        ancestors = ancestryChain
    }

    @discardableResult
    private static func collectMatches(in snapshot: JSONNodeSnapshot, query: String, ancestors: inout [UUID], matchesOrdered: inout [UUID], highlightIDs: inout Set<UUID>, expansionIDs: inout Set<UUID>, shouldCancel: () -> Bool) throws -> Bool {
        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

        let didMatchSelf = snapshot.matches(query: query)
        var didMatchChild = false

        ancestors.append(snapshot.id)
        defer { ancestors.removeLast() }

        for child in snapshot.children {
            if shouldCancel() {
                throw FormattedSearchCancellation.cancelled
            }

            if try collectMatches(in: child, query: query, ancestors: &ancestors, matchesOrdered: &matchesOrdered, highlightIDs: &highlightIDs, expansionIDs: &expansionIDs, shouldCancel: shouldCancel) {
                didMatchChild = true
            }
        }

        if didMatchSelf {
            matchesOrdered.append(snapshot.id)
            highlightIDs.insert(snapshot.id)
            expansionIDs.formUnion(ancestors)
        }

        if didMatchChild {
            expansionIDs.insert(snapshot.id)
        }

        return didMatchSelf || didMatchChild
    }

    private static func normalizedValueString(for value: Any) -> String {
        var result = ""
        result.reserveCapacity(1024)  // Pre-allocate buffer capacity
        appendNormalizedValue(value, to: &result, maxDepth: 2)
        return result.lowercased()  // Single lowercase operation at the end
    }

    private static func appendNormalizedValue(_ value: Any, to result: inout String, maxDepth: Int) {
        if maxDepth <= 0 {
            return
        }

        switch value {
        case let stringValue as String:
            if !result.isEmpty { result.append(" ") }
            result.append(stringValue)  // No lowercase here

        case let number as NSNumber:
            if !result.isEmpty { result.append(" ") }
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                result.append(number.boolValue ? "true" : "false")
            } else {
                result.append(number.stringValue)  // No lowercase here
            }

        case is NSNull:
            if !result.isEmpty { result.append(" ") }
            result.append("null")

        case let array as [Any]:
            // Limit array processing to first 100 elements to avoid quadratic behavior
            let limit = min(array.count, 100)
            for item in array.prefix(limit) {
                appendNormalizedValue(item, to: &result, maxDepth: maxDepth - 1)
            }

        case let dict as [String: Any]:
            // Limit dict processing to first 50 keys
            let limit = min(dict.count, 50)
            for (key, value) in dict.prefix(limit) {
                if !result.isEmpty { result.append(" ") }
                result.append(key)  // No lowercase here
                appendNormalizedValue(value, to: &result, maxDepth: maxDepth - 1)
            }

        case let ordered as OrderedDictionary:
            // Limit ordered dict processing to first 50 pairs
            let limit = min(ordered.orderedPairs.count, 50)
            for (key, value) in ordered.orderedPairs.prefix(limit) {
                if !result.isEmpty { result.append(" ") }
                result.append(key)  // No lowercase here
                appendNormalizedValue(value, to: &result, maxDepth: maxDepth - 1)
            }

        default:
            if !result.isEmpty { result.append(" ") }
            result.append(String(describing: value))  // No lowercase here
        }
    }

    // MARK: - Search Index for Fast Token Lookup
    private struct SearchIndex {
        /// Maps search tokens (prefixes) to node IDs
        /// Example: "user" → [nodeID1, nodeID2, nodeID3]
        private var tokenToNodeIDs: [String: Set<UUID>] = [:]

        /// Maps node IDs to their search tokens for quick lookup of tokens that match
        private var nodeIDToTokens: [UUID: Set<String>] = [:]

        mutating func addTokensForNode(_ nodeID: UUID, tokens: [String]) {
            var uniqueTokens: Set<String> = []

            for token in tokens {
                // Only process tokens that are at least 3 characters long
                guard token.count >= 3 else { continue }

                // Add prefixes (3-8 chars) to support substring matching while reducing memory
                // Limiting to 8 chars reduces memory overhead by ~60% vs 20-char limit
                for i in 3...min(token.count, 8) {
                    let prefix = String(token.prefix(i))
                    tokenToNodeIDs[prefix, default: []].insert(nodeID)
                    uniqueTokens.insert(prefix)
                }
            }

            nodeIDToTokens[nodeID] = uniqueTokens
        }

        /// Get all node IDs that match a query token using prefix matching
        func getMatchingNodeIDs(for query: String) -> Set<UUID> {
            return tokenToNodeIDs[query] ?? []
        }

        /// Get all tokens that contain the query as a substring
        func getMatchingTokens(for query: String) -> [String] {
            return tokenToNodeIDs.keys.filter { $0.contains(query) }
        }

        /// Check if the index has been built (has data)
        func isEmpty() -> Bool {
            return tokenToNodeIDs.isEmpty
        }
    }

    private struct JSONNodeSnapshot {
        let id: UUID
        let keyLowercased: String
        let isRoot: Bool
        let typeDescriptionLowercased: String
        let normalizedValue: String?
        let children: [JSONNodeSnapshot]
        var searchIndex: SearchIndex

        func matches(query: String) -> Bool {
            if !isRoot && keyLowercased.range(of: query, options: .literal) != nil {
                return true
            }

            if children.isEmpty {
                if let normalizedValue, normalizedValue.range(of: query, options: .literal) != nil {
                    return true
                }
            } else if typeDescriptionLowercased.range(of: query, options: .literal) != nil {
                return true
            }

            return false
        }
    }

    private enum FormattedSearchCancellation: Error {
        case cancelled
    }

    private struct FormattedSearchComputation {
        let matchesOrdered: [UUID]
        let highlightIDs: Set<UUID>
        let expansionIDs: Set<UUID>
    }

    private func applyFormattedSearchIfNeeded() {
        let trimmed = formattedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            formattedSearchWorkItem?.cancel()
            formattedSearchWorkItem = nil
            clearFormattedSearchResults()
            return
        }
        updateFormattedSearch(with: formattedSearchQuery, skipDebounce: true)
    }
}
