import Foundation
import XCTest

@testable import BetterFishing

final class FishialTokenStoreTests: XCTestCase {
    private var authEndpoint: URL { FishialConfiguration.authEndpoint }

    override func setUp() {
        super.setUp()
        HTTPStubRegistry.shared.reset()
    }

    override func tearDown() {
        HTTPStubRegistry.shared.reset()
        super.tearDown()
    }

    func testValidTokenReturnsCachedTokenWithoutNewAuth() async throws {
        let (store, _) = makeStore()
        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-1"]),
            for: authEndpoint.absoluteString
        )

        let first = try await store.validToken()

        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-2"]),
            for: authEndpoint.absoluteString
        )
        let second = try await store.validToken()

        XCTAssertEqual(first, "jwt-token-1")
        XCTAssertEqual(second, "jwt-token-1", "El token vigente en caché debe reutilizarse sin llamar a /v2/auth")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: authEndpoint.absoluteString), 1)
    }

    func testValidTokenRefreshesExpiredToken() async throws {
        let (store, clock) = makeStore()
        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-1"]),
            for: authEndpoint.absoluteString
        )

        _ = try await store.validToken()

        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-2"]),
            for: authEndpoint.absoluteString
        )
        clock.advance(by: 600 + 60 + 1)

        let refreshed = try await store.validToken()

        XCTAssertEqual(refreshed, "jwt-token-2", "Un token vencido debe forzar una nueva llamada a /v2/auth")
        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: authEndpoint.absoluteString), 2)
    }

    func testConcurrentCallersTriggerSingleAuthRequest() async throws {
        let (store, _) = makeStore()
        registerDelayedAuthStub(delay: 0.1, token: "jwt-token-1")

        let tokens = await withTaskGroup(of: String?.self, returning: [String?].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await store.validToken()
                }
            }
            var collected: [String?] = []
            for await value in group {
                collected.append(value)
            }
            return collected
        }

        let nonNil = tokens.compactMap { $0 }
        XCTAssertEqual(nonNil.count, 10, "Todas las llamadas concurrentes deben recibir un token válido")
        XCTAssertTrue(nonNil.allSatisfy { $0 == "jwt-token-1" })
        XCTAssertEqual(
            HTTPStubRegistry.shared.requestCount(for: authEndpoint.absoluteString),
            1,
            "La renovación debe serializarse: solo una llamada de auth bajo concurrencia"
        )
    }

    func testConcurrentCallersShareSingleFailedAuth() async throws {
        let (store, _) = makeStore()
        registerDelayedAuthStub(delay: 0.1, statusCode: 401, body: #"{"error":"invalid_client"}"#)

        let errors = await withTaskGroup(of: FishialTokenError?.self, returning: [FishialTokenError?].self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await store.validToken()
                        return nil
                    } catch let error as FishialTokenError {
                        return error
                    } catch {
                        return nil
                    }
                }
            }
            var collected: [FishialTokenError?] = []
            for await value in group {
                collected.append(value)
            }
            return collected
        }

        let thrown = errors.compactMap { $0 }
        XCTAssertEqual(thrown.count, 10, "Todas las llamadas concurrentes deben propagar el mismo fallo de auth")
        XCTAssertTrue(thrown.allSatisfy { $0 == .unauthorized })
        XCTAssertEqual(
            HTTPStubRegistry.shared.requestCount(for: authEndpoint.absoluteString),
            1,
            "El fallo también debe compartirse: solo una llamada de auth bajo concurrencia"
        )
    }

    func testValidTokenThrowsForUnauthorizedResponse() async {
        let (store, _) = makeStore()
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 401, data: Data(#"{"error":"invalid_client"}"#.utf8)),
            for: authEndpoint.absoluteString
        )

        do {
            _ = try await store.validToken()
            XCTFail("Se esperaba que validToken() lanzase ante un HTTP 401")
        } catch let error as FishialTokenError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testValidTokenPropagatesNetworkError() async {
        let (store, _) = makeStore()
        HTTPStubRegistry.shared.register(
            HTTPStub(error: URLError(.networkConnectionLost)),
            for: authEndpoint.absoluteString
        )

        do {
            _ = try await store.validToken()
            XCTFail("Se esperaba que validToken() lanzase ante un error de red")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testAuthRequestSendsClientCredentialsInJSONBody() async throws {
        let (store, _) = makeStore()
        HTTPStubRegistry.shared.register(
            HTTPStub.json(["token_type": "Bearer", "access_token": "jwt-token-1"]),
            for: authEndpoint.absoluteString
        )

        _ = try await store.validToken()

        let bodies = HTTPStubRegistry.shared.requestBodies(for: authEndpoint.absoluteString)
        let body = try XCTUnwrap(bodies.first)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body, options: []) as? [String: String]
        )
        XCTAssertEqual(json["client_id"], "test-client-id")
        XCTAssertEqual(json["client_secret"], "test-client-secret")
    }

    private func makeStore() -> (store: FishialTokenStore, clock: ManualClock) {
        let clock = ManualClock(base: Date(timeIntervalSince1970: 1_700_000_000))
        let store = FishialTokenStore(
            clientID: "test-client-id",
            clientSecret: "test-client-secret",
            session: .mockSession(),
            now: { clock.current }
        )
        return (store, clock)
    }

    private func registerDelayedAuthStub(delay: TimeInterval, statusCode: Int = 200, body: String) {
        HTTPStubRegistry.shared.register(
            HTTPStub(
                statusCode: statusCode,
                data: Data(body.utf8),
                headers: ["Content-Type": "application/json"],
                requestDelay: delay
            ),
            for: authEndpoint.absoluteString
        )
    }

    private func registerDelayedAuthStub(delay: TimeInterval, token: String) {
        registerDelayedAuthStub(
            delay: delay,
            body: #"{"token_type": "Bearer", "access_token": "\#(token)"}"#
        )
    }
}

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date

    init(base: Date) {
        currentDate = base
    }

    var current: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentDate
        }
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentDate = currentDate.addingTimeInterval(interval)
    }
}