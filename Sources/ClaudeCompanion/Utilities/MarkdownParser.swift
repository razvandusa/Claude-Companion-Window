import Foundation

/// A renderable chunk of markdown.
///
/// Block structure is parsed here; inline emphasis, links and code spans are
/// left to `AttributedString(markdown:)` at render time.
enum MarkdownBlock: Identifiable, Equatable {
    case heading(id: Int, level: Int, text: String)
    case paragraph(id: Int, text: String)
    case code(id: Int, language: String?, source: String, isComplete: Bool)
    case bulletList(id: Int, items: [ListItem])
    case numberedList(id: Int, items: [ListItem])
    case quote(id: Int, text: String)
    case table(id: Int, header: [String], rows: [[String]])
    case divider(id: Int)

    struct ListItem: Identifiable, Equatable {
        let id: Int
        /// Nesting depth, zero-based.
        let depth: Int
        /// Marker shown before the text — a bullet glyph or "1." style number.
        let marker: String
        let text: String
    }

    var id: Int {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .code(let id, _, _, _),
             .bulletList(let id, _),
             .numberedList(let id, _),
             .quote(let id, _),
             .table(let id, _, _),
             .divider(let id):
            return id
        }
    }
}

/// Line-oriented markdown block parser.
///
/// Written for streaming: a fenced code block that hasn't been closed yet is
/// still emitted (flagged incomplete) so code renders as it arrives instead of
/// flashing as raw text and then reflowing.
enum MarkdownParser {

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var identifier = 0
        func nextID() -> Int { defer { identifier += 1 }; return identifier }

        let lines = markdown.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if let fence = CodeFence(line: trimmed) {
                var source: [String] = []
                var isComplete = false
                index += 1

                while index < lines.count {
                    let candidate = lines[index]
                    if CodeFence.isClosing(candidate.trimmingCharacters(in: .whitespaces), matching: fence) {
                        isComplete = true
                        index += 1
                        break
                    }
                    source.append(candidate)
                    index += 1
                }

                blocks.append(.code(
                    id: nextID(),
                    language: fence.language,
                    source: source.joined(separator: "\n"),
                    isComplete: isComplete
                ))
                continue
            }

            // Blank line
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Horizontal rule
            if isDivider(trimmed) {
                blocks.append(.divider(id: nextID()))
                index += 1
                continue
            }

            // Heading
            if let heading = parseHeading(trimmed) {
                blocks.append(.heading(id: nextID(), level: heading.level, text: heading.text))
                index += 1
                continue
            }

            // Table — needs a delimiter row directly beneath the header
            if trimmed.contains("|"),
               index + 1 < lines.count,
               isTableDelimiter(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                let header = splitTableRow(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|"), !candidate.isEmpty else { break }
                    rows.append(splitTableRow(candidate))
                    index += 1
                }
                blocks.append(.table(id: nextID(), header: header, rows: rows))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(
                        candidate.dropFirst()
                            .trimmingCharacters(in: CharacterSet(charactersIn: " "))
                    )
                    index += 1
                }
                blocks.append(.quote(id: nextID(), text: quoted.joined(separator: "\n")))
                continue
            }

            // Lists
            if let first = ListLine(line: line) {
                var items: [MarkdownBlock.ListItem] = []
                var itemIdentifier = 0
                let ordered = first.isOrdered

                while index < lines.count, let entry = ListLine(line: lines[index]),
                      entry.isOrdered == ordered {
                    items.append(MarkdownBlock.ListItem(
                        id: itemIdentifier,
                        depth: entry.depth,
                        marker: entry.marker,
                        text: entry.text
                    ))
                    itemIdentifier += 1
                    index += 1
                }

                blocks.append(
                    ordered
                        ? .numberedList(id: nextID(), items: items)
                        : .bulletList(id: nextID(), items: items)
                )
                continue
            }

            // Paragraph — consume until a blank line or a line that starts a
            // different block.
            var paragraph: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty
                    || CodeFence(line: candidateTrimmed) != nil
                    || parseHeading(candidateTrimmed) != nil
                    || candidateTrimmed.hasPrefix(">")
                    || ListLine(line: candidate) != nil
                    || isDivider(candidateTrimmed) {
                    break
                }
                paragraph.append(candidateTrimmed)
                index += 1
            }

            if !paragraph.isEmpty {
                blocks.append(.paragraph(id: nextID(), text: paragraph.joined(separator: "\n")))
            }
        }

        return blocks
    }

    // MARK: - Line classifiers

    private struct CodeFence {
        let marker: Character
        let length: Int
        let language: String?

        init?(line: String) {
            guard let first = line.first, first == "`" || first == "~" else { return nil }
            let run = line.prefix { $0 == first }
            guard run.count >= 3 else { return nil }

            marker = first
            length = run.count
            let info = line.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
            language = info.isEmpty ? nil : info.components(separatedBy: .whitespaces).first
        }

        static func isClosing(_ line: String, matching fence: CodeFence) -> Bool {
            guard let first = line.first, first == fence.marker else { return false }
            let run = line.prefix { $0 == fence.marker }
            return run.count >= fence.length
                && line.dropFirst(run.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private struct ListLine {
        let depth: Int
        let marker: String
        let text: String
        let isOrdered: Bool

        init?(line: String) {
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            let indentWidth = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let body = line.dropFirst(leading.count)

            if let match = body.firstMatch(ofUnorderedMarker: true) {
                depth = indentWidth / 2
                marker = "•"
                text = String(body.dropFirst(match)).trimmingCharacters(in: .whitespaces)
                isOrdered = false
                return
            }

            // Ordered: digits followed by '.' or ')' then whitespace
            let digits = body.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let rest = body.dropFirst(digits.count)
            guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
            let afterSeparator = rest.dropFirst()
            guard let space = afterSeparator.first, space == " " || space == "\t" else { return nil }

            depth = indentWidth / 2
            marker = "\(digits)."
            text = String(afterSeparator).trimmingCharacters(in: .whitespaces)
            isOrdered = true
        }
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let remainder = line.dropFirst(hashes.count)
        guard remainder.first == " " else { return nil }
        return (hashes.count, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("-"), line.contains("|") else { return false }
        let allowed = CharacterSet(charactersIn: "-|: ")
        return line.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func splitTableRow(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

private extension Substring {
    /// Returns the length of a leading unordered-list marker ("- ", "* ", "+ ").
    func firstMatch(ofUnorderedMarker: Bool) -> Int? {
        guard let first = first, first == "-" || first == "*" || first == "+" else { return nil }
        let rest = dropFirst()
        guard let next = rest.first, next == " " || next == "\t" else { return nil }
        return 1
    }
}
