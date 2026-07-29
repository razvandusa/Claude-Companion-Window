import AVFoundation
import Foundation

/// Reads an assistant turn aloud.
///
/// Tracks which message is speaking so the action row can flip its icon to a
/// stop control, and so starting a second message cancels the first.
@MainActor
final class SpeechReader: NSObject, ObservableObject {

    @Published private(set) var speakingMessageID: UUID?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func isSpeaking(_ messageID: UUID) -> Bool {
        speakingMessageID == messageID
    }

    /// Starts reading, or stops if this message is already being read.
    func toggle(_ markdown: String, messageID: UUID) {
        guard speakingMessageID != messageID else {
            stop()
            return
        }

        stop()

        let spoken = Self.spokenText(from: markdown)
        guard !spoken.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingMessageID = messageID
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingMessageID = nil
    }

    /// Strips the markdown that would otherwise be read out as punctuation.
    ///
    /// Fenced code is dropped entirely rather than spelled out — a read-aloud
    /// of a shell script is noise, not information.
    nonisolated static func spokenText(from markdown: String) -> String {
        var lines: [String] = []
        var isInsideFence = false

        for line in markdown.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInsideFence.toggle()
                continue
            }
            guard !isInsideFence else { continue }
            lines.append(strip(line))
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func strip(_ line: String) -> String {
        var text = line

        // Leading block syntax: headings, quotes, list bullets.
        text = text.replacingOccurrences(
            of: "^\\s*(#{1,6}\\s+|>\\s+|[-*+]\\s+|\\d+\\.\\s+)",
            with: "",
            options: .regularExpression
        )

        // Inline emphasis, inline code, and link syntax — keeping link text.
        text = text.replacingOccurrences(
            of: "\\[([^\\]]*)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "[*_`~]",
            with: "",
            options: .regularExpression
        )

        return text
    }
}

extension SpeechReader: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.speakingMessageID = nil }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.speakingMessageID = nil }
    }
}
