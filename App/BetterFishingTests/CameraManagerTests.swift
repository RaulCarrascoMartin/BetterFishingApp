import AVFoundation
import XCTest

@testable import BetterFishing

@MainActor
final class CameraManagerTests: XCTestCase {
    private let jpegFixture = Data([
        0xFF, 0xD8,
        0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xFF, 0xD9,
    ])

    func testInitialStateIsNotRequestedAndNotRunning() {
        let (manager, _, _) = makeManager()

        XCTAssertNil(manager.cameraAccessDenied, "Antes de solicitar permiso, cameraAccessDenied debe ser nil")
        XCTAssertFalse(manager.isRunning)
    }

    func testRequestAccessWhenDeniedExposesDeniedAndDoesNotStart() async {
        let (manager, session, _) = makeManager(authStatus: .denied)

        let granted = await manager.requestCameraAccessIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(manager.cameraAccessDenied, true)
        XCTAssertEqual(session.startCount, 0, "Con permiso denegado no debe arrancarse la sesión")
        XCTAssertEqual(session.configureCount, 0)
        XCTAssertFalse(manager.isRunning)
    }

    func testRequestAccessWhenAuthorizedStartsSession() async {
        let (manager, session, _) = makeManager(authStatus: .authorized)

        let granted = await manager.requestCameraAccessIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(manager.cameraAccessDenied, false)
        XCTAssertEqual(session.startCount, 1, "Con permiso autorizado la sesión debe arrancar")
        XCTAssertGreaterThanOrEqual(session.configureCount, 1)
        XCTAssertTrue(manager.isRunning)
    }

    func testRequestAccessPromptsUserWhenNotDetermined() async {
        let authorization = StubAuthorization(status: .notDetermined, requestResult: .authorized)
        let (manager, session, _) = makeManager(authorization: authorization)

        let granted = await manager.requestCameraAccessIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(authorization.requestCount, 1, "Con estado notDetermined debe solicitarse el permiso")
        XCTAssertEqual(session.startCount, 1)
        XCTAssertTrue(manager.isRunning)
    }

    func testStopRunningWhenSessionAlreadyStoppedIsIdempotent() async {
        let (manager, session, _) = makeManager(session: StubSession(isRunning: false), authStatus: .authorized)

        await manager.stopRunning()

        XCTAssertEqual(session.stopCount, 0, "stopRunning() con la sesión ya detenida no debe invocar nada")
        XCTAssertFalse(manager.isRunning)
    }

    func testStopRunningWhenRunningStopsTheSession() async {
        let (manager, session, _) = makeManager(authStatus: .authorized)
        _ = await manager.requestCameraAccessIfNeeded()
        XCTAssertTrue(manager.isRunning)

        await manager.stopRunning()

        XCTAssertEqual(session.stopCount, 1)
        XCTAssertFalse(manager.isRunning)
    }

    func testCapturePhotoReturnsStashedJPEGFromOutput() async {
        let photoOutput = StubPhotoOutput(result: .success(jpegFixture))
        let (manager, _, _) = makeManager(photoOutput: photoOutput, authStatus: .authorized)
        _ = await manager.requestCameraAccessIfNeeded()

        let data = await manager.capturePhoto()

        XCTAssertEqual(data, jpegFixture, "La captura debe devolver los datos JPEG programados en el doble")
        XCTAssertEqual(photoOutput.captureCount, 1)
    }

    func testCapturePhotoReturnsNilWhenAccessDenied() async {
        let photoOutput = StubPhotoOutput(result: .success(jpegFixture))
        let (manager, _, _) = makeManager(photoOutput: photoOutput, authStatus: .denied)
        _ = await manager.requestCameraAccessIfNeeded()
        XCTAssertEqual(manager.cameraAccessDenied, true)

        let data = await manager.capturePhoto()

        XCTAssertNil(data, "Sin permiso de cámara la captura no debe devolver datos")
        XCTAssertEqual(photoOutput.captureCount, 0)
    }

    private func makeManager(
        session: StubSession? = nil,
        photoOutput: StubPhotoOutput? = nil,
        authStatus: CameraAccessStatus = .authorized,
        authorization: (any CameraAuthorizationManaging)? = nil
    ) -> (CameraManager, StubSession, StubPhotoOutput) {
        let resolvedSession = session ?? StubSession(isRunning: false)
        let resolvedPhotoOutput = photoOutput ?? StubPhotoOutput()
        let resolvedAuthorization = authorization ?? StubAuthorization(status: authStatus, requestResult: .authorized)
        let manager = CameraManager(
            authorization: resolvedAuthorization,
            session: resolvedSession,
            photoOutput: resolvedPhotoOutput
        )
        return (manager, resolvedSession, resolvedPhotoOutput)
    }
}

final class StubAuthorization: CameraAuthorizationManaging, @unchecked Sendable {
    var status: CameraAccessStatus
    var requestResult: CameraAccessStatus
    private(set) var requestCount = 0

    init(status: CameraAccessStatus, requestResult: CameraAccessStatus) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() -> CameraAccessStatus {
        status
    }

    func requestAccess() async -> CameraAccessStatus {
        requestCount += 1
        return requestResult
    }
}

final class StubSession: CameraSession, @unchecked Sendable {
    var isRunning: Bool
    var configureResult = true
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configureCount = 0

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    var previewSession: AVCaptureSession? {
        nil
    }

    @discardableResult
    func configureSession() -> Bool {
        configureCount += 1
        return configureResult
    }

    func startRunning() {
        startCount += 1
        isRunning = true
    }

    func stopRunning() {
        stopCount += 1
        isRunning = false
    }
}

final class StubPhotoOutput: CameraPhotoOutputting, @unchecked Sendable {
    var result: Result<Data, CameraPhotoError>
    private(set) var captureCount = 0

    init(result: Result<Data, CameraPhotoError> = .success(Data())) {
        self.result = result
    }

    func capturePhoto(onResult: @escaping @Sendable (Result<Data, CameraPhotoError>) -> Void) {
        captureCount += 1
        onResult(result)
    }
}