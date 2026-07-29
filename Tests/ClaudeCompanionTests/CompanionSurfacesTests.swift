import XCTest
@testable import ClaudeCompanion

/// Covers the pure logic behind the surfaces added with the redesign: the
/// "Work With" picker's ordering and search, and the text read-aloud speaks.
final class CompanionSurfacesTests: XCTestCase {

    private func makeApp(
        _ name: String,
        isRunning: Bool = false,
        pid: pid_t? = nil
    ) -> CompanionApp {
        CompanionApp(
            id: "com.example.\(name.lowercased())",
            name: name,
            bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            isRunning: isRunning,
            processIdentifier: pid
        )
    }

    // MARK: - Picker ordering

    /// Running apps are the ones the user is plausibly asking about, so they
    /// sit at the top regardless of name.
    func testRunningAppsSortAboveInstalledOnes() {
        let apps = [
            makeApp("Zed", isRunning: true, pid: 42),
            makeApp("Automator"),
            makeApp("Notes", isRunning: true, pid: 7),
            makeApp("Books")
        ]

        let sorted = apps.sorted(by: AppDirectory.pickerOrder).map(\.name)
        XCTAssertEqual(sorted, ["Notes", "Zed", "Automator", "Books"])
    }

    func testOrderingIsAlphabeticalWithinEachGroup() {
        let apps = [makeApp("Xcode"), makeApp("Calendar"), makeApp("mail")]
        let sorted = apps.sorted(by: AppDirectory.pickerOrder).map(\.name)
        XCTAssertEqual(sorted, ["Calendar", "mail", "Xcode"])
    }

    // MARK: - Picker search

    func testSearchIgnoresCaseAndDiacritics() {
        let apps = [makeApp("Préférences"), makeApp("Terminal")]

        XCTAssertEqual(AppDirectory.filter(apps, query: "prefer").map(\.name), ["Préférences"])
        XCTAssertEqual(AppDirectory.filter(apps, query: "TERM").map(\.name), ["Terminal"])
    }

    func testAnEmptyQueryKeepsEveryApp() {
        let apps = [makeApp("Terminal"), makeApp("Notes")]
        XCTAssertEqual(AppDirectory.filter(apps, query: "   ").count, 2)
    }

    // MARK: - Running state

    func testOnlyNotRunningAppsCarryAStateLabel() {
        XCTAssertEqual(makeApp("CLion").runningStateLabel, "Not running")
        XCTAssertNil(makeApp("Notes", isRunning: true, pid: 1).runningStateLabel)
    }

    // MARK: - Read aloud

    /// A spoken answer shouldn't be a recital of punctuation.
    func testMarkdownSyntaxIsNotSpoken() {
        let spoken = SpeechReader.spokenText(from: "## Heading\n- **bold** item\n> quoted")
        XCTAssertEqual(spoken, "Heading\nbold item\nquoted")
    }

    func testLinkTextIsKeptButTheURLIsNot() {
        let spoken = SpeechReader.spokenText(from: "See [the docs](https://example.com/x) now")
        XCTAssertEqual(spoken, "See the docs now")
    }

    /// Reading a shell script out loud is noise, so fenced code is dropped.
    func testFencedCodeIsDropped() {
        let markdown = """
        Run this:

        ```sh
        rm -rf ./build
        ```

        Then retry.
        """

        let spoken = SpeechReader.spokenText(from: markdown)
        XCTAssertFalse(spoken.contains("rm -rf"))
        XCTAssertTrue(spoken.contains("Run this:"))
        XCTAssertTrue(spoken.contains("Then retry."))
    }
}
