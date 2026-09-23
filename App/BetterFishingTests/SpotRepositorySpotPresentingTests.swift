import Foundation
import XCTest

@testable import BetterFishing

final class SpotRepositorySpotPresentingTests: XCTestCase {

    private let firstID = UUID()
    private let secondID = UUID()

    private func makeCoordinate(latitude: Double = 41.0, longitude: Double = 2.0) -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func makeSpot(
        id: UUID,
        name: String,
        category: SpotCategory = .lake,
        latitude: Double = 41.0,
        longitude: Double = 2.0
    ) -> Spot {
        Spot(
            id: id,
            name: name,
            category: category,
            summary: "Resumen de prueba",
            longitude: longitude,
            latitude: latitude,
            distanceMeters: nil
        )
    }

    private func makeRegion() -> SpotRegion {
        SpotRegion(
            center: makeCoordinate(),
            latitudinalMeters: 111_320.0,
            longitudinalMeters: 111_320.0
        )
    }

    private func makePresenting(repository: any SpotRepository) -> SpotRepositorySpotPresenting {
        SpotRepositorySpotPresenting(repository: repository)
    }

    func testFavoriteSpotIDsDelegatesToSeam() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteIDs = [firstID, secondID]
        let presenting = makePresenting(repository: fake)

        let ids = try await presenting.favoriteSpotIDs()

        XCTAssertEqual(ids, Set([firstID, secondID]))
    }

    func testFavoritesMapsToFavoriteSpotWithoutGeometry() async throws {
        let lake = makeSpot(id: firstID, name: "Embalse de Sau", category: .lake)
        let sea = makeSpot(id: secondID, name: "Port de Barcelona", category: .sea, latitude: 41.37, longitude: 2.18)
        let fake = SpotRepositoryFake()
        fake.seed([lake, sea], for: makeRegion())
        fake.favoriteIDs = [firstID, secondID]
        let presenting = makePresenting(repository: fake)

        let favorites = try await presenting.favorites()

        let first = try XCTUnwrap(favorites.first { $0.spotID == firstID })
        XCTAssertEqual(first.spotID, firstID)
        XCTAssertEqual(first.id, firstID)
        XCTAssertEqual(first.name, "Embalse de Sau")
        XCTAssertEqual(first.category, "lake")
        let second = try XCTUnwrap(favorites.first { $0.spotID == secondID })
        XCTAssertEqual(second.name, "Port de Barcelona")
        XCTAssertEqual(second.category, "sea")
    }

    func testIsFavoriteTrueWhenPresentAndFalseWhenAbsent() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteIDs = [firstID]
        let presenting = makePresenting(repository: fake)

        let present = try await presenting.isFavorite(spotID: firstID)
        let absent = try await presenting.isFavorite(spotID: secondID)

        XCTAssertTrue(present)
        XCTAssertFalse(absent)
    }

    func testSetFavoriteDelegatesBothDirectionsToSeam() async throws {
        let fake = SpotRepositoryFake()
        let presenting = makePresenting(repository: fake)

        try await presenting.setFavorite(spotID: firstID, isFavorite: true)
        try await presenting.setFavorite(spotID: firstID, isFavorite: false)

        XCTAssertEqual(
            fake.recordedFavoriteToggles,
            [
                SpotRepositoryFake.RecordedFavoriteToggle(spotID: firstID, isFavorite: true),
                SpotRepositoryFake.RecordedFavoriteToggle(spotID: firstID, isFavorite: false)
            ]
        )
        XCTAssertTrue(fake.favoriteIDs.isEmpty)
    }

    func testAuthenticationRequiredTranslatesAcrossOperations() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteSpotsError = .authenticationRequired
        fake.setFavoriteError = .authenticationRequired
        let presenting = makePresenting(repository: fake)

        do {
            _ = try await presenting.favorites()
            XCTFail("Se esperaba FavoritesError.authenticationRequired")
        } catch let error as FavoritesError {
            guard case .authenticationRequired = error else {
                XCTFail("Se esperaba .authenticationRequired, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await presenting.setFavorite(spotID: firstID, isFavorite: true)
            XCTFail("Se esperaba FavoritesError.authenticationRequired")
        } catch let error as FavoritesError {
            guard case .authenticationRequired = error else {
                XCTFail("Se esperaba .authenticationRequired, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testQueryFailedTranslatesPerOperation() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteSpotsError = .queryFailed("favoritos sin soporte")
        fake.setFavoriteError = .queryFailed("favoritos sin soporte")
        let presenting = makePresenting(repository: fake)

        do {
            _ = try await presenting.favorites()
            XCTFail("Se esperaba FavoritesError.loadFailed")
        } catch let error as FavoritesError {
            guard case .loadFailed = error else {
                XCTFail("Se esperaba .loadFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await presenting.setFavorite(spotID: firstID, isFavorite: true)
            XCTFail("Se esperaba FavoritesError.saveFailed")
        } catch let error as FavoritesError {
            guard case .saveFailed = error else {
                XCTFail("Se esperaba .saveFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await presenting.setFavorite(spotID: secondID, isFavorite: false)
            XCTFail("Se esperaba FavoritesError.removeFailed")
        } catch let error as FavoritesError {
            guard case .removeFailed = error else {
                XCTFail("Se esperaba .removeFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testBackendUnavailableTranslatesPerOperation() async throws {
        let fake = SpotRepositoryFake()
        fake.favoriteSpotIDsError = .backendUnavailable
        fake.favoriteSpotsError = .backendUnavailable
        fake.setFavoriteError = .backendUnavailable
        let presenting = makePresenting(repository: fake)

        do {
            _ = try await presenting.favoriteSpotIDs()
            XCTFail("Se esperaba FavoritesError.loadFailed")
        } catch let error as FavoritesError {
            guard case .loadFailed = error else {
                XCTFail("Se esperaba .loadFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            _ = try await presenting.favorites()
            XCTFail("Se esperaba FavoritesError.loadFailed")
        } catch let error as FavoritesError {
            guard case .loadFailed = error else {
                XCTFail("Se esperaba .loadFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await presenting.setFavorite(spotID: firstID, isFavorite: true)
            XCTFail("Se esperaba FavoritesError.saveFailed")
        } catch let error as FavoritesError {
            guard case .saveFailed = error else {
                XCTFail("Se esperaba .saveFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await presenting.setFavorite(spotID: firstID, isFavorite: false)
            XCTFail("Se esperaba FavoritesError.removeFailed")
        } catch let error as FavoritesError {
            guard case .removeFailed = error else {
                XCTFail("Se esperaba .removeFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
}