import AVFoundation
import Foundation
import OSLog
import Speech

/// Live dictation into the composer.
///
/// Partial results are written back continuously, so the text appears as the
/// user speaks rather than in one lump at the end. Whatever was already typed
/// is preserved: transcription is appended to the draft as it stood when the
/// mic was switched on.
@MainActor
final class DictationService: ObservableObject {

    @Published private(set) var isRecording = false

    /// Receives the full draft text (original + transcript) on every update.
    var onTranscript: ((String) -> Void)?
    /// Receives a user-facing reason dictation couldn't run or stopped early.
    var onError: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// The composer's contents when recording started.
    private var baseText = ""

    private let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "Dictation")

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func toggle(baseText: String) {
        if isRecording {
            stop()
        } else {
            Task { await start(baseText: baseText) }
        }
    }

    // MARK: - Recording

    func start(baseText: String) async {
        guard !isRecording else { return }

        guard await Self.requestSpeechAccess() else {
            onError?("Speech recognition access is off. Turn it on in System Settings › Privacy & Security › Speech Recognition.")
            return
        }
        guard await Self.requestMicrophoneAccess() else {
            onError?("Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            onError?("Dictation isn't available right now.")
            return
        }

        self.baseText = baseText

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            onError?("No microphone input is available.")
            reset()
            return
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            // Called on the audio thread; appending is the only thing done here.
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            logger.error("Audio engine failed: \(error.localizedDescription, privacy: .public)")
            onError?("The microphone couldn't be started.")
            reset()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.emit(result.bestTranscription.formattedString)
                }

                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }

        isRecording = true
    }

    func stop() {
        guard isRecording || request != nil else { return }
        reset()
        isRecording = false
    }

    // MARK: - Internals

    private func emit(_ transcript: String) {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }

        let existing = baseText.trimmingCharacters(in: .whitespacesAndNewlines)
        onTranscript?(existing.isEmpty ? spoken : existing + " " + spoken)
    }

    private func reset() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    // MARK: - Permissions

    private static func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
