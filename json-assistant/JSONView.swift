import SwiftUI
import Foundation

class OrderedDictionary {
    private var keys: [String] = []
    private var dict: [String: Any] = [:]
    
    subscript(key: String) -> Any? {
        get { return dict[key] }
        set {
            if newValue == nil {
                dict.removeValue(forKey: key)
                keys.removeAll { $0 == key }
            } else {
                if dict[key] == nil {
                    keys.append(key)
                }
                dict[key] = newValue
            }
        }
    }
    
    var orderedPairs: [(String, Any)] {
        return keys.map { ($0, dict[$0]!) }
    }
}

enum OrderedJSONParserError: LocalizedError {
    case unexpectedCharacter(Character, Int)
    case unexpectedEndOfInput
    case invalidLiteral(String, Int)
    case invalidNumber(String, Int)
    
    var errorDescription: String? {
        switch self {
        case .unexpectedCharacter(let character, let position):
            return "Unexpected character '\(character)' at position \(position)."
        case .unexpectedEndOfInput:
            return "Unexpected end of JSON input."
        case .invalidLiteral(let literal, let position):
            return "Invalid literal '\(literal)' at position \(position)."
        case .invalidNumber(let literal, let position):
            return "Invalid number '\(literal)' at position \(position)."
        }
    }
}

struct OrderedJSONParser {
    private let input: String
    private var index: String.Index
    
    init(_ input: String) {
        self.input = input
        self.index = input.startIndex
    }
    
    mutating func parse() throws -> Any {
        skipWhitespace()
        guard !isAtEnd else {
            throw OrderedJSONParserError.unexpectedEndOfInput
        }
        
        let value = try parseValue()
        skipWhitespace()
        if !isAtEnd {
            let character = currentCharacter ?? Character(" ")
            throw OrderedJSONParserError.unexpectedCharacter(character, position)
        }
        return value
    }
    
    private mutating func parseValue() throws -> Any {
        skipWhitespace()
        guard let character = currentCharacter else {
            throw OrderedJSONParserError.unexpectedEndOfInput
        }
        
        switch character {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return try parseString()
        case "-", "0"..."9": return try parseNumber()
        case "t", "f", "n": return try parseLiteral()
        default:
            throw OrderedJSONParserError.unexpectedCharacter(character, position)
        }
    }
    
    private mutating func parseObject() throws -> OrderedDictionary {
        try expect("{")
        skipWhitespace()
        
        let dictionary = OrderedDictionary()
        if match("}") {
            return dictionary
        }
        
        repeat {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(":")
            let value = try parseValue()
            dictionary[key] = value
            skipWhitespace()
        } while match(",")
        
        try expect("}")
        return dictionary
    }
    
    private mutating func parseArray() throws -> [Any] {
        try expect("[")
        skipWhitespace()
        
        var array: [Any] = []
        if match("]") {
            return array
        }
        
        repeat {
            let value = try parseValue()
            array.append(value)
            skipWhitespace()
        } while match(",")
        
        try expect("]")
        return array
    }
    
    private mutating func parseString() throws -> String {
        try expect("\"")
        var result = ""
        
        while !isAtEnd {
            guard let character = currentCharacter else {
                throw OrderedJSONParserError.unexpectedEndOfInput
            }
            
            if character == "\"" {
                advance()
                return result
            }
            
            if character == "\\" {
                advance()
                guard let escaped = currentCharacter else {
                    throw OrderedJSONParserError.unexpectedEndOfInput
                }
                
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    let scalar = try parseUnicodeScalar()
                    result.append(Character(scalar))
                    continue
                default:
                    throw OrderedJSONParserError.invalidLiteral("\\\(escaped)", position)
                }
                advance()
                continue
            }
            
            result.append(character)
            advance()
        }
        
