import SwiftUI

@MainActor
struct FavoritesListView: View {
    @State private var viewModel: AccountViewModel

    init(viewModel: AccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if isSignedOut {
                sessionRequiredView
            } else if viewModel.favorites.isEmpty {
                emptyStateView
            } else {
                favoritesList
            }
        }
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isSignedOut: Bool {
        if case .signedOut = viewModel.sessionState { return true }
        return false
    }

    private var favoritesList: some View {
        List {
            ForEach(viewModel.favorites) { favorite in
                row(for: favorite)
            }
            if let message = viewModel.errorMessage {
                errorNotice(message)
            }
        }
    }

    private func row(for favorite: FavoriteSpot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(favorite.name)
                    .font(.headline)
                if let category = favorite.category {
                    Text(categoryTitle(category))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await viewModel.toggleFavorite(favorite.spotID) }
            } label: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorites.remove")
        }
    }

    private var sessionRequiredView: some View {
        HStack(spacing: 12) {
            Label("Para ver tus favoritos es necesario iniciar sesión.", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("favorites.sessionRequired")
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("Todavía no tienes favoritos", systemImage: "heart")
        } description: {
            Text("Marca spots como favoritos desde el mapa para verlos aquí.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("favorites.emptyState")
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("favorites.error")
    }

    private func categoryTitle(_ rawValue: String) -> String {
        switch SpotCategory(rawValue: rawValue) {
        case .river: "Río"
        case .lake: "Lago o embalse"
        case .sea: "Mar"
        case .shore: "Costa u orilla"
        case .none: rawValue
        }
    }
}