import SwiftUI

@MainActor
struct SpotDetailView: View {
    @State private var viewModel: SpotDetailViewModel

    init(viewModel: SpotDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 4) {
                    Text(viewModel.spot.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("spotDetail.name")
                    Text(categoryTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("spotDetail.category")
                }

                summarySection
                coordinatesSection

                favoriteButton
                sessionRequiredNotice
                toggleErrorNotice
            }
            .padding()
        }
        .navigationTitle("Detalle del spot")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.isLoading else { return }
            await viewModel.load()
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Resumen", systemImage: "text.alignleft")
                .font(.headline)
            Text(viewModel.spot.summary)
                .font(.body)
                .accessibilityIdentifier("spotDetail.summary")
        }
    }

    private var coordinatesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Coordenadas", systemImage: "mappin.and.ellipse")
                .font(.headline)
            Text(formattedCoordinates)
                .font(.body)
                .accessibilityIdentifier("spotDetail.coordinates")
        }
    }

    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavorite() }
        } label: {
            Label(
                viewModel.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos",
                systemImage: viewModel.isFavorite ? "heart.fill" : "heart"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isFavorite ? .red : .accentColor)
        .accessibilityIdentifier("spotDetail.favoriteButton")
        .disabled(viewModel.isLoading)
    }

    @ViewBuilder
    private var sessionRequiredNotice: some View {
        if viewModel.sessionRequiredNotice {
            HStack(spacing: 12) {
                Label(SpotDetailViewModel.sessionRequiredMessage, systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .accessibilityIdentifier("spotDetail.sessionRequired")
                Spacer()
                Button {
                    viewModel.dismissSessionNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("spotDetail.dismissSessionRequired")
            }
            .padding()
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var toggleErrorNotice: some View {
        if let message = viewModel.toggleErrorMessage {
            HStack(spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .accessibilityIdentifier("spotDetail.toggleError")
                Spacer()
                Button {
                    viewModel.dismissToggleError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("spotDetail.dismissToggleError")
            }
            .padding()
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var categoryTitle: String {
        switch viewModel.spot.category {
        case .river: "Río"
        case .lake: "Lago o embalse"
        case .sea: "Mar"
        case .shore: "Costa u orilla"
        }
    }

    private var formattedCoordinates: String {
        String(format: "%.4f, %.4f", viewModel.spot.latitude, viewModel.spot.longitude)
    }
}