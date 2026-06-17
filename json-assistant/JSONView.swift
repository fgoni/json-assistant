import SwiftUI
import Foundation
import os
import AppKit

#if DEBUG
/// Counts JSONNodeView body evaluations so benchmarks can measure how many rows
/// actually re-render on a state change. Main-thread only.
enum JSONRowRenderProbe {
    nonisolated(unsafe) static var bodyCount = 0
    static func reset() { bodyCount = 0 }
    static func tick() { bodyCount += 1 }
}
#endif

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
            JSONNodeView(
                node: node,
                palette: palette,
                wordWrap: wordWrap,
                isExpanded: viewModel.isExpanded(node.id),
                isHighlighted: viewModel.formattedSearchMatches.contains(node.id),
                isFocused: viewModel.formattedSearchFocusedID == node.id,
                onToggle: { viewModel.toggleExpansion(for: node.id) }
            )
            .equatable()

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

                    // Note when this array was truncated by the parser's element cap.
                    if let total = node.truncatedArrayTotal {
                        truncatedArrayNote(shown: node.children.count, total: total)
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

    @ViewBuilder
    private func truncatedArrayNote(shown: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(palette.muted)
            Text("Showing first \(shown) of \(total) elements — array truncated for performance.")
                .foregroundColor(palette.muted)
                .formattedLineWrap(wordWrap)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}


struct JSONNodeView: View, Equatable {
    let node: JSONNode
    let palette: ThemePalette
    let wordWrap: Bool
    let isExpanded: Bool
    let isHighlighted: Bool
    let isFocused: Bool
    let onToggle: () -> Void

    // Equatable so SwiftUI can skip re-rendering a row whose inputs are unchanged.
    // The node is immutable after construction, so identity captures its content.
    static func == (lhs: JSONNodeView, rhs: JSONNodeView) -> Bool {
        lhs.node === rhs.node
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isHighlighted == rhs.isHighlighted
            && lhs.isFocused == rhs.isFocused
            && lhs.wordWrap == rhs.wordWrap
            && lhs.palette == rhs.palette
    }

    var body: some View {
#if DEBUG
        let _ = JSONRowRenderProbe.tick()
#endif
        let isNodeExpanded = isExpanded

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
                    onToggle()
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
        .contextMenu {
            Button("Copy Path") { copyToClipboard(node.path) }
            Button("Copy Value") { copyToClipboard(OrderedJSONFormatter.prettyPrinted(node.value)) }
            if !node.isRoot {
                Button("Copy Key") { copyToClipboard(node.key) }
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
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

