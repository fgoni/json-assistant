import SwiftUI

struct ContentView: View {
    @StateObject private var jsonViewModel = JSONViewModel()
        
    var body: some View {
        NavigationView {
            SidebarView(jsonViewModel: jsonViewModel)
            
            HSplitView {
                JSONInputView(jsonViewModel: jsonViewModel)
                JSONOutputView(jsonViewModel: jsonViewModel)
            }
        }
    }
}


struct SidebarView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    
    var body: some View {
        VStack {
            LogoView()
                .frame(width: 100, height: 100)
                .padding()
            
            Text("JSON Assistant")
                .font(.headline)
                .padding(.bottom)
            
            List {
                ForEach(jsonViewModel.parsedJSONs.sorted(by: { $0.date > $1.date })) { json in
                    HStack {
                        VStack(alignment: .leading) {
                            TextField("Unnamed", text: Binding(
                                get: { json.name },
                                set: { jsonViewModel.updateJSONName(json, newName: $0) }
                            ))
                            .textFieldStyle(PlainTextFieldStyle())
                            
                            Text(json.date, style: .date)
                                .font(.caption)
                            Text(json.date, style: .time)
                                .font(.caption)
                        }
                        .onTapGesture {
                            jsonViewModel.loadSavedJSON(json)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            jsonViewModel.deleteJSON(json)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)
    }
}

struct LogoView: View {
    var body: some View {
        Image("JSONAssistantLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

struct JSONInputView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Beautify") {
                    jsonViewModel.beautifyJSON()
                }
                .buttonStyle(.bordered)
            }
            
            TextEditor(text: $jsonViewModel.inputJSON)
                .font(.system(.body, design: .monospaced))
                .border(Color.gray.opacity(0.2))
                .onChange(of: jsonViewModel.inputJSON) { newValue in
                    jsonViewModel.parseJSON(newValue)
                }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    }
}

struct JSONOutputView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Collapse All") {
                    jsonViewModel.collapseAll()
                }
                .buttonStyle(.bordered)
                
                Button("Expand All") {
                    jsonViewModel.expandAll()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            if let errorMessage = jsonViewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if let rootNode = jsonViewModel.rootNode {
                ScrollView {
                    CollapsibleJSONView(node: rootNode, viewModel: jsonViewModel)
                }
            } else {
                Text("No JSON data to display")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ParsedJSON: Identifiable, Codable {
    let id: UUID
    let date: Date
    var name: String
    let content: String
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
