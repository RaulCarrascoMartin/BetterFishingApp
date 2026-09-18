import SwiftUI
import UIKit

extension Catch: Hashable {
    static func == (lhs: Catch, rhs: Catch) -> Bool {
        lhs.id == rhs.id
            && lhs.species == rhs.species
            && lhs.photoPath == rhs.photoPath
            && lhs.date == rhs.date
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(species)
        hasher.combine(photoPath)
        hasher.combine(date)
        hasher.combine(location)
        hasher.combine(notes)
        hasher.combine(createdAt)
    }
}

extension LocationCoordinate2D: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

@MainActor
struct CatchLogView: View {
    @State private var viewModel: CatchLogViewModel
    private let thumbnailProvider: (Catch) -> Data?
    private let detailViewModelFactory: @MainActor (Catch) -> CatchDetailViewModel

    init(
        viewModel: CatchLogViewModel,
        thumbnailProvider: @escaping (Catch) -> Data?,
        detailViewModelFactory: @escaping @MainActor (Catch) -> CatchDetailViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.thumbnailProvider = thumbnailProvider
        self.detailViewModelFactory = detailViewModelFactory
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loadFailed:
                loadFailedView
            case .initial, .loading:
                ProgressView("Cargando capturas…")
                    .accessibilityIdentifier("log.loading")
            case .loaded:
                if viewModel.isEmpty {
                    emptyStateView
                } else {
                    list
                }
            }
        }
        .navigationTitle("Capturas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var list: some View {
        List(viewModel.catches) { entry in
            NavigationLink(value: entry) {
                row(for: entry)
            }
            .accessibilityIdentifier("log.row")
        }
        .navigationDestination(for: Catch.self) { entry in
            CatchDetailView(viewModel: detailViewModelFactory(entry))
        }
    }

    private func row(for entry: Catch) -> some View {
        HStack(spacing: 12) {
            thumbnail(for: entry)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("log.photo")
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.species.commonName)
                    .font(.headline)
                    .accessibilityIdentifier("log.speciesName")
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("log.date")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for entry: Catch) -> some View {
        if let data = thumbnailProvider(entry), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.3))
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Todavía no tienes capturas", systemImage: "tray")
        } description: {
            Text("Guarda tu primera captura desde el escáner para empezar tu historial.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.emptyState")
    }

    private var loadFailedView: some View {
        ContentUnavailableView {
            Label(CatchLogViewModel.loadFailedMessage, systemImage: "exclamationmark.triangle")
        } description: {
            Text(viewModel.errorMessage ?? CatchLogViewModel.loadFailedMessage)
                .accessibilityIdentifier("log.errorMessage")
        } actions: {
            Button("Reintentar") {
                Task { await viewModel.load() }
            }
            .accessibilityIdentifier("log.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("log.loadFailed")
    }
}