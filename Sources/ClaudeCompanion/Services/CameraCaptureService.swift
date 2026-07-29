import AVFoundation
import Foundation

enum CameraCaptureError: LocalizedError {
    case accessDenied
    case noCamera
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Camera access is off. Turn it on in System Settings › Privacy & Security › Camera."
        case .noCamera:
            "No camera is available."
        case .failed(let reason):
            "The photo couldn't be taken: \(reason)"
        }
    }
}

/// Takes a single still from the built-in camera and hands back an attachment.
///
/// There is no viewfinder: the panel is a transient surface and putting a live
/// preview in it would mean holding the camera open for as long as it is on
/// screen. The session is opened, allowed to settle, fired once, and closed.
@MainActor
final class CameraCaptureService {

    /// Time given to auto-exposure and white balance before the shutter fires.
    /// Without it the first frame off a Mac's camera is reliably black.
    private static let warmUpNanoseconds: UInt64 = 700_000_000

    private var delegate: PhotoCaptureDelegate?

    func takePhoto() async throws -> Attachment {
        guard await Self.requestAccess() else { throw CameraCaptureError.accessDenied }
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraCaptureError.noCamera
        }

        let session = AVCaptureSession()
        session.sessionPreset = .photo

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraCaptureError.failed(error.localizedDescription)
        }

        let output = AVCapturePhotoOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CameraCaptureError.noCamera
        }
        session.addInput(input)
        session.addOutput(output)

        // startRunning blocks until the device is configured, so it never runs
        // on the main actor.
        await Self.start(session)
        defer { Self.stop(session) }

        try? await Task.sleep(nanoseconds: Self.warmUpNanoseconds)

        let data = try await capture(with: output)

        guard let attachment = AttachmentLoader.makeImageAttachment(
            from: data,
            filename: "Photo \(Self.stamp()).png"
        ) else {
            throw CameraCaptureError.failed("the image couldn't be encoded")
        }

        return attachment
    }

    // MARK: - Shutter

    private func capture(with output: AVCapturePhotoOutput) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            // The delegate is held here rather than passed along, because
            // AVFoundation keeps only an unowned reference to it.
            let delegate = PhotoCaptureDelegate { [weak self] result in
                self?.delegate = nil
                continuation.resume(with: result)
            }
            self.delegate = delegate
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    // MARK: - Session lifecycle

    private static func start(_ session: AVCaptureSession) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                continuation.resume()
            }
        }
    }

    private static func stop(_ session: AVCaptureSession) {
        DispatchQueue.global(qos: .utility).async {
            session.stopRunning()
        }
    }

    // MARK: - Permission

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
    }
}

/// Bridges the one-shot delegate callback back into `async`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(CameraCaptureError.failed(error.localizedDescription)))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraCaptureError.failed("no image data")))
            return
        }
        completion(.success(data))
    }
}
