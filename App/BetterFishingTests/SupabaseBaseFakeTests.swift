import Foundation
import XCTest

@testable import BetterFishing

final class SupabaseBaseFakeTests: XCTestCase {
    func testBaseFakeIsUsableAsAllThreeSeams() async throws {
        let fake = SupabaseBaseFake()
        let auth: any SupabaseAuthProviding = fake
        let store: any SupabaseStoring = fake
        let db: any SupabaseDatabaseAccess = fake

        let session = try await auth.signIn(email: "angler@example.com", password: "secret")
        let path = try await store.upload(
            bucket: "catches",
            path: "catch-1.jpg",
            data: Data([0x01]),
            options: nil
        )
        let rows: [String] = try await db.select(
            columns: "id,name",
            from: "spots",
            filters: [],
            limit: 5
        )

        XCTAssertNotNil(session.accessToken)
        XCTAssertEqual(path, fake.uploadResultPath)
        XCTAssertEqual(rows, fake.cannedRows)
        XCTAssertEqual(fake.recordedSignIns.count, 1)
        XCTAssertEqual(fake.recordedUploads.count, 1)
        XCTAssertEqual(fake.recordedSelects.count, 1)
    }

    func testSignInRecordsCredentialsAndReturnsConfiguredSession() async throws {
        let fake = SupabaseBaseFake()
        fake.authSession = SupabaseBaseFakeTests.session
        let auth: any SupabaseAuthProviding = fake

        let session = try await auth.signIn(email: "angler@example.com", password: "hunter2")

        XCTAssertEqual(session, SupabaseBaseFakeTests.session)
        XCTAssertEqual(
            fake.recordedSignIns,
            [BaseFakeRecordedCredentials(email: "angler@example.com", password: "hunter2")]
        )
    }

    func testSignUpRecordsCredentialsAndReturnsConfiguredSession() async throws {
        let fake = SupabaseBaseFake()
        let auth: any SupabaseAuthProviding = fake

        let session = try await auth.signUp(email: "new@example.com", password: "pw1234")

        XCTAssertEqual(session, fake.authSession)
        XCTAssertEqual(
            fake.recordedSignUps,
            [BaseFakeRecordedCredentials(email: "new@example.com", password: "pw1234")]
        )
    }

    func testSignOutRecordsCallAndCurrentSessionReflectsConfiguredState() async throws {
        let fake = SupabaseBaseFake()
        let auth: any SupabaseAuthProviding = fake

        try await auth.signOut()
        let current = try await auth.currentSession()
        let user = await auth.currentUser()

        XCTAssertEqual(fake.recordedSignOutCount, 1)
        XCTAssertEqual(current, fake.authSession)
        XCTAssertEqual(user, fake.authSession.user)
    }

    func testStateChangesYieldsConfiguredEventsInOrder() async {
        let fake = SupabaseBaseFake()
        fake.stateChangesEvents = [
            .signedIn(SupabaseBaseFakeTests.session),
            .signedOut,
        ]
        let auth: any SupabaseAuthProviding = fake

        var labels: [String] = []
        var emittedSession: SupabaseSession?
        for await event in auth.stateChanges() {
            switch event {
            case .signedIn(let session):
                emittedSession = session
                labels.append("signedIn")
            case .sessionRestored(let session):
                emittedSession = session
                labels.append("sessionRestored")
            case .signedOut:
                labels.append("signedOut")
            }
        }

        XCTAssertEqual(labels, ["signedIn", "signedOut"])
        XCTAssertEqual(emittedSession, SupabaseBaseFakeTests.session)
    }

