import Foundation

@testable import BetterFishing

struct SupabaseBaseFakeError: Error, Equatable {
    let reason: String
}

struct BaseFakeRecordedCredentials: Equatable {
    let email: String
    let password: String
}

struct BaseFakeRecordedUpload: Equatable {
    let bucket: String
    let path: String
    let data: Data
    let options: SupabaseUploadOptions?
}

struct BaseFakeRecordedDownload: Equatable {
    let bucket: String
    let path: String
}

struct BaseFakeRecordedSelect: Equatable {
    let columns: String
    let table: String
    let filters: [SupabaseFilter]
    let limit: Int?
}

struct BaseFakeRecordedRPC: Equatable {
    let function: String
    let arguments: SupabaseRPCArguments?
}

final class SupabaseBaseFake: SupabaseAuthProviding, SupabaseStoring, SupabaseDatabaseAccess, @unchecked Sendable {
    private struct State {
        var authSession: SupabaseSession
        var authSignUpResult: SupabaseSignUpResult?
        var authError: Error?
        var stateChangesEvents: [SupabaseAuthEvent]
        var uploadResultPath: String
        var uploadError: Error?
        var downloadData: Data
        var downloadError: Error?
        var cannedRows: [String]
        var cannedRPCValue: String
        var databaseError: Error?
        var isSessionActive: Bool
        var recordedSignUps: [BaseFakeRecordedCredentials]
        var recordedSignIns: [BaseFakeRecordedCredentials]
        var recordedSignOuts: Int
        var recordedUploads: [BaseFakeRecordedUpload]
        var recordedDownloads: [BaseFakeRecordedDownload]
        var recordedSelects: [BaseFakeRecordedSelect]
        var recordedRPCs: [BaseFakeRecordedRPC]
    }

    private let lock = NSLock()
    private var state: State

    init(
        authSession: SupabaseSession = SupabaseBaseFake.defaultSession,
        stateChangesEvents: [SupabaseAuthEvent] = [],
        uploadResultPath: String = "catches/catch-1.jpg",
        downloadData: Data = Data([0x0A]),
        cannedRows: [String] = [],
        cannedRPCValue: String = ""
    ) {
        state = State(
            authSession: authSession,
            authSignUpResult: nil,
            authError: nil,
            stateChangesEvents: stateChangesEvents,
            uploadResultPath: uploadResultPath,
            uploadError: nil,
            downloadData: downloadData,
            downloadError: nil,
            cannedRows: cannedRows,
            cannedRPCValue: cannedRPCValue,
            databaseError: nil,
            isSessionActive: true,
            recordedSignUps: [],
            recordedSignIns: [],
            recordedSignOuts: 0,
            recordedUploads: [],
            recordedDownloads: [],
            recordedSelects: [],
            recordedRPCs: []
        )
    }