        throw OrderedJSONParserError.unexpectedEndOfInput
    }
    
    private mutating func parseUnicodeScalar() throws -> UnicodeScalar {
        advance() // move past 'u'
        var hex = ""
        for _ in 0..<4 {
            guard let character = currentCharacter else {
                throw OrderedJSONParserError.unexpectedEndOfInput
            }
            guard character.isHexDigit else {
                throw OrderedJSONParserError.invalidLiteral(String(character), position)
            }
            hex.append(character)
            advance()
        }
        
        guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else {
            throw OrderedJSONParserError.invalidLiteral("\\u\(hex)", position)
        }
        return scalar
    }
    
    private mutating func parseLiteral() throws -> Any {
        if match(string: "true") {
            return NSNumber(value: true)
        }
        if match(string: "false") {
            return NSNumber(value: false)
        }
        if match(string: "null") {
            return NSNull()
        }
        let character = currentCharacter ?? Character(" ")
        throw OrderedJSONParserError.invalidLiteral(String(character), position)
    }
    
    private mutating func parseNumber() throws -> Any {
        let start = index
        var tempIndex = index
        let allowedCharacters = CharacterSet(charactersIn: "-+0123456789.eE")
        
        while tempIndex < input.endIndex,
              let scalar = input[tempIndex].unicodeScalars.first,
              allowedCharacters.contains(scalar) {
            tempIndex = input.index(after: tempIndex)
        }
        
        let numberString = String(input[start..<tempIndex])
        guard !numberString.isEmpty else {
            throw OrderedJSONParserError.invalidNumber(numberString, position)
        }
        
        let wrapped = "[\(numberString)]"
        guard
            let data = wrapped.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any],
            let value = parsed.first
        else {
            throw OrderedJSONParserError.invalidNumber(numberString, position)
        }
        
        index = tempIndex
        return value
    }
    
    private mutating func expect(_ character: Character) throws {
        guard currentCharacter == character else {
            let found = currentCharacter ?? Character(" ")
            throw OrderedJSONParserError.unexpectedCharacter(found, position)
        }
        advance()
    }
    
    private mutating func match(_ character: Character) -> Bool {
        if currentCharacter == character {
            advance()
            return true
        }
        return false
    }
    
    private mutating func match(string: String) -> Bool {
        var tempIndex = index
        for character in string {
            if tempIndex == input.endIndex || input[tempIndex] != character {
                return false
            }
            tempIndex = input.index(after: tempIndex)
        }
        index = tempIndex
        return true
    }
    
    private mutating func advance() {
        if !isAtEnd {
            index = input.index(after: index)
        }
    }
    
    private mutating func skipWhitespace() {
        while let character = currentCharacter, character.isWhitespace {
            advance()
        }
    }
    
    private var currentCharacter: Character? {
        guard !isAtEnd else { return nil }
        return input[index]
    }
    
    private var position: Int {
        input.distance(from: input.startIndex, to: index) + 1
    }
    
    private var isAtEnd: Bool {
        index >= input.endIndex
    }
}

enum OrderedJSONFormatter {
    static func prettyPrinted(_ value: Any, indent: Int = 0) -> String {
        return format(value, indentLevel: indent)
    }
    
    private static func format(_ value: Any, indentLevel: Int) -> String {
        let indentUnit = "    "
        let currentIndent = String(repeating: indentUnit, count: indentLevel)
        let nextIndentLevel = indentLevel + 1
        let nextIndent = String(repeating: indentUnit, count: nextIndentLevel)
        
        switch value {
        case let dictionary as OrderedDictionary:
            let pairs = dictionary.orderedPairs
            guard !pairs.isEmpty else { return "{}" }
            var lines = ["{"]
            for (index, pair) in pairs.enumerated() {
                let formattedValue = format(pair.1, indentLevel: nextIndentLevel)
                var line = "\(nextIndent)\"\(escape(pair.0))\": \(formattedValue)"
                if index < pairs.count - 1 {
                    line += ","
                }
                lines.append(line)
            }
            lines.append("\(currentIndent)}")
            return lines.joined(separator: "\n")
            
        case let array as [Any]:
            guard !array.isEmpty else { return "[]" }
            var lines = ["["]
            for (index, element) in array.enumerated() {
                var line = "\(nextIndent)\(format(element, indentLevel: nextIndentLevel))"
                if index < array.count - 1 {
                    line += ","
                }
                lines.append(line)
            }
            lines.append("\(currentIndent)]")
            return lines.joined(separator: "\n")
            
        case let string as String:
            return "\"\(escape(string))\""
            
        case let number as NSNumber:
            if number.isBool {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
            
        case _ as NSNull:
            return "null"
            
        case let bool as Bool:
            return bool ? "true" : "false"
            
        case let double as Double:
            return NSNumber(value: double).stringValue
            
        case let int as Int:
            return "\(int)"
            
        default:
            return "\"\(escape(String(describing: value)))\""
        }
    }
    
    private static func escape(_ string: String) -> String {
        var escaped = ""
        for character in string {
            switch character {
            case "\"": escaped.append("\\\"")
            case "\\": escaped.append("\\\\")
            case "\u{08}": escaped.append("\\b")
            case "\u{0C}": escaped.append("\\f")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default:
                if character.unicodeScalars.allSatisfy({ $0.value < 0x20 }) {
                    for scalar in character.unicodeScalars {
                        let value = String(format: "%04X", scalar.value)
                        escaped.append("\\u\(value)")
                    }
                } else {
                    escaped.append(character)
                }
            }
        }
        return escaped
    }
}

class JSONNode: Identifiable, ObservableObject {
    let id = UUID()
    let key: String
    let isRoot: Bool
    @Published var value: Any
    @Published var isExpanded: Bool = false
    @Published var children: [JSONNode] = []
    