    func testAuthFailurePropagatesProgrammedError() async {
        let fake = SupabaseBaseFake()
        fake.authError = SupabaseBaseFakeError(reason: "invalid credentials")
        let auth: any SupabaseAuthProviding = fake

        do {
            _ = try await auth.signIn(email: "angler@example.com", password: "wrong")
            XCTFail("Expected signIn to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "invalid credentials"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testUploadRecordsBucketAndPathAndReturnsConfiguredPath() async throws {
        let fake = SupabaseBaseFake()
        fake.uploadResultPath = "catches/2026/season/catch-1.jpg"
        let expectedOptions = SupabaseUploadOptions(contentType: "image/jpeg", upsert: true)
        let store: any SupabaseStoring = fake

        let path = try await store.upload(
            bucket: "catches",
            path: "2026/season/catch-1.jpg",
            data: Data([0xAA, 0xBB]),
            options: expectedOptions
        )

        XCTAssertEqual(path, "catches/2026/season/catch-1.jpg")
        let recorded = fake.recordedUploads
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.bucket, "catches")
        XCTAssertEqual(recorded.first?.path, "2026/season/catch-1.jpg")
        XCTAssertEqual(recorded.first?.data, Data([0xAA, 0xBB]))
        XCTAssertEqual(recorded.first?.options, expectedOptions)
    }

    func testUploadFailurePropagatesProgrammedError() async {
        let fake = SupabaseBaseFake()
        fake.uploadError = SupabaseBaseFakeError(reason: "bucket full")
        let store: any SupabaseStoring = fake

        do {
            _ = try await store.upload(
                bucket: "catches",
                path: "catch-1.jpg",
                data: Data(),
                options: nil
            )
            XCTFail("Expected upload to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "bucket full"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDownloadRecordsBucketAndPathAndReturnsConfiguredData() async throws {
        let fake = SupabaseBaseFake()
        fake.downloadResultData = Data([0xDE, 0xAD])
        let store: any SupabaseStoring = fake

        let data = try await store.download(bucket: "catches", path: "catch-1.jpg")

        XCTAssertEqual(data, Data([0xDE, 0xAD]))
        XCTAssertEqual(fake.recordedDownloads.count, 1)
        XCTAssertEqual(fake.recordedDownloads.first?.bucket, "catches")
        XCTAssertEqual(fake.recordedDownloads.first?.path, "catch-1.jpg")
    }

    func testDownloadFailurePropagatesProgrammedError() async {
        let fake = SupabaseBaseFake()
        fake.downloadError = SupabaseBaseFakeError(reason: "object not found")
        let store: any SupabaseStoring = fake

        do {
            _ = try await store.download(bucket: "catches", path: "missing.jpg")
            XCTFail("Expected download to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "object not found"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testSelectReturnsCannedRowsAndRecordsColumnsFiltersLimit() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = ["row-1", "row-2"]
        let filters: [SupabaseFilter] = [
            SupabaseFilter(column: "species", operator: .eq, value: "bass"),
            SupabaseFilter(column: "min_size", operator: .gte, value: "30"),
        ]
        let db: any SupabaseDatabaseAccess = fake

        let rows: [String] = try await db.select(
            columns: "id,species",
            from: "spots",
            filters: filters,
            limit: 10
        )

        XCTAssertEqual(rows, ["row-1", "row-2"])
        let recorded = fake.recordedSelects
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.columns, "id,species")
        XCTAssertEqual(recorded.first?.table, "spots")
        XCTAssertEqual(recorded.first?.filters, filters)
        XCTAssertEqual(recorded.first?.limit, 10)
    }

    func testRPCReturnsCannedValueAndRecordsFunctionAndArguments() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRPCValue = "ok"
        let arguments = SupabaseRPCArguments([
            "lat": .double(40.4168),
            "lng": .double(-3.7038),
            "radius": .int(5),
        ])
        let db: any SupabaseDatabaseAccess = fake

        let result: String = try await db.rpc("nearby_spots", arguments: arguments)

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(fake.recordedRPCs.first?.function, "nearby_spots")
        XCTAssertEqual(fake.recordedRPCs.first?.arguments, arguments)
    }

    func testRPCVoidRecordsFunctionAndArguments() async throws {
        let fake = SupabaseBaseFake()
        let arguments = SupabaseRPCArguments([
            "id": .string("value-1"),
            "active": .bool(true),
        ])
        let db: any SupabaseDatabaseAccess = fake

        try await db.rpcVoid("mutate_value", arguments: arguments)

        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(fake.recordedRPCs.first?.function, "mutate_value")
        XCTAssertEqual(fake.recordedRPCs.first?.arguments, arguments)
    }

    func testRPCVoidFailurePropagatesProgrammedErrorAndRecordsCall() async {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseFakeError(reason: "rpc failed")
        let db: any SupabaseDatabaseAccess = fake

        do {
            try await db.rpcVoid("mutate_value", arguments: nil)
            XCTFail("Expected rpcVoid to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "rpc failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(fake.recordedRPCs.count, 1)
        XCTAssertEqual(fake.recordedRPCs.first?.function, "mutate_value")
        XCTAssertNil(fake.recordedRPCs.first?.arguments)
    }

    func testDatabaseFailurePropagatesProgrammedError() async {
        let fake = SupabaseBaseFake()
        fake.databaseError = SupabaseBaseFakeError(reason: "query failed")
        let db: any SupabaseDatabaseAccess = fake

        do {
            let _: [String] = try await db.select(
                columns: "id",
                from: "spots",
                filters: [],
                limit: nil
            )
            XCTFail("Expected select to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "query failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            let _: String = try await db.rpc("nearby_spots", arguments: nil)
            XCTFail("Expected rpc to throw")
        } catch let error as SupabaseBaseFakeError {
            XCTAssertEqual(error, SupabaseBaseFakeError(reason: "query failed"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testResetClearsRecordedCalls() async throws {
        let fake = SupabaseBaseFake()
        let auth: any SupabaseAuthProviding = fake
        let store: any SupabaseStoring = fake
        let db: any SupabaseDatabaseAccess = fake

        _ = try await auth.signIn(email: "angler@example.com", password: "secret")
        _ = try await auth.signOut()
        _ = try await store.upload(bucket: "catches", path: "c.jpg", data: Data(), options: nil)
        _ = try await store.download(bucket: "catches", path: "c.jpg")
        let _: [String] = try await db.select(columns: "id", from: "spots", filters: [], limit: nil)
        let _: String = try await db.rpc("nearby_spots", arguments: nil)
        try await db.rpcVoid("clear_cache", arguments: nil)
        XCTAssertEqual(fake.recordedSignUps.count, 0)
        XCTAssertEqual(fake.recordedSignIns.count, 1)
        XCTAssertEqual(fake.recordedSignOutCount, 1)
        XCTAssertEqual(fake.recordedUploads.count, 1)
        XCTAssertEqual(fake.recordedDownloads.count, 1)
        XCTAssertEqual(fake.recordedSelects.count, 1)
        XCTAssertEqual(fake.recordedRPCs.count, 2)

        fake.reset()

        XCTAssertTrue(fake.recordedSignUps.isEmpty)
        XCTAssertTrue(fake.recordedSignIns.isEmpty)
        XCTAssertEqual(fake.recordedSignOutCount, 0)
        XCTAssertTrue(fake.recordedUploads.isEmpty)
        XCTAssertTrue(fake.recordedDownloads.isEmpty)
        XCTAssertTrue(fake.recordedSelects.isEmpty)
        XCTAssertTrue(fake.recordedRPCs.isEmpty)
    }

    private static let user = SupabaseUser(
        id: UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)),
        email: "angler@example.com",
        createdAt: Date(timeIntervalSinceReferenceDate: 7_500_000)
    )

    private static let session = SupabaseSession(
        accessToken: "access-token-123",
        refreshToken: "refresh-token-456",
        expiresAt: Date(timeIntervalSinceReferenceDate: 7_500_000 + 3_600),
        user: user
    )
}