import XCTest

@testable import BetterFishing

@MainActor
final class PhotoPickerViewTests: XCTestCase {
    private let jpegFixture = Data([
        0xFF, 0xD8,
        0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0xFF, 0xD9,
    ])

    func testSelectingImageDeliversDataToCallback() async {
        let recorder = CallbackRecorder()
        let presenter = PhotoSelectionPresenter(onImagePicked: recorder.record)
        let item = StubPhotoItem(data: jpegFixture)

        await presenter.handleSelection(item)

        XCTAssertEqual(recorder.count, 1, "Seleccionar una imagen debe entregar los datos una vez")
        XCTAssertEqual(recorder.received, jpegFixture)
        XCTAssertFalse(presenter.isPreparing)
    }

    func testCancellationDeliversNoData() async {
        let recorder = CallbackRecorder()
        let presenter = PhotoSelectionPresenter(onImagePicked: recorder.record)

        await presenter.handleSelection(nil)

        XCTAssertEqual(recorder.count, 0, "Cancelar la selección no debe entregar datos")
        XCTAssertNil(recorder.received, "Cancelar la selección no debe iniciar identificación")
    }

    func testFailedLoadDeliversNoData() async {
        let recorder = CallbackRecorder()
        let presenter = PhotoSelectionPresenter(onImagePicked: recorder.record)
        let item = StubPhotoItem(data: nil)

        await presenter.handleSelection(item)

        XCTAssertEqual(recorder.count, 0, "Una carga fallida de transferable no debe entregar datos")
        XCTAssertNil(recorder.received)
        XCTAssertFalse(presenter.isPreparing)
    }

    func testIsPreparingTrueWhileLoadIsInFlight() async {
        let recorder = CallbackRecorder()
        let presenter = PhotoSelectionPresenter(onImagePicked: recorder.record)
        let gate = GatePhotoItem()

        let task = Task { await presenter.handleSelection(gate) }
        await waitUntil { presenter.isPreparing && gate.isSuspended }

        XCTAssertTrue(presenter.isPreparing, "Mientras el transferable carga, el estado debe ser preparing")

        gate.release(data: jpegFixture)
        await task.value

        XCTAssertFalse(presenter.isPreparing)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.received, jpegFixture)
    }

    private func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class CallbackRecorder {
    private(set) var count = 0
    private(set) var received: Data?

    func record(_ data: Data) {
        count += 1
        received = data
    }
}

private struct StubPhotoItem: PhotoItemLoading {
    let data: Data?

    func loadImageData() async -> Data? {
        data
    }
}

private final class GatePhotoItem: PhotoItemLoading, @unchecked Sendable {
    private let lock = NSLock()
    private var suspendedContinuation: CheckedContinuation<Data?, Never>?

    private(set) var isSuspended = false

    func loadImageData() async -> Data? {
        await withCheckedContinuation { continuation in
            lock.lock()
            suspendedContinuation = continuation
            isSuspended = true
            lock.unlock()
        }
    }

    func release(data: Data?) {
        lock.lock()
        let continuation = suspendedContinuation
        suspendedContinuation = nil
        isSuspended = false
        lock.unlock()
        continuation?.resume(returning: data)
    }
}