    init(key: String, value: Any, isRoot: Bool = false) {
        self.key = key
        self.isRoot = isRoot
        self.value = value
        parseValue(value)
    }
    
    private func parseValue(_ value: Any) {
        switch value {
        case let dict as OrderedDictionary:
            children = dict.orderedPairs.map { JSONNode(key: $0.0, value: $0.1) }
        case let dict as [String: Any]:
            let ordered = OrderedDictionary()
            for (key, value) in dict {
                ordered[key] = value
            }
            children = ordered.orderedPairs.map { JSONNode(key: $0.0, value: $0.1) }
        case let array as [Any]:
            children = array.enumerated().map { JSONNode(key: "[\($0)]", value: $1) }
        default:
            break
        }
    }
    
    var displayValue: String {
        if !children.isEmpty { return "" }
        switch value {
        case is OrderedDictionary, is [String: Any]:
            return "Object"
        case is [Any]:
            return "Array"
        case let stringValue as String: return "\"\(stringValue)\""
        case is NSNull: return "null"
        case let number as NSNumber:
            return number.isBool ? (number.boolValue ? "true" : "false") : number.stringValue
        default: return "\(value)"
        }
    }
    
    var typeDescription: String {
        return JSONNode.describeType(of: value)
    }
    
    static func describeType(of value: Any) -> String {
        switch value {
        case is OrderedDictionary, is [String: Any]:
            return "Object"
        case is [Any]:
            return "Array"
        case let number as NSNumber:
            return number.isBool ? "Boolean" : "Number"
        case is String:
            return "String"
        case is NSNull:
            return "Null"
        case is Bool:
            return "Boolean"
        default:
            return String(describing: type(of: value))
        }
    }
}

extension NSNumber {
    fileprivate var isBool: Bool {
        let boolID = CFBooleanGetTypeID()
        return CFGetTypeID(self) == boolID
    }
}

enum ValueType {
    case string, number, bool, null, complex, other
}

struct CollapsibleJSONView: View {
    @ObservedObject var node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    let depth: Int

    init(node: JSONNode, viewModel: JSONViewModel, palette: ThemePalette, depth: Int = 0) {
        self.node = node
        self.viewModel = viewModel
        self.palette = palette
        self.depth = depth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JSONNodeView(node: node, viewModel: viewModel, palette: palette)

            // Only render children when expanded, and limit depth to prevent excessive nesting
            if node.isExpanded && !node.children.isEmpty && depth < 50 {
                ForEach(node.children) { child in
                    CollapsibleJSONView(node: child, viewModel: viewModel, palette: palette, depth: depth + 1)
                        .padding(.leading, 16)
                        .id(child.id)
                }
            }
        }
        .id(node.id)
    }
}


struct JSONNodeView: View {
    @ObservedObject var node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    
    var body: some View {
        let isHighlighted = viewModel.formattedSearchMatches.contains(node.id)
        let isFocused = viewModel.formattedSearchFocusedID == node.id

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
            Image(systemName: node.isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
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
            } else {
                Text(node.key)
                    .foregroundColor(keyColor)
                    .fontWeight(keyWeight)
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
            
            Spacer(minLength: 0)
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
        } else if node.value is [Any] {
            Text("Array")
                .foregroundColor(palette.muted)
                .textSelection(.enabled)
        } else if let stringValue = node.value as? String {
            if let url = URL(string: stringValue),
               let scheme = url.scheme,
               ["http", "https"].contains(scheme.lowercased()) {
                Link(destination: url) {
                    Text(node.displayValue)
                        .foregroundColor(palette.accent)
                }
                .textSelection(.enabled)
            } else {
                Text(node.displayValue)
                    .foregroundColor(palette.string)
                    .textSelection(.enabled)
            }
        } else if let number = node.value as? NSNumber {
            if number.isBool {
                Text(node.displayValue)
                    .foregroundColor(number.boolValue ? palette.boolTrue : palette.boolFalse)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            } else {
                Text(node.displayValue)
                    .foregroundColor(palette.number)
                    .textSelection(.enabled)
            }
        } else if node.value is NSNull {
            Text(node.displayValue)
                .foregroundColor(palette.null)
                .italic()
                .textSelection(.enabled)
        } else {
            Text(node.displayValue)
                .foregroundColor(palette.number)
                .textSelection(.enabled)
        }
    }
}




