import XCTest
import SwiftUI
@testable import ClaudeCompanion

final class SyntaxHighlighterTests: XCTestCase {

    func testUnknownLanguageIsLeftPlain() {
        let attributed = SyntaxHighlighter.highlight("let x = 1", language: "brainfuck")
        let colors = Set(attributed.runs.map { $0.foregroundColor })
        XCTAssertEqual(colors, [SyntaxHighlighter.Token.plain.color])
    }

    func testNilLanguageIsLeftPlain() {
        let attributed = SyntaxHighlighter.highlight("SELECT 1", language: nil)
        let colors = Set(attributed.runs.map { $0.foregroundColor })
        XCTAssertEqual(colors, [SyntaxHighlighter.Token.plain.color])
    }

    func testKeywordsAreColored() {
        let attributed = SyntaxHighlighter.highlight("func greet() {}", language: "swift")
        XCTAssertEqual(color(of: "func", in: attributed), SyntaxHighlighter.Token.keyword.color)
    }

    /// Highest-priority rules claim their characters first, so a keyword inside
    /// a string literal stays string-colored.
    func testKeywordInsideAStringIsNotHighlightedAsAKeyword() {
        let attributed = SyntaxHighlighter.highlight("let s = \"func\"", language: "swift")
        XCTAssertEqual(color(of: "\"func\"", in: attributed), SyntaxHighlighter.Token.string.color)
    }

    func testKeywordInsideACommentIsNotHighlightedAsAKeyword() {
        let attributed = SyntaxHighlighter.highlight("// func here", language: "swift")
        XCTAssertEqual(color(of: "// func here", in: attributed), SyntaxHighlighter.Token.comment.color)
    }

    func testNumbersAreColored() {
        let attributed = SyntaxHighlighter.highlight("x = 42", language: "python")
        XCTAssertEqual(color(of: "42", in: attributed), SyntaxHighlighter.Token.number.color)
    }

    func testTypesAreColored() {
        let attributed = SyntaxHighlighter.highlight("var name: String", language: "swift")
        XCTAssertEqual(color(of: "String", in: attributed), SyntaxHighlighter.Token.type.color)
    }

    func testAliasesResolveToTheSameGrammar() {
        for alias in ["ts", "tsx", "javascript", "js"] {
            let attributed = SyntaxHighlighter.highlight("const x = 1", language: alias)
            XCTAssertEqual(
                color(of: "const", in: attributed),
                SyntaxHighlighter.Token.keyword.color,
                "alias \(alias) should highlight keywords"
            )
        }
    }

    func testSqlKeywordsAreCaseInsensitive() {
        let attributed = SyntaxHighlighter.highlight("select * from t", language: "sql")
        XCTAssertEqual(color(of: "select", in: attributed), SyntaxHighlighter.Token.keyword.color)
    }

    func testHighlightingPreservesTheSourceText() {
        let source = "def f(x):\n    return x * 2  # doubles\n"
        let attributed = SyntaxHighlighter.highlight(source, language: "python")
        XCTAssertEqual(String(attributed.characters), source)
    }

    func testDisplayNameFallsBackToText() {
        XCTAssertEqual(SyntaxHighlighter.displayName(for: nil), "text")
        XCTAssertEqual(SyntaxHighlighter.displayName(for: ""), "text")
        XCTAssertEqual(SyntaxHighlighter.displayName(for: "PY"), "python")
        XCTAssertEqual(SyntaxHighlighter.displayName(for: "zig"), "zig")
    }

    // MARK: - Helpers

    /// Color applied to the first occurrence of `substring`.
    private func color(of substring: String, in attributed: AttributedString) -> Color? {
        let text = String(attributed.characters)
        guard let found = text.range(of: substring),
              let range = Range(found, in: attributed)
        else {
            XCTFail("\(substring) not found in \(text)")
            return nil
        }
        return attributed[range].runs.first?.foregroundColor
    }
}
