import Foundation
import Observation

@MainActor
@Observable
final class SpotDetailViewModel {
    static let sessionRequiredMessage = "Inicia sesión para guardar favoritos"
    static let toggleFailedMessage = "No se pudo actualizar el favorito"

    let spot: Spot

    private(set) var isFavorite = false
    private(set) var isLoading = true
    private(set) var sessionRequiredNotice = false
    private(set) var toggleErrorMessage: String?
    @ObservationIgnored
    nonisolated(unsafe) private(set) var stateChangesTask: Task<Void, Never>?

    private let repository: any SpotRepository
    private let auth: any SupabaseAuthProviding

    init(repository: any SpotRepository, auth: any SupabaseAuthProviding, spot: Spot) {
        self.repository = repository
        self.auth = auth
        self.spot = spot
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        sessionRequiredNotice = false
        toggleErrorMessage = nil
        await refreshFavoriteState()
        stateChangesTask = observeAuthStateChanges()
    }

    func dismissSessionNotice() {
        sessionRequiredNotice = false
    }

    func dismissToggleError() {
        toggleErrorMessage = nil
    }

    func toggleFavorite() async {
        toggleErrorMessage = nil
        guard await auth.currentUser() != nil else {
            sessionRequiredNotice = true
            return
        }
        sessionRequiredNotice = false
        let target = !isFavorite
        isLoading = true
        defer { isLoading = false }
        do {
            try await repository.setFavorite(spotID: spot.id, isFavorite: target)
            isFavorite = target
        } catch {
            toggleErrorMessage = Self.toggleFailedMessage
        }
    }

    private func refreshFavoriteState() async {
        guard await auth.currentUser() != nil else {
            isFavorite = false
            return
        }
        do {
            let favorites = try await repository.favoriteSpotIDs()
            isFavorite = favorites.contains(spot.id)
        } catch {
            isFavorite = false
        }
    }

    private func observeAuthStateChanges() -> Task<Void, Never> {
        Task { [weak self] in
            guard let auth = self?.auth else { return }
            for await event in auth.stateChanges() {
                guard let self else { return }
                switch event {
                case .signedIn, .sessionRestored:
                    sessionRequiredNotice = false
                    await refreshFavoriteState()
                case .signedOut:
                    isFavorite = false
                    sessionRequiredNotice = true
                    toggleErrorMessage = nil
                }
            }
        }
    }

    deinit {
        stateChangesTask?.cancel()
    }
}