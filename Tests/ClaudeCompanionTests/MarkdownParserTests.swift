import XCTest
@testable import ClaudeCompanion

final class MarkdownParserTests: XCTestCase {

    func testParsesHeadingsAtEachLevel() {
        let blocks = MarkdownParser.parse("# One\n\n### Three")

        guard case .heading(_, let firstLevel, let firstText) = blocks[0],
              case .heading(_, let secondLevel, let secondText) = blocks[1]
        else { return XCTFail("Expected two headings, got \(blocks)") }

        XCTAssertEqual(firstLevel, 1)
        XCTAssertEqual(firstText, "One")
        XCTAssertEqual(secondLevel, 3)
        XCTAssertEqual(secondText, "Three")
    }

    func testHashWithoutSpaceIsNotAHeading() {
        let blocks = MarkdownParser.parse("#hashtag")
        guard case .paragraph(_, let text) = blocks[0] else {
            return XCTFail("Expected a paragraph, got \(blocks)")
        }
        XCTAssertEqual(text, "#hashtag")
    }

    func testParsesFencedCodeWithLanguage() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")

        guard case .code(_, let language, let source, let isComplete) = blocks[0] else {
            return XCTFail("Expected a code block, got \(blocks)")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(source, "let x = 1")
        XCTAssertTrue(isComplete)
    }

    /// While a response streams the closing fence hasn't arrived yet; the block
    /// still has to render so code doesn't flash as raw text.
    func testUnterminatedFenceStillProducesACodeBlock() {
        let blocks = MarkdownParser.parse("```python\nprint(1)")

        guard case .code(_, let language, let source, let isComplete) = blocks[0] else {
            return XCTFail("Expected a code block, got \(blocks)")
        }
        XCTAssertEqual(language, "python")
        XCTAssertEqual(source, "print(1)")
        XCTAssertFalse(isComplete)
    }

    func testFenceContentIsNotReparsedAsMarkdown() {
        let blocks = MarkdownParser.parse("```\n# not a heading\n- not a list\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .code(_, _, let source, _) = blocks[0] else {
            return XCTFail("Expected a single code block, got \(blocks)")
        }
        XCTAssertEqual(source, "# not a heading\n- not a list")
    }

    func testParsesBulletAndNumberedLists() {
        let bullets = MarkdownParser.parse("- one\n- two")
        guard case .bulletList(_, let bulletItems) = bullets[0] else {
            return XCTFail("Expected a bullet list, got \(bullets)")
        }
        XCTAssertEqual(bulletItems.map(\.text), ["one", "two"])

        let numbers = MarkdownParser.parse("1. first\n2. second")
        guard case .numberedList(_, let numberedItems) = numbers[0] else {
            return XCTFail("Expected a numbered list, got \(numbers)")
        }
        XCTAssertEqual(numberedItems.map(\.marker), ["1.", "2."])
    }

    func testNestedListItemsCarryDepth() {
        let blocks = MarkdownParser.parse("- top\n  - nested")
        guard case .bulletList(_, let items) = blocks[0] else {
            return XCTFail("Expected a bullet list, got \(blocks)")
        }
        XCTAssertEqual(items[0].depth, 0)
        XCTAssertEqual(items[1].depth, 1)
    }

    func testParsesBlockquote() {
        let blocks = MarkdownParser.parse("> quoted line\n> second line")
        guard case .quote(_, let text) = blocks[0] else {
            return XCTFail("Expected a quote, got \(blocks)")
        }
        XCTAssertEqual(text, "quoted line\nsecond line")
    }

    func testParsesTableWithHeaderAndRows() {
        let markdown = """
        | Name | Count |
        | --- | ----- |
        | a | 1 |
        | b | 2 |
        """
        let blocks = MarkdownParser.parse(markdown)

        guard case .table(_, let header, let rows) = blocks[0] else {
            return XCTFail("Expected a table, got \(blocks)")
        }
        XCTAssertEqual(header, ["Name", "Count"])
        XCTAssertEqual(rows, [["a", "1"], ["b", "2"]])
    }

    /// A pipe without a delimiter row underneath is just prose.
    func testPipeWithoutDelimiterRowIsAParagraph() {
        let blocks = MarkdownParser.parse("a | b")
        guard case .paragraph = blocks[0] else {
            return XCTFail("Expected a paragraph, got \(blocks)")
        }
    }

    func testParsesDivider() {
        let blocks = MarkdownParser.parse("---")
        guard case .divider = blocks[0] else {
            return XCTFail("Expected a divider, got \(blocks)")
        }
    }

    func testParagraphStopsAtTheNextBlock() {
        let blocks = MarkdownParser.parse("intro text\n```\ncode\n```")
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(_, let text) = blocks[0], case .code = blocks[1] else {
            return XCTFail("Expected paragraph then code, got \(blocks)")
        }
        XCTAssertEqual(text, "intro text")
    }

    func testEmptyInputProducesNoBlocks() {
        XCTAssertTrue(MarkdownParser.parse("").isEmpty)
        XCTAssertTrue(MarkdownParser.parse("\n\n   \n").isEmpty)
    }

    func testBlockIdentifiersAreUnique() {
        let blocks = MarkdownParser.parse("# a\n\ntext\n\n- item\n\n> quote")
        XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count)
    }
}
