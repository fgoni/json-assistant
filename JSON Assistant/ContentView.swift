import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Syntax Highlighted Text Editor

#if canImport(AppKit)
struct SyntaxHighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let palette: ThemePalette
    let onPaste: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor(palette.text)
        textView.backgroundColor = .clear
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        context.coordinator.textView = textView
        context.coordinator.updateSyntaxHighlighting()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRange = textView.selectedRanges.first?.rangeValue ?? NSRange(location: 0, length: 0)
            textView.string = text
            context.coordinator.updateSyntaxHighlighting()

            // Restore cursor position
            let newLocation = min(selectedRange.location, text.count)
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, palette: palette, onPaste: onPaste)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        let palette: ThemePalette
        let onPaste: (String) -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, palette: ThemePalette, onPaste: @escaping (String) -> Void) {
            self._text = text
            self.palette = palette
            self.onPaste = onPaste
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateSyntaxHighlighting()
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            // Detect paste operation
            if let replacement = replacementString, replacement.count > 1 {
                // This is likely a paste
                let pasteBoard = NSPasteboard.general
                if let pastedText = pasteBoard.string(forType: .string), pastedText == replacement {
                    DispatchQueue.main.async { [weak self] in
                        self?.onPaste(pastedText)
                    }
                }
            }
            return true
        }

        func updateSyntaxHighlighting() {
            guard let textView = textView else { return }
            guard let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)

            // Reset to default text color
            textStorage.addAttribute(.foregroundColor, value: NSColor(palette.text), range: fullRange)

            let text = textStorage.string

            // Apply JSON syntax highlighting
            highlightJSON(in: text, textStorage: textStorage)
        }

        private func highlightJSON(in text: String, textStorage: NSTextStorage) {
            var index = text.startIndex

            while index < text.endIndex {
                let char = text[index]
                let startIndex = index

                // Skip whitespace
                if char.isWhitespace {
                    index = text.index(after: index)
                    continue
                }

                // String literals (keys and values)
                if char == "\"" {
                    if let endIndex = findStringEnd(in: text, from: index) {
                        let range = NSRange(startIndex..<endIndex, in: text)
                        let stringContent = String(text[startIndex...endIndex])

                        // Check if this is a key (followed by a colon)
                        var checkIndex = endIndex
                        while checkIndex < text.endIndex && text[checkIndex].isWhitespace {
                            checkIndex = text.index(after: checkIndex)
                        }

                        let isKey = checkIndex < text.endIndex && text[checkIndex] == ":"
                        let color = isKey ? NSColor(palette.key) : NSColor(palette.string)
                        textStorage.addAttribute(.foregroundColor, value: color, range: range)

                        index = text.index(after: endIndex)
                        continue
                    }
                }

                // Numbers
                if char.isNumber || char == "-" {
                    var endIndex = index
                    while endIndex < text.endIndex {
                        let c = text[endIndex]
                        if c.isNumber || c == "." || c == "-" || c == "+" || c == "e" || c == "E" {
                            endIndex = text.index(after: endIndex)
                        } else {
                            break
                        }
                    }

                    if endIndex > index {
                        let range = NSRange(startIndex..<endIndex, in: text)
                        textStorage.addAttribute(.foregroundColor, value: NSColor(palette.number), range: range)
                        index = endIndex
                        continue
                    }
                }

                // Boolean values
                if text[index...].starts(with: "true") {
                    let endIndex = text.index(index, offsetBy: 4)
                    let range = NSRange(startIndex..<endIndex, in: text)
                    textStorage.addAttribute(.foregroundColor, value: NSColor(palette.boolTrue), range: range)
                    index = endIndex
                    continue
                }

                if text[index...].starts(with: "false") {
                    let endIndex = text.index(index, offsetBy: 5)
                    let range = NSRange(startIndex..<endIndex, in: text)
                    textStorage.addAttribute(.foregroundColor, value: NSColor(palette.boolFalse), range: range)
                    index = endIndex
                    continue
                }

                // Null
                if text[index...].starts(with: "null") {
                    let endIndex = text.index(index, offsetBy: 4)
                    let range = NSRange(startIndex..<endIndex, in: text)
                    textStorage.addAttribute(.foregroundColor, value: NSColor(palette.null), range: range)
                    index = endIndex
                    continue
                }

                // Punctuation
                if "{}[],:".contains(char) {
                    let endIndex = text.index(after: index)
                    let range = NSRange(startIndex..<endIndex, in: text)
                    textStorage.addAttribute(.foregroundColor, value: NSColor(palette.punctuation), range: range)
                    index = endIndex
                    continue
                }

                index = text.index(after: index)
            }
        }

        private func findStringEnd(in text: String, from startIndex: String.Index) -> String.Index? {
            var index = text.index(after: startIndex) // Skip opening quote
            var escaped = false

            while index < text.endIndex {
                let char = text[index]

                if escaped {
                    escaped = false
                    index = text.index(after: index)
                    continue
                }

                if char == "\\" {
                    escaped = true
                    index = text.index(after: index)
                    continue
                }

                if char == "\"" {
                    return index
                }

                index = text.index(after: index)
            }

            return nil
        }
    }
}
#endif

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var jsonViewModel: JSONViewModel

    private var palette: ThemePalette {
        ThemePalette.palette(for: colorScheme)
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            NavigationView {
                SidebarView(jsonViewModel: jsonViewModel, palette: palette)
                    .frame(minWidth: 220)
                    .background(palette.surface)

                HSplitView {
                    JSONInputView(jsonViewModel: jsonViewModel, palette: palette)
                        .frame(minWidth: 280)
                    JSONOutputView(jsonViewModel: jsonViewModel, palette: palette)
                        .frame(minWidth: 360)
                }
                .background(palette.background)
            }
            .navigationViewStyle(.automatic)
        }
        .accentColor(palette.accent)
    }
}


