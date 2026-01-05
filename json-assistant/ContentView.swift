import SwiftUI
import os
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Syntax Highlighted Text Editor

#if canImport(AppKit)
struct SyntaxHighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    let palette: ThemePalette
    let fontSize: CGFloat
    let wordWrap: Bool
    let onPaste: (String) -> Void

	    func makeNSView(context: Context) -> NSScrollView {
	        let scrollView = NSTextView.scrollableTextView()
	        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor(palette.text)
        textView.backgroundColor = .clear
	        textView.insertionPointColor = NSColor(palette.accent)
	        textView.selectedTextAttributes = [
	            .backgroundColor: NSColor(palette.selection),
	            .foregroundColor: NSColor.selectedTextColor
	        ]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        // Configure word-wrap
        textView.isHorizontallyResizable = !wordWrap
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
        }

        // Configure scrollers
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.appearance = NSAppearance(named: .vibrantDark)
        scrollView.horizontalScroller?.appearance = NSAppearance(named: .vibrantDark)

        // Show horizontal scroller when word-wrap is disabled
        scrollView.hasHorizontalScroller = !wordWrap
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.updateSyntaxHighlighting()

        return scrollView
    }

	    func updateNSView(_ scrollView: NSScrollView, context: Context) {
	        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.font?.pointSize != fontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if textView.insertionPointColor != NSColor(palette.accent) {
            textView.insertionPointColor = NSColor(palette.accent)
        }

        // Update word-wrap setting
        let shouldUpdate = textView.isHorizontallyResizable == wordWrap  // Will be true if state needs to change
        textView.isHorizontallyResizable = !wordWrap
        if wordWrap {
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.widthTracksTextView = false
        }

        // Update horizontal scroller visibility
        scrollView.hasHorizontalScroller = !wordWrap

        // Trigger layout update if word-wrap setting changed
        if shouldUpdate {
            // Defer layout updates to avoid reentrancy issues
            DispatchQueue.main.async {
                textView.textContainer?.size = NSZeroSize
                textView.sizeToFit()
                scrollView.needsLayout = true
                scrollView.display()
            }
        }

	        textView.selectedTextAttributes = [
	            .backgroundColor: NSColor(palette.selection),
	            .foregroundColor: NSColor.selectedTextColor
	        ]

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
        private var highlightWorkItem: DispatchWorkItem?
        private let highlightQueue = DispatchQueue(label: "com.jsonassistant.highlighting", qos: .userInitiated)

        init(text: Binding<String>, palette: ThemePalette, onPaste: @escaping (String) -> Void) {
            self._text = text
            self.palette = palette
            self.onPaste = onPaste
        }

	        func textDidChange(_ notification: Notification) {
	            guard let textView = notification.object as? NSTextView else { return }
	            text = textView.string

            // Debounce syntax highlighting - increased to 400ms for better typing responsiveness
            // This reduces unnecessary highlight calculations when user is actively typing
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.updateSyntaxHighlighting()
                }
            }
            highlightWorkItem = workItem
	            highlightQueue.asyncAfter(deadline: .now() + 0.4, execute: workItem)
	        }

	        func textViewDidChangeSelection(_ notification: Notification) {
	            guard let textView = notification.object as? NSTextView else { return }
	            textView.selectedTextAttributes = [
	                .backgroundColor: NSColor(palette.selection),
	                .foregroundColor: NSColor.selectedTextColor
	            ]
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

            let text = textStorage.string
            let textSize = text.utf8.count

            // Disable syntax highlighting for very large files (>500KB)
            let maxHighlightSize = 500_000
            if textSize > maxHighlightSize {
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.foregroundColor, value: NSColor(palette.text), range: fullRange)
                return
            }

            // Batch attribute updates for better performance
            textStorage.beginEditing()
            defer { textStorage.endEditing() }

            let fullRange = NSRange(location: 0, length: textStorage.length)

            // Reset to default text color
            textStorage.addAttribute(.foregroundColor, value: NSColor(palette.text), range: fullRange)

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
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject var jsonViewModel: JSONViewModel
    @ObservedObject var themeSettings: ThemeSettings

    private var palette: ThemePalette {
        let effectiveColorScheme = themeSettings.getColorScheme(systemScheme: systemColorScheme) ?? systemColorScheme
        return ThemePalette.palette(for: effectiveColorScheme)
    }

    private var windowTitle: String {
        guard let selectedID = jsonViewModel.selectedJSONID,
              let selected = jsonViewModel.parsedJSONs.first(where: { $0.id == selectedID }) else {
            return "JSON Assistant"
        }
        let trimmed = selected.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "JSON Assistant" : trimmed
    }

	    var body: some View {
	        ZStack {
	            palette.background.ignoresSafeArea()

	            NavigationView {
	                SidebarView(jsonViewModel: jsonViewModel, palette: palette)
	                    .frame(minWidth: 220)
	                    .background(palette.surface)

	                HSplitView {
	                    JSONInputView(jsonViewModel: jsonViewModel, themeSettings: themeSettings, palette: palette)
	                        .frame(minWidth: 280)
	                    JSONOutputView(jsonViewModel: jsonViewModel, themeSettings: themeSettings, palette: palette)
	                        .frame(minWidth: 360)
	                }
	                .background(palette.background)
	            }
	            .navigationViewStyle(.automatic)
	            .padding(.top, 16)
	        }
	        .accentColor(palette.accent)
	        .background(
	            WindowConfigurator(title: windowTitle)
        )
        .sheet(isPresented: $themeSettings.showSettingsPanel) {
            SettingsView(themeSettings: themeSettings)
        }
    }
}

