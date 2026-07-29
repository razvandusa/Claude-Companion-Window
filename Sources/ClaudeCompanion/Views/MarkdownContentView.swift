import SwiftUI

/// Renders assistant output as markdown.
///
/// Block structure comes from ``MarkdownParser``; inline emphasis, links and
/// code spans are handled by `AttributedString`'s markdown parser.
struct MarkdownContentView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] { MarkdownParser.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let text):
            Text(InlineMarkdown.attributed(text))
                .font(headingFont(for: level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 2)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(_, let text):
            Text(InlineMarkdown.attributed(text))
                .font(Theme.Fonts.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .code(_, let language, let source, _):
            CodeBlockView(source: source, language: language)

        case .bulletList(_, let items), .numberedList(_, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.subtleText)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(InlineMarkdown.attributed(item.text))
                            .font(Theme.Fonts.body)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.depth) * 14)
                }
            }

        case .quote(_, let text):
            Text(InlineMarkdown.attributed(text))
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.subtleText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.Colors.separator)
                        .frame(width: 3)
                }

        case .table(_, let header, let rows):
            MarkdownTableView(header: header, rows: rows)

        case .divider:
            Divider().overlay(Theme.Colors.separator)
        }
    }

    /// Semantic styles so headings scale with Dynamic Type.
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .system(.title2).weight(.semibold)
        case 2: .system(.title3).weight(.semibold)
        case 3: .system(.headline)
        default: .system(.subheadline).weight(.semibold)
        }
    }
}

/// Markdown tables, laid out as a grid that scrolls sideways when needed.
private struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(header.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        Text(InlineMarkdown.attributed(header[safe: column] ?? ""))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                Divider().gridCellColumns(columnCount)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            Text(InlineMarkdown.attributed(row[safe: column] ?? ""))
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(10)
        }
        .background(
            Theme.Colors.codeBackground,
            in: RoundedRectangle(cornerRadius: Theme.Metrics.codeCornerRadius, style: .continuous)
        )
    }
}

/// Inline markdown conversion with code-span styling applied afterwards.
enum InlineMarkdown {
    static func attributed(_ text: String) -> AttributedString {
        var result: AttributedString
        do {
            result = try AttributedString(
                markdown: text,
                options: .init(
                    // Preserves the soft line breaks the model emits inside a
                    // paragraph instead of collapsing them.
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return AttributedString(text)
        }

        // Collect first, then mutate — mutating while iterating `runs` invalidates it.
        let codeRanges = result.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.inlinePresentationIntent?.contains(.code) == true else { return nil }
            return run.range
        }

        for range in codeRanges {
            result[range].font = .system(size: 12, design: .monospaced)
            result[range].foregroundColor = Color(nsColor: .systemPink)
        }

        return result
    }
}

extension Array {
    /// Bounds-checked subscript, used where a markdown table row is short.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
