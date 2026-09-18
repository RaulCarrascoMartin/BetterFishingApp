import Foundation
import Observation

@MainActor
@Observable
final class CatchLogViewModel {
    enum State: Equatable {
        case initial
        case loading
        case loaded
        case loadFailed
    }

    static let loadFailedMessage = "No se pudo cargar el historial"

    private(set) var state: State
    private(set) var catches: [Catch] = []

    var isEmpty: Bool { catches.isEmpty }
    var errorMessage: String? {
        switch state {
        case .loadFailed: Self.loadFailedMessage
        default: nil
        }
    }

    private let repository: any CatchRepository

    init(repository: any CatchRepository) {
        self.repository = repository
        self.state = .initial
    }

    func load() async {
        state = .loading
        do {
            let loadedCatches = try await repository.listCatches()
            catches = Self.ordered(loadedCatches)
            state = .loaded
        } catch {
            state = .loadFailed
        }
    }

    private static func ordered(_ entries: [Catch]) -> [Catch] {
        entries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }
}