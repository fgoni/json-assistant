import SwiftUI

@main
struct JSON_AssistantApp: App {
    @StateObject private var viewModel = JSONViewModel()
    @StateObject private var themeSettings = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(jsonViewModel: viewModel, themeSettings: themeSettings)
                .environmentObject(themeSettings)
        }
        .commands {
            CommandMenu("JSON Actions") {
                Button("New Entry") {
                    viewModel.startNewEntry()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Collapse All") {
                    viewModel.collapseAll()
                }
                .keyboardShortcut("-", modifiers: [.command, .option])

                Button("Expand All") {
                    viewModel.expandAll()
                }
                .keyboardShortcut("=", modifiers: [.command, .option])

                Divider()

                Button("Select Latest 1") {
                    viewModel.selectLatest(1)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Select Latest 2") {
                    viewModel.selectLatest(2)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Select Latest 3") {
                    viewModel.selectLatest(3)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Select Latest 4") {
                    viewModel.selectLatest(4)
                }
                .keyboardShortcut("4", modifiers: .command)

                Divider()

                Button("Find Next") {
                    viewModel.focusNextFormattedMatch()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(viewModel.formattedSearchMatchOrder.isEmpty)

                Button("Find Previous") {
                    viewModel.focusPreviousFormattedMatch()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(viewModel.formattedSearchMatchOrder.isEmpty)
            }

            CommandMenu("Font Size") {
                Button("Increase Formatted JSON Font Size") {
                    themeSettings.increaseFormattedJSONFontSize()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Formatted JSON Font Size") {
                    themeSettings.decreaseFormattedJSONFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button("Increase Request JSON Font Size") {
                    themeSettings.increaseRequestJSONFontSize()
                }
                .keyboardShortcut("=", modifiers: [.command, .shift])

                Button("Decrease Request JSON Font Size") {
                    themeSettings.decreaseRequestJSONFontSize()
                }
                .keyboardShortcut("-", modifiers: [.command, .shift])

                Divider()

                Button("Reset Font Sizes") {
                    themeSettings.resetFontSizes()
                }
            }

            CommandMenu("Settings") {
                Button(action: {
                    themeSettings.showSettingsPanel = true
                }) {
                    Text("Preferences...")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
