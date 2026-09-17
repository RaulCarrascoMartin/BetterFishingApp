import Foundation
import os

enum FishialConfiguration {
    static let baseURL = URL(string: "https://api-recognition.fishial.ai")!
    static let authEndpoint = baseURL.appendingPathComponent("v2/auth")
}

enum FishialTokenError: Error, Equatable {
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
}

final class FishialTokenStore: Sendable {
    private static let tokenTTL: TimeInterval = 600
    private static let validityMargin: TimeInterval = 60
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "FishialTokenStore")

    private struct State {
        var token: String?
        var expiresAt: Date?
        var nextRenewalID = 0
        var inFlightID: Int?
        var inFlight: Task<String, Error>?
    }

    private let session: URLSession
    private let clientID: String
    private let clientSecret: String
    private let now: @Sendable () -> Date
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        clientID: String,
        clientSecret: String,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
        self.now = now
    }

    func validToken() async throws -> String {
        if let cached = cachedValidToken() {
            return cached
        }

        let renewal = state.withLock { state -> (id: Int, task: Task<String, Error>) in
            if let id = state.inFlightID, let inFlight = state.inFlight {
                return (id, inFlight)
            }
            state.nextRenewalID += 1
            let id = state.nextRenewalID
            let task = Task { try await self.refreshToken() }
            state.inFlight = task
            state.inFlightID = id
            return (id, task)
        }

        do {
            let token = try await renewal.task.value
            clearInFlight(renewal.id)
            return token
        } catch {
            clearInFlight(renewal.id)
            throw error
        }
    }

    private func cachedValidToken() -> String? {
        let current = now()
        return state.withLock { state in
            guard let token = state.token, let expiresAt = state.expiresAt else {
                return nil
            }
            let validUntil = expiresAt.addingTimeInterval(-Self.validityMargin)
            return current < validUntil ? token : nil
        }
    }

    private func clearInFlight(_ id: Int) {
        state.withLock { state in
            if state.inFlightID == id {
                state.inFlight = nil
                state.inFlightID = nil
            }
        }
    }

    private func refreshToken() async throws -> String {
        Self.logger.info("Renovando token Fishial vía /v2/auth")
        do {
            let token = try await performAuthRequest()
            Self.logger.info("Token Fishial renovado con éxito; TTL \(Self.tokenTTL)s")
            return token
        } catch {
            Self.logger.error("Fallo al renovar token Fishial: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func performAuthRequest() async throws -> String {
        var request = URLRequest(url: FishialConfiguration.authEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            AuthRequestBody(clientID: clientID, clientSecret: clientSecret)
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FishialTokenError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw FishialTokenError.unauthorized
            }
            throw FishialTokenError.serverError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(FishialTokenResponse.self, from: data)

        let expiry = now().addingTimeInterval(Self.tokenTTL)
        state.withLock { state in
            state.token = payload.accessToken
            state.expiresAt = expiry
        }
        return payload.accessToken
    }
}

private struct AuthRequestBody: Encodable {
    let clientID: String
    let clientSecret: String
}