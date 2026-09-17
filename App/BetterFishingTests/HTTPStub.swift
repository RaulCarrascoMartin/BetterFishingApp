import Foundation

struct HTTPStub {
    var statusCode: Int
    var data: Data
    var headers: [String: String]
    var error: Error?
    var requestDelay: TimeInterval

    init(
        statusCode: Int = 200,
        data: Data = Data(),
        headers: [String: String] = ["Content-Type": "application/json"],
        error: Error? = nil,
        requestDelay: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.data = data
        self.headers = headers
        self.error = error
        self.requestDelay = requestDelay
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
    private var requestCounts: [String: Int] = [:]
    private var requestBodies: [String: [Data]] = [:]

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

    func record(_ request: URLRequest, urlString: String) {
        lock.lock()
        defer { lock.unlock() }
        requestCounts[urlString, default: 0] += 1
        requestBodies[urlString, default: []].append(Self.bodyData(of: request))
    }

    func requestCount(for urlString: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCounts[urlString] ?? 0
    }

    func requestBodies(for urlString: String) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return requestBodies[urlString] ?? []
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        stubs.removeAll()
        requestCounts.removeAll()
        requestBodies.removeAll()
    }

    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}