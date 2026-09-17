import Foundation
import os

enum FishialClientError: Error, Equatable {
    case unauthorized
    case invalidResponse
    case serverError(statusCode: Int)
}

final class FishialClient: FishIdentifying {
    private static let recognizeTimeoutInterval: TimeInterval = 15
    private static let reliableCertaintyThreshold = 0.55
    private static let lowCertaintyThreshold = 0.30
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "FishialClient")

    private let session: URLSession
    private let tokenStore: FishialTokenStore

    init(session: URLSession = .shared, tokenStore: FishialTokenStore) {
        self.session = session
        self.tokenStore = tokenStore
    }

    func recognize(imageData: Data) async throws -> IdentificationOutcome {
        let token = try await tokenStore.validToken()
        do {
            return try await performRecognize(imageData: imageData, bearerToken: token)
        } catch FishialClientError.unauthorized {
            Self.logger.info("recognize recibió 401; se renueva el token y se reintenta una vez")
            tokenStore.invalidateCachedToken()
            let renewedToken = try await tokenStore.validToken()
            return try await performRecognize(imageData: imageData, bearerToken: renewedToken)
        }
    }

    private func performRecognize(
        imageData: Data,
        bearerToken: String
    ) async throws -> IdentificationOutcome {
        var request = URLRequest(url: FishialConfiguration.recognizeEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.recognizeTimeoutInterval
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = imageData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("recognize falló: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("recognize devolvió una respuesta no HTTP; se trata como error genérico")
            throw FishialClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 401:
            Self.logger.error("recognize devolvió 401 (token rechazado)")
            throw FishialClientError.unauthorized
        case 200:
            break
        default:
            Self.logger.error("recognize devolvió HTTP \(httpResponse.statusCode, privacy: .public)")
            throw FishialClientError.serverError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: FishialRecognitionResponse
        do {
            payload = try decoder.decode(FishialRecognitionResponse.self, from: data)
        } catch {
            Self.logger.error("recognize devolvió una respuesta no JSON del edge; error genérico")
            throw FishialClientError.invalidResponse
        }

        guard payload.ok else {
            Self.logger.error("recognize respondió con ok: false; error genérico")
            throw FishialClientError.invalidResponse
        }

        return makeOutcome(from: payload)
    }

    private func makeOutcome(from payload: FishialRecognitionResponse) -> IdentificationOutcome {
        guard let bestObject = payload.objects.first, let candidate = bestObject.species.first else {
            Self.logger.info("recognize: sin coincidencia (\(payload.objects.count) objetos)")
            return .noMatch
        }
        guard candidate.certainty >= Self.lowCertaintyThreshold else {
            Self.logger.info(
                "recognize: sin coincidencia (confianza \(candidate.certainty, privacy: .public) bajo el umbral)"
            )
            return .noMatch
        }
        guard let definition = payload.definitions[candidate.id] else {
            Self.logger.info(
                "recognize: sin coincidencia (sin definición para \(candidate.id, privacy: .public))"
            )
            return .noMatch
        }

        let confidence: IdentificationConfidence =
            candidate.certainty >= Self.reliableCertaintyThreshold ? .reliable : .low
        let result = IdentificationResult(
            species: Species(
                id: candidate.id,
                commonName: definition.commonName,
                scientificName: definition.scientificName,
                localizedName: nil,
                referenceImageURL: definition.imageUrl.flatMap(URL.init(string:))
            ),
            certainty: candidate.certainty,
            confidence: confidence
        )

        switch confidence {
        case .reliable:
            Self.logger.info("recognize: identificación fiable (\(candidate.id, privacy: .public))")
        case .low:
            Self.logger.warning(
                "recognize: identificación con confianza baja (\(candidate.id, privacy: .public))"
            )
        }
        return .identified(result)
    }
}