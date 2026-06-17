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

/// One flattened row in the virtualized tree.
private struct JSONRow: Identifiable {
    enum Kind { case node, loadMore, truncatedNote }
    let id: String
    let node: JSONNode
    let depth: Int
    let kind: Kind
}

/// Virtualized JSON tree: flattens the expanded nodes into a single LazyVStack so
/// SwiftUI only instantiates the rows in (or near) the viewport, instead of the
/// previous recursive VStacks that materialized every expanded row at once.
struct JSONTreeView: View {
    let rootNode: JSONNode
    @ObservedObject var viewModel: JSONViewModel
    let palette: ThemePalette
    @ObservedObject var themeSettings: ThemeSettings

    private var wordWrap: Bool { themeSettings.formattedJSONWordWrap }

    /// Flattens the currently-expanded tree into the linear row list to render.
    private var rows: [JSONRow] {
        var result: [JSONRow] = []
        appendRows(for: rootNode, depth: 0, into: &result)
        return result
    }

    private func appendRows(for node: JSONNode, depth: Int, into result: inout [JSONRow]) {
        result.append(JSONRow(id: node.id.uuidString, node: node, depth: depth, kind: .node))
        guard viewModel.isExpanded(node.id), !node.children.isEmpty, depth < 50 else { return }

        let total = node.children.count
        let visible = node.isFullyLoaded ? total : min(viewModel.visibleChildCount(for: node.id), total)
        for child in node.children.prefix(visible) {
            appendRows(for: child, depth: depth + 1, into: &result)
        }
        if !node.isFullyLoaded && total > visible {
            result.append(JSONRow(id: node.id.uuidString + "#more", node: node, depth: depth + 1, kind: .loadMore))
        }
        if node.truncatedArrayTotal != nil {
            result.append(JSONRow(id: node.id.uuidString + "#trunc", node: node, depth: depth + 1, kind: .truncatedNote))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let axes: Axis.Set = wordWrap ? .vertical : [.vertical, .horizontal]
            let scrollIndicatorGutter: CGFloat = 44
            let endGutter: CGFloat = wordWrap ? 24 : 96
            ScrollViewReader { proxy in
                ScrollView(axes, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            rowView(row)
                                .padding(.leading, CGFloat(row.depth) * 16)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .padding(.trailing, scrollIndicatorGutter + endGutter)
                    .padding(.bottom, wordWrap ? 12 : (scrollIndicatorGutter + endGutter))
                    .frame(minWidth: geometry.size.width, alignment: .topLeading)
                }
                .onChange(of: viewModel.formattedSearchFocusedID) { _, targetID in
                    guard let targetID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: JSONRow) -> some View {
        switch row.kind {
        case .node:
            JSONNodeView(
                node: row.node,
                palette: palette,
                wordWrap: wordWrap,
                isExpanded: viewModel.isExpanded(row.node.id),
                isHighlighted: viewModel.formattedSearchMatches.contains(row.node.id),
                isFocused: viewModel.formattedSearchFocusedID == row.node.id,
                onToggle: { viewModel.toggleExpansion(for: row.node.id) }
            )
            .equatable()
            .id(row.node.id)
        case .loadMore:
            loadMoreButton(for: row.node)
        case .truncatedNote:
            truncatedArrayNote(for: row.node)
        }
    }

    @ViewBuilder
    private func loadMoreButton(for node: JSONNode) -> some View {
        let total = node.children.count
        let visible = viewModel.visibleChildCount(for: node.id)
        Button {
            viewModel.revealMoreChildren(for: node.id, total: total)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle.fill").foregroundColor(palette.accent)
                Text("Show \(min(50, total - visible)) more...").foregroundColor(palette.accent)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func truncatedArrayNote(for node: JSONNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(palette.muted)
            Text("Showing first \(node.children.count) of \(node.truncatedArrayTotal ?? node.children.count) elements — array truncated for performance.")
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

