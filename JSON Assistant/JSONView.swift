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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JSONNodeView(node: node, viewModel: viewModel, palette: palette)
            if node.isExpanded {
                ForEach(node.children) { child in
                    CollapsibleJSONView(node: child, viewModel: viewModel, palette: palette)
                        .padding(.leading, 16)
                }
            }
        }
    }
}


struct JSONNodeView: View {
    @ObservedObject var node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    
    var body: some View {
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
                    .foregroundColor(palette.muted)
                    .fontWeight(.semibold)
            } else {
                Text(node.key)
                    .foregroundColor(palette.key)
                Text(":")
                    .foregroundColor(palette.punctuation)
            }
            
            if node.children.isEmpty {
                leafValueView
            } else if !node.isRoot {
                Text(node.typeDescription)
                    .foregroundColor(palette.muted)
            }
            
            Spacer(minLength: 0)
        }
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
    @Published var rootNode: JSONNode?
    @Published var errorMessage: String?
    @Published var parsedJSONs: [ParsedJSON] = []
    @Published var selectedJSONID: UUID?
    private(set) var isProgrammaticInputUpdate: Bool = false
    
    init() {
        loadSavedJSONs()
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
            DispatchQueue.main.async {
                self.rootNode = nil
                self.errorMessage = nil
            }
            return
        }
        
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            DispatchQueue.main.async {
                self.rootNode = nil
                self.errorMessage = nil
            }
            return
        }
        
        do {
            var parser = OrderedJSONParser(jsonString)
            let parsedValue = try parser.parse()
            let prettyString = OrderedJSONFormatter.prettyPrinted(parsedValue)
        
            let rootLabel = JSONNode.describeType(of: parsedValue)
            DispatchQueue.main.async {
                if autoExpand {
                    self.setEditorText(prettyString)
                }
                self.rootNode = JSONNode(key: rootLabel, value: parsedValue, isRoot: true)
                self.errorMessage = nil
                self.persistParsedJSONIfNeeded(originalJSON: jsonString, autoExpand: autoExpand)
                
                if autoExpand {
                    self.setExpansionState(for: self.rootNode, isExpanded: true)
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
           if let node = findNode(withID: nodeID, in: rootNode) {
               node.isExpanded.toggle()
           }
       }
       
       private func findNode(withID id: UUID, in node: JSONNode?) -> JSONNode? {
           guard let node = node else { return nil }
           if node.id == id { return node }
           for child in node.children {
               if let found = findNode(withID: id, in: child) {
                   return found
               }
           }
           return nil
       }
    
    func beautifyJSON() {
        parseJSON(inputJSON, autoExpand: true)
    }

    func startNewEntry() {
        selectedJSONID = nil
        setEditorText("")
        rootNode = nil
        errorMessage = nil
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
    
}