#if canImport(AppKit)
private struct WindowConfigurator: NSViewRepresentable {
    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.title != title {
                window.title = title
            }

            context.coordinator.attachChromeIfNeeded(to: window)
            context.coordinator.updateTitle(title)

            if #available(macOS 11.0, *) {
                window.toolbarStyle = .unifiedCompact
            }
        }
    }

    final class Coordinator: NSObject, NSToolbarDelegate {
        private static let toolbarIdentifier = NSToolbar.Identifier("MainToolbar")

        private weak var window: NSWindow?
        private weak var titlebarLabel: NSTextField?
        private weak var titlebarLabelSuperview: NSView?

	        func attachChromeIfNeeded(to window: NSWindow) {
	            self.window = window

            if window.toolbar?.identifier != Self.toolbarIdentifier {
                let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
                toolbar.delegate = self
                toolbar.displayMode = .iconOnly
                toolbar.allowsUserCustomization = false
                toolbar.autosavesConfiguration = false
                toolbar.showsBaselineSeparator = true
                window.toolbar = toolbar
	            } else if window.toolbar?.delegate == nil {
	                window.toolbar?.delegate = self
	            }

	            window.titlebarAppearsTransparent = false
	            window.styleMask.remove(.fullSizeContentView)
	            window.titleVisibility = .hidden
	            attachOrUpdateTitlebarLabel(for: window)
	        }

        func updateTitle(_ title: String) {
            guard let label = titlebarLabel else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.stringValue = title
            CATransaction.commit()
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            []
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            []
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            nil
        }

	        private func attachOrUpdateTitlebarLabel(for window: NSWindow) {
	            guard let zoomButton = window.standardWindowButton(.zoomButton) else { return }
	            guard let container = zoomButton.superview?.superview ?? zoomButton.superview else { return }

	            if titlebarLabelSuperview !== container || titlebarLabel == nil {
	                titlebarLabel?.removeFromSuperview()

	                let label = NSTextField(labelWithString: "")
	                label.textColor = .labelColor
	                label.lineBreakMode = .byTruncatingTail
	                label.translatesAutoresizingMaskIntoConstraints = false
	                label.maximumNumberOfLines = 1

	                container.addSubview(label)

	                NSLayoutConstraint.activate([
	                    label.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 8),
	                    label.centerYAnchor.constraint(equalTo: zoomButton.centerYAnchor),
	                    label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12)
	                ])

	                titlebarLabel = label
	                titlebarLabelSuperview = container

	                // Set font properties asynchronously to avoid constraint cascade crashes
	                DispatchQueue.main.async { [weak label] in
	                    CATransaction.begin()
	                    CATransaction.setDisableActions(true)
	                    label?.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
	                    label?.setContentHuggingPriority(.defaultHigh, for: .horizontal)
	                    label?.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
	                    CATransaction.commit()
	                }
	            }
	        }
	    }
	}
