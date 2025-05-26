import SwiftUI

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

class JSONNode: Identifiable, ObservableObject {
    let id = UUID()
    let key: String
    @Published var value: Any
    @Published var isExpanded: Bool = false
    @Published var children: [JSONNode] = []
    
    init(key: String, value: Any) {
        self.key = key
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
        case let stringValue as String: return "\"\(stringValue)\""
        case is NSNull: return "null"
        case let number as NSNumber:
            return number.isBool ? (number.boolValue ? "true" : "false") : number.stringValue
        default: return "\(value)"
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  
            JSONNodeView(node: node, viewModel: viewModel)
            if node.isExpanded {
                ForEach(node.children) { child in
                    CollapsibleJSONView(node: child, viewModel: viewModel)
                        .padding(.leading, 20)
                }
            }
        }
    }
}


struct JSONNodeView: View {
    @ObservedObject var node: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    
    var body: some View {
        HStack {
            if !node.children.isEmpty {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .onTapGesture {
                        viewModel.toggleExpansion(for: node.id)
                    }
            }
            Text(node.key)
                .foregroundColor(.purple)
            if node.children.isEmpty {
                Text(processValue(node.displayValue))
                    .foregroundColor(colorForValue(node.value))
            }
            Spacer()
        }
    }
    
    private func processValue(_ value: Any) -> String {
        return String(describing: value).replacingOccurrences(of: "\"", with: "")
    }
    
    private func colorForValue(_ value: Any) -> Color {
        switch value {
        case is String: return .teal
        case is NSNull: return .gray
        default: return .indigo
        }
    }
}




class JSONViewModel: ObservableObject {
    @Published var inputJSON: String = ""
    @Published var rootNode: JSONNode?
    @Published var errorMessage: String?
    @Published var parsedJSONs: [ParsedJSON] = []
    
    init() {
        loadSavedJSONs()
    }

    
    func parseAndSaveJSON(_ jsonString: String) {
        parseJSON(jsonString)
        if errorMessage == nil && !jsonString.isEmpty {
            saveJSON(jsonString)
        }
    }

    
    func parseJSON(_ jsonString: String) {
        guard !jsonString.isEmpty else {
            rootNode = nil
            errorMessage = nil
            return
        }
        
        do {
            let jsonData = jsonString.data(using: .utf8)!
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [.mutableContainers])
            
            // Convert to OrderedDictionary if it's a dictionary
            if let dict = jsonObject as? [String: Any] {
                let ordered = OrderedDictionary()
                for (key, value) in dict {
                    ordered[key] = value
                }
                rootNode = JSONNode(key: "root", value: ordered)
            } else {
                rootNode = JSONNode(key: "root", value: jsonObject)
            }
            
            errorMessage = nil
            expandAll()
        } catch {
            errorMessage = "Error parsing JSON: \(error.localizedDescription)"
        }
    }

    
    func saveJSON(_ jsonString: String) {
        guard !jsonString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !parsedJSONs.contains(where: { $0.content == jsonString }) else { return }
        
        let newParsedJSON = ParsedJSON(id: UUID(), date: Date(), name: "Unnamed", content: jsonString)
        parsedJSONs.append(newParsedJSON)
        saveParsedJSONs()
    }
    
    func loadSavedJSON(_ json: ParsedJSON) {
        inputJSON = json.content
        parseJSON(json.content)
    }
    
    func deleteJSON(_ json: ParsedJSON) {
        parsedJSONs.removeAll { $0.id == json.id }
        saveParsedJSONs()
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
        guard let jsonData = inputJSON.data(using: .utf8) else {
            errorMessage = "Invalid JSON: Could not convert string to data"
            return
        }
        
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [.mutableContainers])
            let beautifiedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
            if let beautifiedString = String(data: beautifiedData, encoding: .utf8) {
                inputJSON = beautifiedString
                parseJSON(beautifiedString) // Just parse, don't save
            }
        } catch {
            errorMessage = "Error beautifying JSON: \(error.localizedDescription)"
        }
    }
    
}
