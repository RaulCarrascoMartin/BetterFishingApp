import XCTest

@testable import BetterFishing

final class SupabaseProfileRepositoryTests: XCTestCase {

    private func makeRepository(fake: SupabaseBaseFake) -> SupabaseProfileRepository {
        SupabaseProfileRepository(auth: fake, database: fake, storage: fake)
    }

    func testProfileReturnsDefaultWhenNoRows() async throws {
        let fake = SupabaseBaseFake()
        let repository = makeRepository(fake: fake)

        let profile = try await repository.profile()

        XCTAssertEqual(profile.userID, SupabaseBaseFake.defaultUser.id)
        XCTAssertNil(profile.displayName)
        XCTAssertNil(profile.avatarPath)
    }

    func testProfileDecodesCannedRow() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = ["{\"user_id\":\"\(SupabaseBaseFake.defaultUser.id.uuidString)\",\"display_name\":\"Ana\",\"avatar_path\":null}"]
        let repository = makeRepository(fake: fake)

        let profile = try await repository.profile()

        XCTAssertEqual(profile.userID, SupabaseBaseFake.defaultUser.id)
        XCTAssertEqual(profile.displayName, "Ana")
        XCTAssertNil(profile.avatarPath)
    }

    func testUpdateDisplayNamePreservesAvatarViaUpsertProfile() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = ["{\"user_id\":\"\(SupabaseBaseFake.defaultUser.id.uuidString)\",\"display_name\":\"Antigua\",\"avatar_path\":\"x/avatar.jpg\"}"]
        fake.cannedRPCValue = "{}"
        let repository = makeRepository(fake: fake)

        try await repository.updateDisplayName("Nuevo")

        let recorded = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(recorded.function, "upsert_profile")
        XCTAssertEqual(recorded.arguments?.values["p_user_id"], .string(SupabaseBaseFake.defaultUser.id.uuidString))
        XCTAssertEqual(recorded.arguments?.values["p_display_name"], .string("Nuevo"))
        XCTAssertEqual(recorded.arguments?.values["p_avatar_path"], .string("x/avatar.jpg"))
    }

    func testUpdateAvatarUploadsToAvatarsBucketAndPersistsPath() async throws {
        let fake = SupabaseBaseFake()
        let userID = SupabaseBaseFake.defaultUser.id
        fake.uploadResultPath = "\(userID.uuidString)/avatar.jpg"
        fake.cannedRPCValue = "{}"
        fake.cannedRows = ["{\"user_id\":\"\(userID.uuidString)\",\"display_name\":\"Ana\",\"avatar_path\":null}"]
        let repository = makeRepository(fake: fake)

        let storedPath = try await repository.updateAvatar(data: Data([0x01, 0x02]), contentType: "image/jpeg")

        XCTAssertEqual(storedPath, fake.uploadResultPath)
        let upload = try XCTUnwrap(fake.recordedUploads.first)
        XCTAssertEqual(upload.bucket, "avatars")
        XCTAssertEqual(upload.path, "\(userID.uuidString)/avatar.jpg")
        XCTAssertTrue(upload.path.hasSuffix("avatar.jpg"))
        XCTAssertEqual(upload.options?.contentType, "image/jpeg")
        XCTAssertEqual(upload.options?.upsert, true)
        let rpc = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(rpc.function, "upsert_profile")
        XCTAssertEqual(rpc.arguments?.values["p_avatar_path"], .string(fake.uploadResultPath))
        XCTAssertEqual(rpc.arguments?.values["p_display_name"], .string("Ana"))
    }

    func testAvatarDataDownloadsFromAvatarsBucket() async throws {
        let fake = SupabaseBaseFake()
        let userID = SupabaseBaseFake.defaultUser.id
        fake.downloadResultData = Data([0xAA, 0xBB])
        let repository = makeRepository(fake: fake)

        let data = try await repository.avatarData(avatarPath: "\(userID.uuidString)/avatar.jpg")

        XCTAssertEqual(data, Data([0xAA, 0xBB]))
        let download = try XCTUnwrap(fake.recordedDownloads.first)
        XCTAssertEqual(download.bucket, "avatars")
        XCTAssertEqual(download.path, "\(userID.uuidString)/avatar.jpg")
    }

    func testProfileAndNameUpdateWithoutSessionThrowNotAuthenticated() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        let repository = makeRepository(fake: fake)

        do {
            _ = try await repository.profile()
            XCTFail("Se esperaba AccountProfileError.notAuthenticated")
        } catch let error as AccountProfileError {
            guard case .notAuthenticated = error else {
                XCTFail("Se esperaba .notAuthenticated, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }

        do {
            try await repository.updateDisplayName("Nuevo")
            XCTFail("Se esperaba AccountProfileError.notAuthenticated")
        } catch let error as AccountProfileError {
            guard case .notAuthenticated = error else {
                XCTFail("Se esperaba .notAuthenticated, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testProfileLoadFailureThrowsLoadFailed() async throws {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseError.queryFailed
        let repository = makeRepository(fake: fake)

        do {
            _ = try await repository.profile()
            XCTFail("Se esperaba AccountProfileError.loadFailed")
        } catch let error as AccountProfileError {
            guard case .loadFailed = error else {
                XCTFail("Se esperaba .loadFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func testUpdateDisplayNameRPCFailureThrowsUpdateFailed() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = ["{\"user_id\":\"\(SupabaseBaseFake.defaultUser.id.uuidString)\",\"display_name\":\"Ana\",\"avatar_path\":null}"]
        fake.cannedRPCValue = "no-es-json"
        let repository = makeRepository(fake: fake)

        do {
            try await repository.updateDisplayName("Nuevo")
            XCTFail("Se esperaba AccountProfileError.updateFailed")
        } catch let error as AccountProfileError {
            guard case .updateFailed = error else {
                XCTFail("Se esperaba .updateFailed, recibido \(error)")
                return
            }
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }
}