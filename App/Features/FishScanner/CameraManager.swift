import AVFoundation
import Foundation
import Observation

enum CameraAccessStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

enum CameraPhotoError: Error, Equatable, Sendable {
    case sessionNotReady
    case captureFailed
}

protocol CameraAuthorizationManaging: Sendable {
    func authorizationStatus() -> CameraAccessStatus
    func requestAccess() async -> CameraAccessStatus
}

protocol CameraSession: AnyObject, Sendable {
    var isRunning: Bool { get }
    var previewSession: AVCaptureSession? { get }
    @discardableResult
    func configureSession() -> Bool
    func startRunning()
    func stopRunning()
}

protocol CameraPhotoOutputting: AnyObject, Sendable {
    func capturePhoto(onResult: @escaping @Sendable (Result<Data, CameraPhotoError>) -> Void)
}

struct SystemCameraAuthorization: CameraAuthorizationManaging {
    func authorizationStatus() -> CameraAccessStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async -> CameraAccessStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

extension SystemCameraDevice: @unchecked Sendable {}

final class SystemCameraDevice: CameraSession, CameraPhotoOutputting {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private let delegateLock = NSLock()
    private var pendingPhotoDelegates: Set<PhotoCaptureDelegate> = []

    var previewSession: AVCaptureSession? {
        captureSession
    }

    var isRunning: Bool {
        captureSession.isRunning
    }

    @discardableResult
    func configureSession() -> Bool {
        guard !isConfigured else { return true }
        captureSession.sessionPreset = .photo
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            return false
        }
        captureSession.addInput(input)
        guard captureSession.canAddOutput(photoOutput) else {
            return false
        }
        captureSession.addOutput(photoOutput)
        isConfigured = true
        return true
    }

    func startRunning() {
        captureSession.startRunning()
    }

    func stopRunning() {
        captureSession.stopRunning()
    }

    func capturePhoto(onResult: @escaping @Sendable (Result<Data, CameraPhotoError>) -> Void) {
        guard isConfigured else {
            onResult(.failure(.sessionNotReady))
            return
        }
        let delegate = PhotoCaptureDelegate(owner: self, onResult: onResult)
        delegateLock.lock()
        pendingPhotoDelegates.insert(delegate)
        delegateLock.unlock()
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
    }

    fileprivate func didCompleteCapture(_ delegate: PhotoCaptureDelegate) {
        delegateLock.lock()
        pendingPhotoDelegates.remove(delegate)
        delegateLock.unlock()
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let onResult: @Sendable (Result<Data, CameraPhotoError>) -> Void
    private weak var owner: SystemCameraDevice?

    init(owner: SystemCameraDevice, onResult: @escaping @Sendable (Result<Data, CameraPhotoError>) -> Void) {
        self.owner = owner
        self.onResult = onResult
        super.init()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        owner?.didCompleteCapture(self)
        if error != nil {
            onResult(.failure(.captureFailed))
        } else if let data = photo.fileDataRepresentation() {
            onResult(.success(data))
        } else {
            onResult(.failure(.captureFailed))
        }
    }
}

@MainActor
@Observable
final class CameraManager {
    private(set) var isRunning = false
    private(set) var cameraAccessDenied: Bool?

    private let authorization: any CameraAuthorizationManaging
    private let session: any CameraSession
    private let photoOutput: any CameraPhotoOutputting
    private let serialQueue = DispatchQueue(label: "com.betterfishing.camera.session")

    init(
        authorization: any CameraAuthorizationManaging = SystemCameraAuthorization(),
        session: any CameraSession,
        photoOutput: any CameraPhotoOutputting
    ) {
        self.authorization = authorization
        self.session = session
        self.photoOutput = photoOutput
    }

    convenience init() {
        let device = SystemCameraDevice()
        self.init(authorization: SystemCameraAuthorization(), session: device, photoOutput: device)
    }

    var previewSession: AVCaptureSession? {
        session.previewSession
    }

    func requestCameraAccessIfNeeded() async -> Bool {
        switch authorization.authorizationStatus() {
        case .authorized:
            cameraAccessDenied = false
            await configureAndStart()
            return true
        case .denied:
            cameraAccessDenied = true
            return false
        case .notDetermined:
            let status = await authorization.requestAccess()
            if status == .authorized {
                cameraAccessDenied = false
                await configureAndStart()
                return true
            }
            cameraAccessDenied = true
            return false
        }
    }

    func startRunning() async {
        guard cameraAccessDenied != true else { return }
        await configureAndStart()
    }

    func stopRunning() async {
        let session = self.session
        await runOnSerialQueue {
            if session.isRunning {
                session.stopRunning()
            }
        }
        isRunning = session.isRunning
    }

    func capturePhoto() async -> Data? {
        guard cameraAccessDenied != true else { return nil }
        let session = self.session
        let photoOutput = self.photoOutput
        let result: Result<Data, CameraPhotoError> = await withCheckedContinuation { continuation in
            serialQueue.async {
                _ = session.configureSession()
                photoOutput.capturePhoto { captured in
                    continuation.resume(returning: captured)
                }
            }
        }
        return try? result.get()
    }

    private func configureAndStart() async {
        let session = self.session
        await runOnSerialQueue {
            _ = session.configureSession()
            session.startRunning()
        }
        isRunning = session.isRunning
    }

    private func runOnSerialQueue(_ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            serialQueue.async {
                operation()
                continuation.resume()
            }
        }
    }
}