import Foundation
import Observation

@MainActor
@Observable
final class AccountViewModel {
    private(set) var sessionState: AccountSessionState = .signedOut
    private(set) var profile: AccountProfile?
    private(set) var favorites: [FavoriteSpot] = []
    private(set) var isSyncing = false
    private(set) var lastSyncResult: CatchSyncResult?
    private(set) var errorMessage: String?
    private(set) var infoMessage: String?
    private(set) var avatarData: Data?

    var sessionUser: SupabaseUser? {
        if case .signedIn(let user) = sessionState {
            return user
        }
        return nil
    }

    @ObservationIgnored
    nonisolated(unsafe) private(set) var sessionStateTask: Task<Void, Never>?

    private let auth: any AccountSessionManaging
    private let profileService: any ProfileManaging
    private let favoritesService: any FavoritesPresenting
    private let syncService: any CatchSynchronizing
    private(set) var isSubmitting = false

    init(
        auth: any AccountSessionManaging,
        profile: any ProfileManaging,
        favorites: any FavoritesPresenting,
        sync: any CatchSynchronizing
    ) {
        self.auth = auth
        self.profileService = profile
        self.favoritesService = favorites
        self.syncService = sync
        let consumeTask = Task { [weak self] in
            guard let self else { return }
            await self.observeSessionState()
        }
        self.sessionStateTask = consumeTask
    }

    func signUp(email: String, password: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        infoMessage = nil
        do {
            let outcome = try await auth.signUp(email: email, password: password)
            if outcome == .emailConfirmationRequired {
                infoMessage = "Cuenta creada. Revisa tu email para confirmar la cuenta antes de iniciar sesión."
            }
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        infoMessage = nil
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    func signOut() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await auth.signOut()
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    func saveDisplayName(_ name: String) async {
        do {
            try await profileService.updateDisplayName(name)
            profile = try await profileService.profile()
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    func uploadAvatar(data: Data, contentType: String) async {
        do {
            _ = try await profileService.updateAvatar(data: data, contentType: contentType)
            profile = try await profileService.profile()
            avatarData = data
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    func toggleFavorite(_ spotID: UUID) async {
        let target = !favorites.contains { $0.spotID == spotID }
        do {
            try await favoritesService.setFavorite(spotID: spotID, isFavorite: target)
            favorites = try await favoritesService.favorites()
        } catch {
            if let real = try? await favoritesService.favorites() {
                favorites = real
            }
            errorMessage = Self.errorText(error)
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        guard case .signedIn(let user) = sessionState else {
            errorMessage = CatchSyncError.noSession.localizedDescription
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            lastSyncResult = try await syncService.sync(userID: user.id)
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    private func observeSessionState() async {
        if let user = await auth.currentUser {
            await handleSessionChange(.signedIn(user))
        }
        for await state in auth.sessionState {
            await handleSessionChange(state)
        }
    }

    private func handleSessionChange(_ state: AccountSessionState) async {
        sessionState = state
        switch state {
        case .signedIn:
            await loadPersonalData()
        case .signedOut:
            clearPersonalData()
        }
    }

    private func loadPersonalData() async {
        do {
            profile = try await profileService.profile()
            if let path = profile?.avatarPath {
                do {
                    avatarData = try await profileService.avatarData(avatarPath: path)
                } catch {
                    avatarData = nil
                    errorMessage = Self.errorText(error)
                }
            } else {
                avatarData = nil
            }
        } catch {
            errorMessage = Self.errorText(error)
        }
        do {
            favorites = try await favoritesService.favorites()
        } catch {
            errorMessage = Self.errorText(error)
        }
    }

    private func clearPersonalData() {
        profile = nil
        favorites = []
        lastSyncResult = nil
        avatarData = nil
        errorMessage = nil
        infoMessage = nil
    }

    private static func errorText(_ error: Error) -> String {
        error.localizedDescription
    }

    deinit {
        sessionStateTask?.cancel()
    }
}