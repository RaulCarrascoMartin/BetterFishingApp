import Foundation
import XCTest

@testable import BetterFishing

@MainActor
final class AccountViewModelTests: XCTestCase {

    private let user = SupabaseUser(
        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)),
        email: "angler@example.com",
        createdAt: Date(timeIntervalSinceReferenceDate: 7_500_000)
    )

    private func makeProfile() -> AccountProfile {
        AccountProfile(userID: user.id, displayName: "Marina", avatarPath: nil)
    }

    private func makeFavorite(id: UUID = UUID()) -> FavoriteSpot {
        FavoriteSpot(spotID: id, name: "Embalse de Sau", category: "lake")
    }

    private func makeViewModel(
        auth: AccountSessionFake,
        profile: ProfileFake,
        favorites: FavoritesFake,
        sync: SyncFake
    ) -> AccountViewModel {
        AccountViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)
    }

    func testEmittingSignedOutClearsPersonalData() async {
        let auth = AccountSessionFake(currentUser: user)
        let profile = ProfileFake(profile: makeProfile())
        let favorites = FavoritesFake(favorites: [makeFavorite()])
        let sync = SyncFake(result: CatchSyncResult(pushed: 1, pulled: 0, skipped: 2))
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await waitUntil { viewModel.profile != nil && !viewModel.favorites.isEmpty }
        await viewModel.sync()
        XCTAssertNotNil(viewModel.lastSyncResult)

        auth.emit(.signedOut)

        await waitUntil { viewModel.profile == nil }
        XCTAssertEqual(viewModel.sessionState, .signedOut)
        XCTAssertNil(viewModel.profile)
        XCTAssertTrue(viewModel.favorites.isEmpty)
        XCTAssertNil(viewModel.lastSyncResult)
    }

    func testSignInLoadsProfileAndFavorites() async {
        let auth = AccountSessionFake()
        auth.nextUser = user
        let profile = ProfileFake(profile: makeProfile())
        let favorite = makeFavorite()
        let favorites = FavoritesFake(favorites: [favorite])
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await viewModel.signIn(email: "angler@example.com", password: "correct-horse")

        await waitUntil { viewModel.profile != nil && !viewModel.favorites.isEmpty }
        XCTAssertEqual(viewModel.profile, makeProfile())
        XCTAssertEqual(viewModel.favorites, [favorite])
        XCTAssertEqual(viewModel.sessionUser?.email, "angler@example.com")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSignOutClearsAndKeepsNothingFromPreviousAccount() async {
        let auth = AccountSessionFake(currentUser: user)
        let profile = ProfileFake(profile: makeProfile())
        let favorites = FavoritesFake(favorites: [makeFavorite()])
        let sync = SyncFake(result: CatchSyncResult(pushed: 1, pulled: 0, skipped: 2))
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await waitUntil { viewModel.profile != nil && !viewModel.favorites.isEmpty }
        await viewModel.sync()
        XCTAssertNotNil(viewModel.lastSyncResult)

        await viewModel.signOut()

        await waitUntil { viewModel.sessionState == .signedOut }
        XCTAssertNil(viewModel.profile)
        XCTAssertTrue(viewModel.favorites.isEmpty)
        XCTAssertNil(viewModel.lastSyncResult)
        XCTAssertNil(viewModel.sessionUser)
    }

    func testFailedSignInShowsTypedErrorAndStaysSignedOut() async {
        let auth = AccountSessionFake()
        auth.error = AccountError.signInFailed("credenciales inválidas")
        let profile = ProfileFake(profile: makeProfile())
        let favorites = FavoritesFake()
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await viewModel.signIn(email: "angler@example.com", password: "wrong-password")

        XCTAssertEqual(
            viewModel.errorMessage,
            AccountError.signInFailed("credenciales inválidas").localizedDescription
        )
        XCTAssertEqual(viewModel.sessionState, .signedOut)
        XCTAssertNil(viewModel.sessionUser)
    }

    func testSaveDisplayNameFailurePreservesPreviousVisibleProfile() async {
        let auth = AccountSessionFake(currentUser: user)
        let profile = ProfileFake(profile: makeProfile())
        profile.updateNameError = AccountProfileError.updateFailed("red caída")
        let favorites = FavoritesFake()
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await waitUntil { viewModel.profile != nil }
        XCTAssertEqual(viewModel.profile, makeProfile())

        await viewModel.saveDisplayName("Nuevo Nombre")

        XCTAssertEqual(viewModel.profile, makeProfile(), "Un fallo al guardar conserva el perfil anterior visible")
        XCTAssertEqual(
            viewModel.errorMessage,
            AccountProfileError.updateFailed("red caída").localizedDescription
        )
    }

    func testToggleFavoriteFailureReQueriesRealState() async {
        let auth = AccountSessionFake(currentUser: user)
        let profile = ProfileFake(profile: makeProfile())
        let favorite = makeFavorite()
        let favorites = FavoritesFake(favorites: [favorite])
        favorites.setFavoriteError = FavoritesError.removeFailed("red caída")
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await waitUntil { viewModel.profile != nil && !viewModel.favorites.isEmpty }
        XCTAssertEqual(viewModel.favorites, [favorite])

        await viewModel.toggleFavorite(favorite.spotID)

        XCTAssertEqual(viewModel.favorites, [favorite], "Un fallo de toggle conserva el estado real re-consultado")
        XCTAssertEqual(
            viewModel.errorMessage,
            FavoritesError.removeFailed("red caída").localizedDescription
        )
    }

    func testToggleFavoriteSuccessReQueriesRealState() async {
        let auth = AccountSessionFake(currentUser: user)
        let profile = ProfileFake(profile: makeProfile())
        let favorite = makeFavorite()
        let favorites = FavoritesFake()
        favorites.knownSpots = [favorite.spotID: favorite]
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await waitUntil { viewModel.profile != nil }
        XCTAssertTrue(viewModel.favorites.isEmpty)

        await viewModel.toggleFavorite(favorite.spotID)

        XCTAssertEqual(viewModel.favorites, [favorite], "Tras el toggle con éxito la lista refleja el estado real")
    }

    func testSyncWithoutSessionReportsError() async {
        let auth = AccountSessionFake()
        let profile = ProfileFake(profile: makeProfile())
        let favorites = FavoritesFake()
        let sync = SyncFake()
        let viewModel = makeViewModel(auth: auth, profile: profile, favorites: favorites, sync: sync)

        await viewModel.sync()

        XCTAssertEqual(viewModel.errorMessage, CatchSyncError.noSession.localizedDescription)
        XCTAssertNil(viewModel.lastSyncResult)
        XCTAssertFalse(viewModel.isSyncing)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Condición no alcanzada antes del timeout")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class AccountSessionFake: AccountSessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentUserStorage: SupabaseUser?
    private var errorStorage: Error?
    private var nextUserStorage: SupabaseUser?
    private var recordedSignInEmailsStorage: [String] = []
    private let stream: AsyncStream<AccountSessionState>
    private let continuation: AsyncStream<AccountSessionState>.Continuation

    init(currentUser: SupabaseUser? = nil) {
        self.currentUserStorage = currentUser
        let (stream, continuation) = AsyncStream<AccountSessionState>.makeStream(bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    var currentUser: SupabaseUser? {
        get async {
            withLock { currentUserStorage }
        }
    }

    var sessionState: AsyncStream<AccountSessionState> {
        stream
    }

    var nextUser: SupabaseUser? {
        get {
            withLock { nextUserStorage }
        }
        set {
            withLock { nextUserStorage = newValue }
        }
    }

    var error: Error? {
        get {
            withLock { errorStorage }
        }
        set {
            withLock { errorStorage = newValue }
        }
    }

    var recordedSignInEmails: [String] {
        withLock { recordedSignInEmailsStorage }
    }

    func emit(_ state: AccountSessionState) {
        continuation.yield(state)
    }

    func signUp(email: String, password: String) async throws {
        let error = withLock { errorStorage }
        try throwIfSet(error)
        let user = withLock { nextUserStorage } ?? makeUser(email: email)
        withLock { currentUserStorage = user }
        continuation.yield(.signedIn(user))
    }

    func signIn(email: String, password: String) async throws {
        let error = withLock { errorStorage }
        try throwIfSet(error)
        let user = withLock { nextUserStorage } ?? makeUser(email: email)
        withLock { currentUserStorage = user }
        continuation.yield(.signedIn(user))
    }

    func signOut() async throws {
        let error = withLock { errorStorage }
        try throwIfSet(error)
        withLock { currentUserStorage = nil }
        continuation.yield(.signedOut)
    }

    private func makeUser(email: String) -> SupabaseUser {
        SupabaseUser(id: UUID(), email: email, createdAt: Date())
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

private final class ProfileFake: ProfileManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var profileStorage: AccountProfile?
    private var profileErrorStorage: Error?
    private var updateNameErrorStorage: Error?
    private let updateAvatarErrorStorage: Error?

    init(profile: AccountProfile? = nil) {
        self.profileStorage = profile
        self.updateAvatarErrorStorage = nil
    }

    var updateNameError: Error? {
        get {
            withLock { updateNameErrorStorage }
        }
        set {
            withLock { updateNameErrorStorage = newValue }
        }
    }

    func profile() async throws -> AccountProfile {
        let result = withLock { () -> (Error?, AccountProfile?) in
            (profileErrorStorage, profileStorage)
        }
        try throwIfSet(result.0)
        guard let profile = result.1 else {
            throw AccountProfileError.loadFailed("sin perfil")
        }
        return profile
    }

    func updateDisplayName(_ name: String) async throws {
        let error = withLock { updateNameErrorStorage }
        try throwIfSet(error)
        let next = withLock { () -> AccountProfile? in
            guard let current = profileStorage else { return nil }
            let updated = AccountProfile(userID: current.userID, displayName: name, avatarPath: current.avatarPath)
            profileStorage = updated
            return updated
        }
        guard next != nil else {
            throw AccountProfileError.updateFailed("sin perfil previo")
        }
    }

    func updateAvatar(data: Data, contentType: String) async throws -> String {
        let error = withLock { updateAvatarErrorStorage }
        try throwIfSet(error)
        let path = withLock { () -> String? in
            guard let current = profileStorage else { return nil }
            let avatarPath = "\(current.userID.uuidString)/avatar.jpg"
            profileStorage = AccountProfile(userID: current.userID, displayName: current.displayName, avatarPath: avatarPath)
            return avatarPath
        }
        guard let path else {
            throw AccountProfileError.uploadAvatarFailed("sin perfil previo")
        }
        return path
    }

    func avatarData(avatarPath: String) async throws -> Data? {
        nil
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

private final class FavoritesFake: FavoritesPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var favoritesStorage: [FavoriteSpot]
    private var favoritesErrorStorage: Error?
    private var setFavoriteErrorStorage: Error?
    private var knownSpotsStorage: [UUID: FavoriteSpot] = [:]

    init(favorites: [FavoriteSpot] = []) {
        self.favoritesStorage = favorites
    }

    var favoritesError: Error? {
        get {
            withLock { favoritesErrorStorage }
        }
        set {
            withLock { favoritesErrorStorage = newValue }
        }
    }

    var setFavoriteError: Error? {
        get {
            withLock { setFavoriteErrorStorage }
        }
        set {
            withLock { setFavoriteErrorStorage = newValue }
        }
    }

    var knownSpots: [UUID: FavoriteSpot] {
        get {
            withLock { knownSpotsStorage }
        }
        set {
            withLock { knownSpotsStorage = newValue }
        }
    }

    func favorites() async throws -> [FavoriteSpot] {
        let result = withLock { () -> (Error?, [FavoriteSpot]) in
            (favoritesErrorStorage, favoritesStorage.sorted { $0.spotID.uuidString < $1.spotID.uuidString })
        }
        try throwIfSet(result.0)
        return result.1
    }

    func favoriteSpotIDs() async throws -> Set<UUID> {
        let list = try await favorites()
        return Set(list.map(\.spotID))
    }

    func isFavorite(spotID: UUID) async throws -> Bool {
        try await favoriteSpotIDs().contains(spotID)
    }

    func setFavorite(spotID: UUID, isFavorite: Bool) async throws {
        let error = withLock { setFavoriteErrorStorage }
        try throwIfSet(error)
        withLock {
            if isFavorite {
                if !favoritesStorage.contains(where: { $0.spotID == spotID }) {
                    favoritesStorage.append(knownSpotsStorage[spotID] ?? FavoriteSpot(spotID: spotID, name: "Favorito", category: nil))
                }
            } else {
                favoritesStorage.removeAll { $0.spotID == spotID }
            }
        }
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

private final class SyncFake: CatchSynchronizing, @unchecked Sendable {
    private let lock = NSLock()
    private var resultStorage: CatchSyncResult
    private var errorStorage: Error?
    private var recordedUserIDsStorage: [UUID] = []

    init(result: CatchSyncResult = CatchSyncResult(pushed: 0, pulled: 0, skipped: 0)) {
        self.resultStorage = result
    }

    var error: Error? {
        get {
            withLock { errorStorage }
        }
        set {
            withLock { errorStorage = newValue }
        }
    }

    var recordedUserIDs: [UUID] {
        withLock { recordedUserIDsStorage }
    }

    func sync(userID: UUID) async throws -> CatchSyncResult {
        let result = withLock { () -> (Error?, CatchSyncResult) in
            recordedUserIDsStorage.append(userID)
            return (errorStorage, resultStorage)
        }
        try throwIfSet(result.0)
        return result.1
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