    static let defaultUser = SupabaseUser(
        id: UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)),
        email: "angler@example.com",
        createdAt: Date(timeIntervalSinceReferenceDate: 7_500_000)
    )

    static let defaultSession = SupabaseSession(
        accessToken: "access-token-123",
        refreshToken: "refresh-token-456",
        expiresAt: Date(timeIntervalSinceReferenceDate: 7_500_000 + 3_600),
        user: defaultUser
    )

    var authSession: SupabaseSession {
        get { withLock { state.authSession } }
        set { withLock { state.authSession = newValue } }
    }

    var authSignUpResult: SupabaseSignUpResult? {
        get { withLock { state.authSignUpResult } }
        set { withLock { state.authSignUpResult = newValue } }
    }

    var authError: Error? {
        get { withLock { state.authError } }
        set { withLock { state.authError = newValue } }
    }

    var stateChangesEvents: [SupabaseAuthEvent] {
        get { withLock { state.stateChangesEvents } }
        set { withLock { state.stateChangesEvents = newValue } }
    }

    var uploadResultPath: String {
        get { withLock { state.uploadResultPath } }
        set { withLock { state.uploadResultPath = newValue } }
    }

    var uploadError: Error? {
        get { withLock { state.uploadError } }
        set { withLock { state.uploadError = newValue } }
    }

    var downloadResultData: Data {
        get { withLock { state.downloadData } }
        set { withLock { state.downloadData = newValue } }
    }

    var downloadError: Error? {
        get { withLock { state.downloadError } }
        set { withLock { state.downloadError = newValue } }
    }

    var cannedRows: [String] {
        get { withLock { state.cannedRows } }
        set { withLock { state.cannedRows = newValue } }
    }

    var cannedRPCValue: String {
        get { withLock { state.cannedRPCValue } }
        set { withLock { state.cannedRPCValue = newValue } }
    }

    var databaseError: Error? {
        get { withLock { state.databaseError } }
        set { withLock { state.databaseError = newValue } }
    }

    var isSessionActive: Bool {
        get { withLock { state.isSessionActive } }
        set { withLock { state.isSessionActive = newValue } }
    }

    var recordedSignUps: [BaseFakeRecordedCredentials] {
        withLock { state.recordedSignUps }
    }

    var recordedSignIns: [BaseFakeRecordedCredentials] {
        withLock { state.recordedSignIns }
    }

    var recordedSignOutCount: Int {
        withLock { state.recordedSignOuts }
    }

    var recordedUploads: [BaseFakeRecordedUpload] {
        withLock { state.recordedUploads }
    }

    var recordedDownloads: [BaseFakeRecordedDownload] {
        withLock { state.recordedDownloads }
    }

    var recordedSelects: [BaseFakeRecordedSelect] {
        withLock { state.recordedSelects }
    }

    var recordedRPCs: [BaseFakeRecordedRPC] {
        withLock { state.recordedRPCs }
    }

    func reset() {
        withLock {
            state.recordedSignUps = []
            state.recordedSignIns = []
            state.recordedSignOuts = 0
            state.recordedUploads = []
            state.recordedDownloads = []
            state.recordedSelects = []
            state.recordedRPCs = []
        }
    }

    func signUp(email: String, password: String) async throws -> SupabaseSignUpResult {
        let result = withLock { () -> (error: Error?, session: SupabaseSession, override: SupabaseSignUpResult?) in
            state.recordedSignUps.append(BaseFakeRecordedCredentials(email: email, password: password))
            return (state.authError, state.authSession, state.authSignUpResult)
        }
        try throwIfSet(result.error)
        return result.override ?? .signedIn(result.session)
    }

    func signIn(email: String, password: String) async throws -> SupabaseSession {
        let result = withLock { () -> (error: Error?, session: SupabaseSession) in
            state.recordedSignIns.append(BaseFakeRecordedCredentials(email: email, password: password))
            return (state.authError, state.authSession)
        }
        try throwIfSet(result.error)
        return result.session
    }

    func signOut() async throws {
        let error = withLock { () -> Error? in
            state.recordedSignOuts += 1
            return state.authError
        }
        try throwIfSet(error)
    }

    func currentUser() async -> SupabaseUser? {
        withLock { state.isSessionActive ? state.authSession.user : nil }
    }

    func currentSession() async throws -> SupabaseSession? {
        let result = withLock { () -> (error: Error?, session: SupabaseSession?) in
            (state.authError, state.isSessionActive ? state.authSession : nil)
        }
        try throwIfSet(result.error)
        return result.session
    }

    func stateChanges() -> AsyncStream<SupabaseAuthEvent> {
        let events = withLock { state.stateChangesEvents }
        return AsyncStream<SupabaseAuthEvent> { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func upload(
        bucket: String,
        path: String,
        data: Data,
        options: SupabaseUploadOptions?
    ) async throws -> String {
        let result = withLock { () -> (error: Error?, path: String) in
            state.recordedUploads.append(
                BaseFakeRecordedUpload(bucket: bucket, path: path, data: data, options: options)
            )
            return (state.uploadError, state.uploadResultPath)
        }
        try throwIfSet(result.error)
        return result.path
    }

    func download(bucket: String, path: String) async throws -> Data {
        let result = withLock { () -> (error: Error?, data: Data) in
            state.recordedDownloads.append(BaseFakeRecordedDownload(bucket: bucket, path: path))
            return (state.downloadError, state.downloadData)
        }
        try throwIfSet(result.error)
        return result.data
    }

    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T] {
        let result = withLock { () -> (error: Error?, rows: [String]) in
            state.recordedSelects.append(
                BaseFakeRecordedSelect(columns: columns, table: table, filters: filters, limit: limit)
            )
            return (state.databaseError, state.cannedRows)
        }
        try throwIfSet(result.error)
        if let rows = result.rows as? [T] {
            return rows
        }
        return try result.rows.compactMap { row in
            try JSONDecoder().decode(T.self, from: Data(row.utf8))
        }
    }

    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T {
        let result = withLock { () -> (error: Error?, value: String) in
            state.recordedRPCs.append(BaseFakeRecordedRPC(function: function, arguments: arguments))
            return (state.databaseError, state.cannedRPCValue)
        }
        try throwIfSet(result.error)
        if let value = result.value as? T {
            return value
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(result.value.utf8))
        } catch {
            throw SupabaseBaseFakeError(reason: "rpc decode failed: \(error)")
        }
    }

    func rpcVoid(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws {
        let error = withLock { () -> Error? in
            state.recordedRPCs.append(BaseFakeRecordedRPC(function: function, arguments: arguments))
            return state.databaseError
        }
        try throwIfSet(error)
    }

    private func throwIfSet(_ error: Error?) throws {
        if let error {
            throw error
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}