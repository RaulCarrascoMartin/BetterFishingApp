import Foundation

struct HTTPStub {
    var statusCode: Int
    var data: Data
    var headers: [String: String]
    var error: Error?

    init(
        statusCode: Int = 200,
        data: Data = Data(),
        headers: [String: String] = ["Content-Type": "application/json"],
        error: Error? = nil
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
        self.error = error
    }

    static func json(_ value: Any, statusCode: Int = 200) -> HTTPStub {
        let data = try! JSONSerialization.data(withJSONObject: value)
        return HTTPStub(statusCode: statusCode, data: data)
    }
}

final class HTTPStubRegistry: @unchecked Sendable {
    static let shared = HTTPStubRegistry()

    private let lock = NSLock()
    private var stubs: [String: HTTPStub] = [:]

    private init() {}

    func register(_ stub: HTTPStub, for urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        stubs[urlString] = stub
    }

    func stub(for url: URL) -> HTTPStub? {
        lock.lock()
        defer { lock.unlock() }
        return stubs[url.absoluteString]
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
    }
}