import AVFoundation
import CoreGraphics
import OSLog
import Speech

/// Asks for everything the app needs, once, on first launch.
///
/// The alternative — asking at the moment each feature is first used — means a
/// system dialog interrupting the thing the user was trying to do, and it made
/// Screen Recording in particular look like it was being asked for repeatedly.
@MainActor
enum PermissionsService {

    private static let logger = Logger(subsystem: AppInfo.bundleIdentifier, category: "Permissions")

    /// What the app can ask for, in the order the prompts appear.
    enum Permission: String, CaseIterable {
        case screenRecording
        case microphone
        case speechRecognition
        case camera

        var label: String {
            switch self {
            case .screenRecording: "Screen Recording"
            case .microphone: "Microphone"
            case .speechRecognition: "Speech Recognition"
            case .camera: "Camera"
            }
        }
    }

    /// Runs the prompts one after another.
    ///
    /// Sequential on purpose: macOS queues these dialogs, and firing them
    /// concurrently stacks four of them on the user at once.
    static func requestAll() async {
        for permission in Permission.allCases {
            let granted = await request(permission)
            logger.log("\(permission.label, privacy: .public): \(granted ? "granted" : "not granted", privacy: .public)")
        }
    }

    /// Whether a permission has already been decided, so first launch can skip
    /// prompts the user has answered before.
    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .screenRecording:
            CGPreflightScreenCaptureAccess()
        case .microphone:
            AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .camera:
            AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .speechRecognition:
            SFSpeechRecognizer.authorizationStatus() == .authorized
        }
    }

    private static func request(_ permission: Permission) async -> Bool {
        switch permission {
        case .screenRecording:
            // Synchronous, and the only one macOS won't re-prompt for: once
            // denied it can only be changed in System Settings.
            guard !CGPreflightScreenCaptureAccess() else { return true }
            CGRequestScreenCaptureAccess()
            return CGPreflightScreenCaptureAccess()

        case .microphone:
            return await requestCapture(.audio)

        case .camera:
            return await requestCapture(.video)

        case .speechRecognition:
            guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
                return SFSpeechRecognizer.authorizationStatus() == .authorized
            }
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    private static func requestCapture(_ media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }
}