struct SidebarView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    let palette: ThemePalette
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 16) {
            LogoView()
                .frame(width: 88, height: 88)
                .padding(.top, 12)

            Text("JSON Assistant")
                .font(.themedUI(size: 13))
                .fontWeight(.semibold)
                .foregroundColor(palette.text)
                .padding(.bottom, 8)



            if sections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(palette.punctuation)
                    Text("No saved responses yet")
                        .font(.themedUI(size: 12))
                        .foregroundColor(palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.surface)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                Text(section.title)
                    .font(.themedUI(size: 11))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                                VStack(spacing: 8) {
                                    ForEach(section.items) { json in
                                        SavedJSONRow(
                                            json: json,
                                            palette: palette,
                                            isSelected: jsonViewModel.selectedJSONID == json.id,
                                            timeString: SidebarView.timeFormatter.string(from: json.date),
                                            preview: previewText(for: json),
                                            onSelect: {
                                                jsonViewModel.loadSavedJSON(json)
                                            },
                                            onDelete: {
                                                jsonViewModel.deleteJSON(json)
                                            },
                                            onRename: { newName in
                                                jsonViewModel.updateJSONName(json, newName: newName)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .background(palette.surface)
    }

    private var sections: [SidebarSection] {
        let grouped = Dictionary(grouping: jsonViewModel.parsedJSONs) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (key: Date, value: [ParsedJSON]) -> SidebarSection in
                SidebarSection(
                    id: key,
                    title: sectionTitle(for: key),
                    items: value.sorted { $0.date > $1.date }
                )
            }
            .sorted { $0.id > $1.id }
    }

    private func sectionTitle(for date: Date) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return SidebarView.monthFormatter.string(from: date)
    }

    private func previewText(for json: ParsedJSON) -> String {
        let collapsed = json.content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let components = collapsed
            .split(whereSeparator: { $0.isNewline || $0.isWhitespace })
        var joined = components.joined(separator: " ")
        if joined.isEmpty {
            let trimmed = json.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "(empty)" : trimmed
        }
        if joined.count > 120 {
            let endIndex = joined.index(joined.startIndex, offsetBy: 120)
            joined = String(joined[..<endIndex]) + "…"
        }
        return joined
    }

    private struct SidebarSection: Identifiable {
        let id: Date
        let title: String
        let items: [ParsedJSON]
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

struct LogoView: View {
    #if canImport(AppKit)
    private var logoImage: Image {
        Image(nsImage: NSApplication.shared.applicationIconImage)
    }
    #else
    private var logoImage: Image {
        Image("AppIcon")
    }
    #endif

    var body: some View {
        logoImage
            .resizable()
            .aspectRatio(contentMode: .fit)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

struct JSONInputView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Request JSON")
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.muted)
                Spacer()
                Button {
                    jsonViewModel.startNewEntry()
                } label: {
                    HStack(spacing: 6) {
                        Text("New")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accent)
                        Text("⌘N")
                            .font(.themedUI(size: 11))
                            .foregroundColor(palette.accent.opacity(0.75))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            TextEditor(text: $jsonViewModel.inputJSON)
                .font(.themedCode())
                .foregroundColor(palette.text)
                .scrollContentBackground(.hidden)
                .hideScrollIndicatorsIfAvailable()
                .onChange(of: jsonViewModel.inputJSON) { newValue in
                    guard !jsonViewModel.isProgrammaticInputUpdate else { return }
                    jsonViewModel.parseJSON(newValue, autoExpand: false)
                }
            .padding(12)
            .background(palette.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}

struct JSONOutputView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Formatted View")
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.muted)
                Spacer()
                Button {
                    jsonViewModel.collapseAll()
                } label: {
                    HStack(spacing: 6) {
                        Text("Collapse All")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accent)
                        Text("⌘⇧-")
                            .font(.themedUI(size: 11))
                            .foregroundColor(palette.accent.opacity(0.75))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .keyboardShortcut(KeyEquivalent("-"), modifiers: [.command, .shift])

                Button {
                    jsonViewModel.expandAll()
                } label: {
                    HStack(spacing: 6) {
                        Text("Expand All")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accent)
                        Text("⌘⇧=")
                            .font(.themedUI(size: 11))
                            .foregroundColor(palette.accent.opacity(0.75))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .keyboardShortcut(KeyEquivalent("="), modifiers: [.command, .shift])
            }

            if let rootNode = jsonViewModel.rootNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        CollapsibleJSONView(node: rootNode, viewModel: jsonViewModel, palette: palette)
                            .font(.themedCode())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .background(palette.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
                )
            } else {
                JSONPlaceholderView(
                    palette: palette,
                    isError: jsonViewModel.errorMessage != nil,
                    headline: jsonViewModel.errorMessage == nil ? "No JSON data to display" : "Wrong format",
                    detail: jsonViewModel.errorMessage
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}

struct ParsedJSON: Identifiable, Codable {
    let id: UUID
    let date: Date
    var name: String
    let content: String
}

#Preview {
    ContentView(jsonViewModel: JSONViewModel())
}

private struct JSONPlaceholderView: View {
    let palette: ThemePalette
    let isError: Bool
    let headline: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(headline)
                .font(.themedUI(size: 12))
                .fontWeight(isError ? .semibold : .regular)
                .foregroundColor(isError ? palette.boolFalse : palette.muted)
            if let detail, isError {
                Text(detail)
                    .font(.themedCode(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundColor(palette.boolFalse.opacity(0.9))
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundFill)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var backgroundFill: some View {
        palette.surface
            .overlay {
                if isError {
                    palette.boolFalse.opacity(0.12)
                }
            }
    }

    private var borderColor: Color {
        isError ? palette.boolFalse.opacity(0.4) : palette.punctuation.opacity(0.25)
    }
}

private struct SavedJSONRow: View {
    let json: ParsedJSON
    let palette: ThemePalette
    let isSelected: Bool
    let timeString: String
    let preview: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Unnamed", text: Binding(
                    get: { json.name },
                    set: onRename
                ))
                .textFieldStyle(.plain)
                .font(.themedUI(size: 12))
                .fontWeight(.semibold)
                .foregroundColor(palette.text)
                .lineLimit(1)

                Spacer()

                Text(timeString)
                    .font(.themedUI(size: 11))
                    .foregroundColor(palette.muted)
            }

            Text(preview)
                .font(.themedCode(size: 11))
                .foregroundColor(palette.punctuation.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
        .padding(.leading, 12)
        .padding(.trailing, isHovering ? 48 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundFill)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.accent)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }
        }
        .overlay(alignment: .trailing) {
            if isHovering {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(palette.boolFalse)
                        .padding(6)
                        .background(palette.boolFalse.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.delete, modifiers: [.command])
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .padding(.trailing, 4)
                .padding(.top, 4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: (isHovering || isSelected) ? 1 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            #if os(macOS)
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
            #else
            isHovering = hovering
            #endif
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }

    private var backgroundFill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                isSelected
                ? palette.surface.opacity(0.9)
                : (isHovering ? palette.surface.opacity(0.6) : Color.clear)
            )
    }

    private var borderColor: Color {
        if isSelected { return palette.accent.opacity(0.4) }
        if isHovering { return palette.punctuation.opacity(0.35) }
        return .clear
    }
}

private extension View {
    @ViewBuilder
    func hideScrollIndicatorsIfAvailable() -> some View {
        if #available(macOS 13.0, iOS 16.0, *) {
            scrollIndicators(.hidden)
        } else {
            self
        }
    }
}
