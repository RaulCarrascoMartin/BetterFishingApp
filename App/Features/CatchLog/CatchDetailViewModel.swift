import Foundation
import Observation

@MainActor
@Observable
final class CatchDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case notFound
        case loadFailed
        case editing
        case saving
        case saveFailed
        case deletingConfirmation
        case deleting
        case deleteFailed
        case removed
    }

    static let loadFailedMessage = "No se pudo cargar la captura"
    static let saveFailedMessage = "No se pudo guardar la captura"
    static let deleteFailedMessage = "No se pudo eliminar la captura"

    private(set) var state: State
    private(set) var catchEntry: Catch?
    private(set) var thumbnailData: Data?

    var editDate: Date
    var editLocation: LocationCoordinate2D?
    var editNotes: String

    var speciesCommonName: String? { catchEntry?.species.commonName }
    var speciesScientificName: String? { catchEntry?.species.scientificName }
    var notes: String? { catchEntry?.notes }
    var location: LocationCoordinate2D? { catchEntry?.location }
    var formattedDate: String? {
        guard let date = catchEntry?.date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    var errorMessage: String? {
        switch state {
        case .loadFailed: Self.loadFailedMessage
        case .saveFailed: Self.saveFailedMessage
        case .deleteFailed: Self.deleteFailedMessage
        default: nil
        }
    }

    private let id: UUID
    private let repository: any CatchRepository
    private let photoProvider: (Catch) -> Data?

    init(
        id: UUID,
        repository: any CatchRepository,
        photoProvider: @escaping (Catch) -> Data? = { _ in nil }
    ) {
        self.id = id
        self.repository = repository
        self.photoProvider = photoProvider
        self.state = .loading
        self.editDate = Date()
        self.editNotes = ""
    }

    func load() async {
        state = .loading
        do {
            guard let catchEntry = try await repository.getCatch(id: id) else {
                state = .notFound
                return
            }
            apply(catchEntry)
            state = .loaded
        } catch {
            state = .loadFailed
        }
    }

    func startEditing() {
        guard state == .loaded, let catchEntry else { return }
        seedEdits(from: catchEntry)
        state = .editing
    }

    func cancel() {
        guard state == .editing || state == .saveFailed || state == .loadFailed else { return }
        state = .loaded
    }

    func save() async {
        guard state == .editing || state == .saveFailed, catchEntry != nil else { return }
        state = .saving
        do {
            try await repository.updateCatch(id: id, date: editDate, location: editLocation, notes: editNotes)
            if let updated = try await repository.getCatch(id: id) {
                apply(updated)
            }
            state = .loaded
        } catch {
            state = .saveFailed
        }
    }

    func dismissError() {
        guard state == .loadFailed || state == .saveFailed || state == .deleteFailed else { return }
        state = .loaded
    }

    func beginDelete() {
        guard state == .loaded else { return }
        state = .deletingConfirmation
    }

    func cancelDelete() {
        guard state == .deletingConfirmation else { return }
        state = .loaded
    }

    func confirmDelete() async {
        guard state == .deletingConfirmation || state == .deleteFailed else { return }
        state = .deleting
        do {
            try await repository.deleteCatch(id: id)
            catchEntry = nil
            thumbnailData = nil
            state = .removed
        } catch {
            state = .deleteFailed
        }
    }

    private func apply(_ catchEntry: Catch) {
        self.catchEntry = catchEntry
        thumbnailData = photoProvider(catchEntry)
        seedEdits(from: catchEntry)
    }

    private func seedEdits(from catchEntry: Catch) {
        editDate = catchEntry.date
        editLocation = catchEntry.location
        editNotes = catchEntry.notes
    }
}