#else
private struct WindowConfigurator: View {
    let title: String
    var body: some View { EmptyView() }
}
#endif


struct SidebarView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    let palette: ThemePalette
    private let calendar = Calendar.current
    @State private var searchText: String = ""
    @State private var isShowingFeedbackSheet: Bool = false
    @State private var feedbackDraft: String = ""
    @State private var didSubmitFeedback: Bool = false

	    var body: some View {
	        VStack(spacing: 16) {
	            LogoView()
	                .frame(width: 88, height: 88)

	            VStack(spacing: 4) {
	                Text("JSON Assistant")
                    .font(.themedUI(size: 13))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("v\(version) (\(build))")
                        .font(.themedUI(size: 10))
                        .foregroundColor(palette.text.opacity(0.5))
                }
            }
            .padding(.bottom, 8)

            searchField


            if jsonViewModel.parsedJSONs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.themedUI(size: 28))
                        .fontWeight(.semibold)
                        .foregroundColor(palette.punctuation)
                    Text("No saved responses yet")
                        .font(.themedUI(size: 12))
                        .foregroundColor(palette.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(palette.surface)
            } else if filteredSections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.themedUI(size: 28))
                        .fontWeight(.semibold)
                        .foregroundColor(palette.punctuation)
                    Text("No matches found")
                        .font(.themedUI(size: 12))
                        .foregroundColor(palette.text)
                    if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Tried \"\(searchText)\" in names and JSON paths.")
                            .font(.themedUI(size: 11))
                            .foregroundColor(palette.text.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(palette.surface)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                        ForEach(filteredSections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                Text(section.title)
                    .font(.themedUI(size: 11))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)
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

            Spacer(minLength: 12)

            VStack(spacing: 8) {
                Button {
                    jsonViewModel.resetFeedbackStatus()
                    feedbackDraft = ""
                    didSubmitFeedback = false
                    isShowingFeedbackSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                        Text(jsonViewModel.isSubmittingFeedback ? "Submitting..." : "Submit Feedback")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(palette.accentButtonText)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(jsonViewModel.isSubmittingFeedback)
                .opacity(jsonViewModel.isSubmittingFeedback ? 0.75 : 1)

                if let message = jsonViewModel.feedbackSubmissionMessage {
                    Text(message)
                        .font(.themedUI(size: 11))
                        .multilineTextAlignment(.center)
                        .foregroundColor(jsonViewModel.feedbackSubmissionIsError ? palette.boolFalse : palette.muted)
                        .frame(maxWidth: .infinity)
                }

                Link(destination: URL(string: "https://coffeedevs.com")!) {
                    Text("Built with ❤️ by coffeedevs.com")
                        .font(.themedUI(size: 10))
                        .foregroundColor(palette.muted.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.plain)
            }
        }
	        .padding(.top, 12)
	        .padding(.horizontal, 12)
	        .padding(.bottom, 16)
	        .background(palette.surface)
        .sheet(isPresented: $isShowingFeedbackSheet) {
            FeedbackSheet(
                palette: palette,
                jsonViewModel: jsonViewModel,
                feedbackText: $feedbackDraft,
                isPresented: $isShowingFeedbackSheet,
                didSubmit: $didSubmitFeedback
            )
        }
    }

    @ViewBuilder
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.themedUI(size: 12))
                .fontWeight(.semibold)
                .foregroundColor(palette.text)
            TextField("Search saved JSON", text: $searchText)
                .textFieldStyle(.plain)
                .font(.themedUI(size: 12))
                .foregroundColor(palette.text)
                .disableAutocorrection(true)
                // Improve placeholder text visibility in dark mode
                .tint(palette.accent)
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.themedUI(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(palette.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 6)
    }

    private var filteredSections: [SidebarSection] {
        let grouped = Dictionary(grouping: filteredJSONs) { calendar.startOfDay(for: $0.date) }
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

    private var filteredJSONs: [ParsedJSON] {
        jsonViewModel.filteredParsedJSONs(matching: searchText)
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

    private struct FeedbackSheet: View {
        let palette: ThemePalette
        @ObservedObject var jsonViewModel: JSONViewModel
        @Binding var feedbackText: String
        @Binding var isPresented: Bool
        @Binding var didSubmit: Bool

        var body: some View {
            let trimmedText = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            let isSendDisabled = jsonViewModel.isSubmittingFeedback || trimmedText.isEmpty

            VStack(alignment: .leading, spacing: 16) {
                Text("Submit Feedback")
                    .font(.themedUI(size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)

                Text("Tell us what you think and we'll send it to the team.")
                    .font(.themedUI(size: 12))
                    .foregroundColor(palette.muted)

                TextEditor(text: $feedbackText)
                    .font(.themedUI(size: 12))
                    .foregroundColor(palette.text)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
                    )

                if let message = jsonViewModel.feedbackSubmissionMessage, didSubmit {
                    HStack(spacing: 8) {
                        Image(systemName: jsonViewModel.feedbackSubmissionIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(jsonViewModel.feedbackSubmissionIsError ? palette.boolFalse : palette.accent)
                        Text(message)
                            .font(.themedUI(size: 11))
                            .foregroundColor(jsonViewModel.feedbackSubmissionIsError ? palette.boolFalse : palette.muted)
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.themedUI(size: 12))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.surface.opacity(0.7))
                    )
                    .buttonStyle(.plain)

                    Button {
                        didSubmit = true
                        jsonViewModel.submitFeedback(message: feedbackText)
                    } label: {
                        HStack(spacing: 6) {
                            if jsonViewModel.isSubmittingFeedback {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.6, anchor: .center)
                            }
                            Text(jsonViewModel.isSubmittingFeedback ? "Sending..." : "Send Feedback")
                        }
                        .font(.themedUI(size: 12))
                        .fontWeight(.semibold)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .foregroundColor(palette.surface)
                        .background(palette.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendDisabled)
                }
            }
            .padding(24)
            .frame(minWidth: 360)
            .background(palette.background)
            .onChange(of: feedbackText) { _ in
                if didSubmit && jsonViewModel.feedbackSubmissionIsError {
                    jsonViewModel.resetFeedbackStatus()
                    didSubmit = false
                }
            }
            .onChange(of: jsonViewModel.isSubmittingFeedback) { submitting in
                guard !submitting,
                      didSubmit,
                      !jsonViewModel.feedbackSubmissionIsError,
                      let message = jsonViewModel.feedbackSubmissionMessage,
                      !message.isEmpty else { return }
                feedbackText = ""
                didSubmit = false
                isPresented = false
            }
        }
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
    @ObservedObject var themeSettings: ThemeSettings
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Request JSON")
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)
                Spacer()
                Button {
                    jsonViewModel.startNewEntry()
                } label: {
                    HStack(spacing: 6) {
                        Text("New")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accentButtonText)
                        Text("⌘N")
                            .font(.themedUI(size: 11))
                            .foregroundColor(palette.accentButtonText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command])
            }

            #if canImport(AppKit)
            SyntaxHighlightedTextEditor(
                text: $jsonViewModel.inputJSON,
                palette: palette,
                fontSize: CGFloat(themeSettings.requestJSONFontSize),
                wordWrap: themeSettings.requestJSONWordWrap,
                onPaste: { pastedText in
                    jsonViewModel.inputJSON = pastedText
                    jsonViewModel.beautifyAndSaveJSON()
                }
            )
            .onChange(of: jsonViewModel.inputJSON) { newValue in
                guard !jsonViewModel.isProgrammaticInputUpdate else { return }
                jsonViewModel.parseJSON(newValue, autoExpand: false)
            }
            .onChange(of: themeSettings.requestJSONWordWrap) { _ in
                // Trigger re-render when word-wrap setting changes
            }
            .padding(12)
            .background(palette.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
            )
            #else
            TextEditor(text: $jsonViewModel.inputJSON)
                .font(.themedCode(size: CGFloat(themeSettings.requestJSONFontSize)))
                .foregroundColor(palette.text)
                .scrollContentBackground(.hidden)
                .hideScrollIndicatorsIfAvailable()
                .onChange(of: jsonViewModel.inputJSON) { newValue in
                    guard !jsonViewModel.isProgrammaticInputUpdate else { return }
                    jsonViewModel.parseJSON(newValue, autoExpand: false)
                }
                .onPasteCommand(of: [.plainText]) { providers in
                    for provider in providers {
                        _ = provider.loadDataRepresentation(for: .plainText) { data, error in
                            guard let data = data,
                                  let pastedText = String(data: data, encoding: .utf8) else { return }

                            DispatchQueue.main.async {
                                jsonViewModel.inputJSON = pastedText
                                jsonViewModel.beautifyAndSaveJSON()
                            }
                        }
                    }
                }
            .padding(12)
            .background(palette.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
            )
            #endif
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }
}

