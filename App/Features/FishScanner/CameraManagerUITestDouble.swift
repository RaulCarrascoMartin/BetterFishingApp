#if DEBUG
import AVFoundation
import UIKit

struct UITestCameraAuthorization: CameraAuthorizationManaging {
    func authorizationStatus() -> CameraAccessStatus {
        .authorized
    }

    func requestAccess() async -> CameraAccessStatus {
        .authorized
    }
}

final class UITestCameraDevice: CameraSession, CameraPhotoOutputting, @unchecked Sendable {
    private(set) var isRunning = false
    private(set) var isConfigured = false
    private let preview: AVCaptureSession
    private let jpegData: Data

    var previewSession: AVCaptureSession? {
        preview
    }

    init() {
        preview = AVCaptureSession()
        jpegData = Self.makeJPEGData()
    }

    @discardableResult
    func configureSession() -> Bool {
        isConfigured = true
        return true
    }

    func startRunning() {
        isRunning = true
    }

    func stopRunning() {
        isRunning = false
    }

    func capturePhoto(onResult: @escaping @Sendable (Result<Data, CameraPhotoError>) -> Void) {
        guard isConfigured else {
            onResult(.failure(.sessionNotReady))
            return
        }
        onResult(.success(jpegData))
    }

    private static func makeJPEGData() -> Data {
        let size = CGSize(width: 640, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            preconditionFailure("No se pudo generar el JPEG del doble de cámara de UI test")
        }
        return jpeg
    }
}
#endif