import Foundation
import XCTest

enum TemporaryDirectoryError: Error {
    case creationFailed
}

final class TemporaryTestDirectory: @unchecked Sendable {
    let url: URL

    init?() {
        let path = NSTemporaryDirectory() + "BetterFishingTests-" + UUID().uuidString
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        self.url = directoryURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        remove()
    }
}

extension XCTestCase {
    func makeTemporaryDirectory() throws -> TemporaryTestDirectory {
        guard let directory = TemporaryTestDirectory() else {
            throw TemporaryDirectoryError.creationFailed
        }
        addTeardownBlock { [directory] in
            directory.remove()
        }
        return directory
    }
}