struct JSONOutputView: View {
    @ObservedObject var jsonViewModel: JSONViewModel
    @ObservedObject var themeSettings: ThemeSettings
    let palette: ThemePalette
    @State private var localSearchText: String = ""
    @State private var searchDebounceTimer: Timer?
    @State private var lastSelectedJSONID: UUID?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Formatted View")
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.muted)
                Spacer()
                formattedSearchControls
                Button {
                    jsonViewModel.collapseAll()
                } label: {
                    HStack(spacing: 6) {
                        Text(jsonViewModel.isExpandingOrCollapsing ? "Collapsing..." : "Collapse All")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accentButtonText)
                        if !jsonViewModel.isExpandingOrCollapsing {
                            Text("⌘⌥-")
                                .font(.themedUI(size: 11))
                                .foregroundColor(palette.accentButtonText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(jsonViewModel.isExpandingOrCollapsing ? 0.6 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(jsonViewModel.isExpandingOrCollapsing)
                .keyboardShortcut(KeyEquivalent("-"), modifiers: [.command, .option])

                Button {
                    jsonViewModel.expandAll()
                } label: {
                    HStack(spacing: 6) {
                        Text(jsonViewModel.isExpandingOrCollapsing ? "Expanding..." : "Expand All")
                            .font(.themedUI(size: 12))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.accentButtonText)
                        if !jsonViewModel.isExpandingOrCollapsing {
                            Text("⌘⌥=")
                                .font(.themedUI(size: 11))
                                .foregroundColor(palette.accentButtonText)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(jsonViewModel.isExpandingOrCollapsing ? 0.6 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(jsonViewModel.isExpandingOrCollapsing)
                .keyboardShortcut(KeyEquivalent("="), modifiers: [.command, .option])
            }
            .onChange(of: jsonViewModel.selectedJSONID) { newSelectedID in
                // Save current search state for previous JSON
                if let lastID = lastSelectedJSONID {
                    jsonViewModel.saveSearchState(for: lastID, query: localSearchText)
                }

                // Update tracking
                lastSelectedJSONID = newSelectedID

                // Cancel any pending search
                searchDebounceTimer?.invalidate()
                searchDebounceTimer = nil

                // Clear the search immediately (both UI and viewModel)
                localSearchText = ""
                jsonViewModel.updateFormattedSearch(with: "")

                // Restore or set search state for new JSON
                if let newID = newSelectedID {
                    if let savedSearch = jsonViewModel.getSearchState(for: newID) {
                        // Restore previous search for this JSON after a brief delay
                        // to ensure snapshot is created from the new JSON
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            localSearchText = savedSearch
                            jsonViewModel.updateFormattedSearch(with: savedSearch, skipDebounce: true)
                        }
                    }
                }
            }

            if jsonViewModel.isLoadingJSON {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5, anchor: .center)
                    Text("Processing JSON...")
                        .font(.themedUI(size: 12))
                        .foregroundColor(palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(palette.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
                )
            } else if let rootNode = jsonViewModel.rootNode {
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal], showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            CollapsibleJSONView(node: rootNode, viewModel: jsonViewModel, palette: palette, themeSettings: themeSettings)
                                .font(.themedCode(size: CGFloat(themeSettings.formattedJSONFontSize)))
                        }
                        .frame(maxWidth: themeSettings.formattedJSONWordWrap ? .infinity : nil, alignment: .leading)
                        .padding(12)
                    }
                    .onAppear {
                        os_log("SCROLL: ScrollView appeared for root node", log: OSLog.default, type: .debug)
                    }
                    .background(palette.surface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
                    )
                    .onChange(of: jsonViewModel.formattedSearchFocusedID) { targetID in
                        guard let targetID else { return }
                        os_log("SCROLL: Focusing on node %{public}s", log: OSLog.default, type: .debug, String(describing: targetID))
                        // Delay scroll to ensure pagination is resolved and views are laid out
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(targetID, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                JSONPlaceholderView(
                    palette: palette,
                    isError: jsonViewModel.errorMessage != nil,
                    headline: jsonViewModel.errorMessage == nil ? "No JSON data to display" : "Wrong format",
                    detail: jsonViewModel.errorMessage
                )
            }
        }
        .onChange(of: themeSettings.formattedJSONWordWrap) { _ in
            // Trigger re-render when word-wrap setting changes
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
    }

    private var formattedSearchControls: some View {
        let matchCount = jsonViewModel.formattedSearchMatchOrder.count
        let focusedIndex = jsonViewModel.formattedSearchFocusedIndex

        return HStack(spacing: 10) {
            formattedSearchTextField

            if matchCount > 0 {
                let index = focusedIndex ?? 0

                Text("\(index + 1)/\(matchCount)")
                    .font(.themedUI(size: 11))
                    .foregroundColor(palette.muted)

                HStack(spacing: 4) {
                    Button {
                        jsonViewModel.focusPreviousFormattedMatch()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.themedUI(size: 11))
                            .fontWeight(.semibold)
                            .foregroundColor(matchCount > 1 ? palette.accent : palette.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(matchCount <= 1)

                    Button {
                        jsonViewModel.focusNextFormattedMatch()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.themedUI(size: 11))
                            .fontWeight(.semibold)
                            .foregroundColor(matchCount > 1 ? palette.accent : palette.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(matchCount <= 1)
                }
            }
        }
        .frame(minWidth: 160, maxWidth: 320)
    }

    private var formattedSearchTextField: some View {
        HStack(spacing: 8) {
            if jsonViewModel.isFormattedSearchSnapshotLoading {
                ProgressView()
                    .scaleEffect(0.75, anchor: .center)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.muted)
            }
            TextField(
                "Search formatted JSON",
                text: Binding(
                    get: { localSearchText },
                    set: { newValue in
                        localSearchText = newValue

                        // Debounce: only call updateFormattedSearch after 200ms of no typing
                        searchDebounceTimer?.invalidate()
                        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
                            jsonViewModel.updateFormattedSearch(with: newValue, skipDebounce: true)
                        }
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.themedUI(size: 12))
            .foregroundColor(palette.text)
            .tint(palette.accent)
            .disableAutocorrection(true)
            if !localSearchText.isEmpty {
                Button {
                    localSearchText = ""
                    jsonViewModel.updateFormattedSearch(with: "")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.themedUI(size: 12))
                        .fontWeight(.semibold)
                        .foregroundColor(palette.muted.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.background.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.punctuation.opacity(0.35), lineWidth: 1)
        )
        .frame(minWidth: 160)
    }
}

struct ParsedJSON: Identifiable, Codable {
    let id: UUID
    let date: Date
    var name: String
    let content: String
}

#Preview {
    ContentView(jsonViewModel: JSONViewModel(), themeSettings: ThemeSettings())
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var themeSettings: ThemeSettings
    @Environment(\.colorScheme) var systemColorScheme
    @Environment(\.dismiss) var dismiss

    private var palette: ThemePalette {
        ThemePalette.palette(for: themeSettings.getColorScheme(systemScheme: systemColorScheme) ?? systemColorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.themedUI(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)

                Divider()
                    .background(palette.punctuation.opacity(0.2))
            }
            .padding(12)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Theme Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Appearance")
                            .font(.themedUI(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.text)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ThemeMode.allCases) { mode in
                                HStack(spacing: 12) {
                                    Image(systemName: themeSettings.selectedTheme == mode ? "checkmark.circle.fill" : "circle")
                                        .font(.themedUI(size: 14))
                                        .fontWeight(.semibold)
                                        .foregroundColor(
                                            themeSettings.selectedTheme == mode
                                            ? palette.accent
                                            : palette.muted
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(.themedUI(size: 12))
                                            .fontWeight(.semibold)
                                            .foregroundColor(palette.text)

                                        if mode == .system {
                                            Text("Follow device settings")
                                                .font(.themedUI(size: 11))
                                                .foregroundColor(palette.muted)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            themeSettings.selectedTheme == mode
                                            ? palette.accent.opacity(0.1)
                                            : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            themeSettings.selectedTheme == mode
                                            ? palette.accent.opacity(0.3)
                                            : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        themeSettings.selectedTheme = mode
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(palette.punctuation.opacity(0.2), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Font Sizes")
                            .font(.themedUI(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.text)

                        VStack(alignment: .leading, spacing: 14) {
                            fontSizeRow(
                                title: "UI",
                                value: $themeSettings.uiFontSize,
                                hint: "Scales interface text"
                            )

                            fontSizeRow(
                                title: "Request JSON",
                                value: $themeSettings.requestJSONFontSize,
                                hint: "⌘⇧= / ⌘⇧-"
                            )

                            fontSizeRow(
                                title: "Formatted JSON",
                                value: $themeSettings.formattedJSONFontSize,
                                hint: "⌘= / ⌘-"
                            )

                            HStack {
                                Spacer()
                                Button("Reset Font Sizes") {
                                    themeSettings.resetFontSizes()
                                }
                                .buttonStyle(.plain)
                                .font(.themedUI(size: 12))
                                .foregroundColor(palette.accent)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(palette.punctuation.opacity(0.2), lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text Display")
                            .font(.themedUI(size: 13))
                            .fontWeight(.semibold)
                            .foregroundColor(palette.text)

                        VStack(alignment: .leading, spacing: 12) {
                            wordWrapToggle(
                                title: "Request JSON",
                                value: $themeSettings.requestJSONWordWrap,
                                description: "Wrap long lines in request view"
                            )

                            wordWrapToggle(
                                title: "Formatted JSON",
                                value: $themeSettings.formattedJSONWordWrap,
                                description: "Wrap long lines in formatted view"
                            )
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(palette.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(palette.punctuation.opacity(0.2), lineWidth: 1)
                        )
                    }

                    Spacer()
                }
                .padding(12)
            }

            // Footer
            VStack(spacing: 12) {
                Divider()
                    .background(palette.punctuation.opacity(0.2))

                HStack(spacing: 12) {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(palette.accent)
                    .foregroundColor(palette.accentButtonText)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(palette.background)
    }

	    @ViewBuilder
	    private func fontSizeRow(title: String, value: Binding<Double>, hint: String) -> some View {
	        let canDecrease = value.wrappedValue > ThemeSettings.minimumFontSize
	        let canIncrease = value.wrappedValue < ThemeSettings.maximumFontSize

	        HStack(alignment: .firstTextBaseline, spacing: 10) {
	            VStack(alignment: .leading, spacing: 2) {
	                Text(title)
	                    .font(.themedUI(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(palette.text)

                if !hint.isEmpty {
                    Text(hint)
                        .font(.themedUI(size: 11))
                        .foregroundColor(palette.muted)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer()

	            Text("\(Int(value.wrappedValue)) pt")
	                .font(.themedUI(size: 12))
	                .foregroundColor(palette.muted)
	                .frame(minWidth: 44, alignment: .trailing)

		            VStack(spacing: 2) {
		                Button {
		                    value.wrappedValue = min(value.wrappedValue + 1, ThemeSettings.maximumFontSize)
		                } label: {
		                    Image(systemName: "chevron.up")
		                        .font(.themedUI(size: 11))
		                        .fontWeight(.semibold)
		                        .foregroundColor(canIncrease ? palette.accent : palette.muted.opacity(0.6))
		                        .frame(width: 18, height: 14)
		                        .contentShape(Rectangle())
		                }
		                .buttonStyle(.plain)
		                .disabled(!canIncrease)

	                Button {
	                    value.wrappedValue = max(value.wrappedValue - 1, ThemeSettings.minimumFontSize)
		                } label: {
		                    Image(systemName: "chevron.down")
		                        .font(.themedUI(size: 11))
		                        .fontWeight(.semibold)
		                        .foregroundColor(canDecrease ? palette.accent : palette.muted.opacity(0.6))
		                        .frame(width: 18, height: 14)
		                        .contentShape(Rectangle())
		                }
		                .buttonStyle(.plain)
		                .disabled(!canDecrease)
		            }
	            .padding(.vertical, 4)
	            .padding(.horizontal, 4)
	            .background(
	                RoundedRectangle(cornerRadius: 8, style: .continuous)
	                    .fill(palette.background.opacity(0.45))
	            )
	            .overlay(
	                RoundedRectangle(cornerRadius: 8, style: .continuous)
	                    .stroke(palette.punctuation.opacity(0.25), lineWidth: 1)
	            )
	        }
	    }

	    @ViewBuilder
	    private func wordWrapToggle(title: String, value: Binding<Bool>, description: String) -> some View {
	        HStack(spacing: 12) {
	            VStack(alignment: .leading, spacing: 2) {
	                Text(title)
	                    .font(.themedUI(size: 12))
	                    .fontWeight(.semibold)
	                    .foregroundColor(palette.text)

	                Text(description)
	                    .font(.themedUI(size: 11))
	                    .foregroundColor(palette.muted)
	                    .lineLimit(nil)
	                    .multilineTextAlignment(.leading)
	            }

	            Spacer()

	            Toggle("", isOn: value)
	                .labelsHidden()
	        }
	        .padding(.vertical, 8)
	        .padding(.horizontal, 12)
	        .background(
	            RoundedRectangle(cornerRadius: 8)
	                .fill(palette.background.opacity(0.45))
	        )
	        .overlay(
	            RoundedRectangle(cornerRadius: 8)
	                .stroke(palette.punctuation.opacity(0.25), lineWidth: 1)
	        )
	    }
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
                .tint(palette.accent)
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