@MainActor
class JSONViewModel: ObservableObject {
    @Published var inputJSON: String = ""
    @Published var rootNode: JSONNode? {
        didSet { rebuildNodeLookup() }
    }
    @Published var errorMessage: String?
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
    private var nodeLookup: [UUID: JSONNode] = [:]

    init() {
        loadSavedJSONs()
    }

    private func rebuildNodeLookup() {
        nodeLookup.removeAll()
        guard let rootNode else { return }

        var stack: [JSONNode] = [rootNode]
        while let node = stack.popLast() {
            nodeLookup[node.id] = node
            stack.append(contentsOf: node.children)
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
        parseJSON(jsonString)
        if errorMessage == nil && !jsonString.isEmpty {
            if let saved = saveJSON(jsonString) {
                selectedJSONID = saved.id
            }
        }
    }


    func parseJSON(_ jsonString: String, autoExpand: Bool = true) {
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
                self?.performParsing(jsonString, autoExpand: autoExpand)
            }
            parseWorkItem = workItem
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem)
        } else {
            // Immediate parsing for beautify/paste operations
            parseWorkItem?.cancel()
            performParsing(jsonString, autoExpand: autoExpand)
        }
    }

    private func performParsing(_ jsonString: String, autoExpand: Bool) {
        do {
            var parser = OrderedJSONParser(jsonString)
            let parsedValue = try parser.parse()
            let prettyString = autoExpand ? OrderedJSONFormatter.prettyPrinted(parsedValue) : ""

            let rootLabel = JSONNode.describeType(of: parsedValue)
            DispatchQueue.main.async {
                if autoExpand {
                    self.setEditorText(prettyString)
                }
                self.rootNode = JSONNode(key: rootLabel, value: parsedValue, isRoot: true)
                self.formattedSearchSnapshot = nil
                self.errorMessage = nil
                self.persistParsedJSONIfNeeded(originalJSON: jsonString, autoExpand: autoExpand)
                self.applyFormattedSearchIfNeeded()

                if autoExpand {
                    // Only auto-expand for reasonably sized JSON (<50KB)
                    let shouldAutoExpand = jsonString.utf8.count < 50_000
                    if shouldAutoExpand {
                        self.setExpansionState(for: self.rootNode, isExpanded: true)
                    } else {
                        // For large JSON, only expand the root
                        self.rootNode?.isExpanded = true
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

    private func persistParsedJSONIfNeeded(originalJSON: String, autoExpand: Bool) {
        guard !autoExpand else { return }
        let trimmed = originalJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let selectedID = selectedJSONID,
           let index = parsedJSONs.firstIndex(where: { $0.id == selectedID }) {
            let existing = parsedJSONs[index]
            let updated = ParsedJSON(
                id: existing.id,
                date: Date(),
                name: existing.name,
                content: originalJSON
            )
            parsedJSONs[index] = updated
            saveParsedJSONs()
            searchTokenCache[existing.id] = nil
        } else if let saved = saveJSON(originalJSON) {
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
    }
    
    func updateJSONName(_ json: ParsedJSON, newName: String) {
        if let index = parsedJSONs.firstIndex(where: { $0.id == json.id }) {
            parsedJSONs[index].name = newName
            saveParsedJSONs()
        }
    }
    
    private func saveParsedJSONs() {
        if let encoded = try? JSONEncoder().encode(parsedJSONs) {
            UserDefaults.standard.set(encoded, forKey: "SavedJSONs")
        }
    }
    
    private func loadSavedJSONs() {
        if let savedJSONs = UserDefaults.standard.data(forKey: "SavedJSONs") {
            if let decodedJSONs = try? JSONDecoder().decode([ParsedJSON].self, from: savedJSONs) {
                parsedJSONs = decodedJSONs
                searchTokenCache.removeAll()
            }
        }
    }

    func expandAll() {
        setExpansionState(for: rootNode, isExpanded: true)
    }
    
    func collapseAll() {
        setExpansionState(for: rootNode, isExpanded: false)
    }
    
    private func setExpansionState(for node: JSONNode?, isExpanded: Bool) {
        guard let node = node else { return }
        node.isExpanded = isExpanded
        node.children.forEach { setExpansionState(for: $0, isExpanded: isExpanded) }
    }

    func toggleExpansion(for nodeID: UUID) {
        guard let node = nodeLookup[nodeID] else { return }
        node.isExpanded.toggle()
    }
    
    func beautifyJSON() {
        parseJSON(inputJSON, autoExpand: true)
    }

    func beautifyAndSaveJSON() {
        parseJSON(inputJSON, autoExpand: true)

        // Save after beautification if parsing was successful
        // The inputJSON will be updated with the beautified version by parseJSON
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if self.errorMessage == nil && !self.inputJSON.isEmpty {
                if let saved = self.saveJSON(self.inputJSON) {
                    self.selectedJSONID = saved.id
                }
            }
        }
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
        request.httpBody = nil

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSubmittingFeedback = false

                if let error = error {
                    self.feedbackSubmissionIsError = true
                    self.feedbackSubmissionMessage = "Failed to submit: \(error.localizedDescription)"
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
                        self.feedbackSubmissionMessage = "Unexpected response (\(statusCode))."
                    } else {
                        self.feedbackSubmissionMessage = "Unexpected response."
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
                    guard strongSelf.formattedSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == loweredQuery else { return }
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

    private func applyFormattedSearchComputation(_ computation: FormattedSearchComputation, rootNode: JSONNode) {
        formattedSearchMatches = computation.highlightIDs
        formattedSearchMatchOrder = computation.matchesOrdered

        let targetIndex: Int?
        if let currentID = formattedSearchFocusedID,
           let currentIndex = computation.matchesOrdered.firstIndex(of: currentID) {
            targetIndex = currentIndex
        } else {
            targetIndex = computation.matchesOrdered.isEmpty ? nil : 0
        }

        updateFocusedMatch(to: targetIndex)

        if !computation.expansionIDs.isEmpty {
            expandNodes(with: computation.expansionIDs)
        }
    }

    private func expandNodes(with expansionIDs: Set<UUID>) {
        guard !expansionIDs.isEmpty else { return }

        for id in expansionIDs {
            nodeLookup[id]?.isExpanded = true
        }
    }

    private static func makeSnapshot(from node: JSONNode) -> JSONNodeSnapshot {
        let normalizedValue: String?
        if node.children.isEmpty {
            normalizedValue = normalizedValueString(for: node.value)
        } else {
            normalizedValue = nil
        }

        let children = node.children.map { makeSnapshot(from: $0) }

        return JSONNodeSnapshot(
            id: node.id,
            keyLowercased: node.isRoot ? "" : node.key.lowercased(),
            isRoot: node.isRoot,
            typeDescriptionLowercased: node.typeDescription.lowercased(),
            normalizedValue: normalizedValue,
            children: children
        )
    }

    private static func computeFormattedSearchComputation(snapshot: JSONNodeSnapshot, query: String, shouldCancel: () -> Bool) throws -> FormattedSearchComputation {
        if shouldCancel() {
            throw FormattedSearchCancellation.cancelled
        }

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
        appendNormalizedValue(value, to: &result, maxDepth: 2)
        return result
    }

    private static func appendNormalizedValue(_ value: Any, to result: inout String, maxDepth: Int) {
        if maxDepth <= 0 {
            return
        }

        switch value {
        case let stringValue as String:
            if !result.isEmpty { result.append(" ") }
            result.append(stringValue.lowercased())

        case let number as NSNumber:
            if !result.isEmpty { result.append(" ") }
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                result.append(number.boolValue ? "true" : "false")
            } else {
                result.append(number.stringValue.lowercased())
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
                result.append(key.lowercased())
                appendNormalizedValue(value, to: &result, maxDepth: maxDepth - 1)
            }

        case let ordered as OrderedDictionary:
            // Limit ordered dict processing to first 50 pairs
            let limit = min(ordered.orderedPairs.count, 50)
            for (key, value) in ordered.orderedPairs.prefix(limit) {
                if !result.isEmpty { result.append(" ") }
                result.append(key.lowercased())
                appendNormalizedValue(value, to: &result, maxDepth: maxDepth - 1)
            }

        default:
            if !result.isEmpty { result.append(" ") }
            result.append(String(describing: value).lowercased())
        }
    }

    private struct JSONNodeSnapshot {
        let id: UUID
        let keyLowercased: String
        let isRoot: Bool
        let typeDescriptionLowercased: String
        let normalizedValue: String?
        let children: [JSONNodeSnapshot]

        func matches(query: String) -> Bool {
            if !isRoot && keyLowercased.contains(query) {
                return true
            }

            if children.isEmpty {
                if let normalizedValue, normalizedValue.contains(query) {
                    return true
                }
            } else if typeDescriptionLowercased.contains(query) {
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
