import SwiftUI
import MapKit

@MainActor
struct SpotMapView: View {
    @State private var viewModel: SpotMapViewModel
    @State private var cameraPosition: MapCameraPosition
    private let detailFactory: @MainActor (Spot) -> SpotDetailView

    init(
        viewModel: SpotMapViewModel,
        detailFactory: @escaping @MainActor (Spot) -> SpotDetailView
    ) {
        _viewModel = State(initialValue: viewModel)
        self.detailFactory = detailFactory
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(spotRegion: viewModel.region)))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationStack {
            Group {
                switch viewModel.state {
                case .unavailable:
                    unavailableView
                case .loading, .loaded, .failed:
                    mapContent
                }
            }
            .navigationTitle("Mapa")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(
                item: Binding(
                    get: { viewModel.selectedSpot },
                    set: { newValue in
                        if let spot = newValue {
                            viewModel.select(spot)
                        } else {
                            viewModel.clearSelection()
                        }
                    }
                )
            ) { spot in
                detailFactory(spot)
            }
        }
        .task {
            await viewModel.loadSpots()
        }
    }

    private var mapContent: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(viewModel.spots) { spot in
                    Annotation(spot.name, coordinate: spot.coordinate.mkCoordinate) {
                        annotationContent(for: spot)
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.updateRegion(context.region.spotRegion)
            }
            .accessibilityIdentifier("spotMap.map")

            statusBar
                .padding(.top, 8)

            VStack(spacing: 8) {
                Spacer()
                nearbyNoticeBar
                nearbyButton
            }
            .padding(.bottom, 16)
        }
    }

    private func annotationContent(for spot: Spot) -> some View {
        let isFavorite = viewModel.isFavorite(spot)
        return Button {
            viewModel.select(spot)
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: spot.category.systemImage)
                        .font(.subheadline)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .offset(x: 8, y: -6)
                    }
                }
                if let meters = spot.distanceMeters {
                    Text(Self.distanceText(meters))
                        .font(.caption2.weight(.semibold))
                }
            }
            .padding(6)
            .background(isFavorite ? .red.opacity(0.12) : .white, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isFavorite ? "spotMap.annotation.favorite" : "spotMap.annotation")
    }

    @ViewBuilder
    private var statusBar: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Cargando spots…")
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("spotMap.loading")
        case .failed:
            HStack(spacing: 12) {
                Label(SpotMapViewModel.loadFailedMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                Spacer()
                Button("Reintentar") {
                    Task { await viewModel.loadSpots() }
                }
                .accessibilityIdentifier("spotMap.retry")
            }
            .padding()
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("spotMap.error")
        default:
            EmptyView()
        }
    }

    private var nearbyButton: some View {
        Button {
            Task { await viewModel.showNearby() }
        } label: {
            Label("Cerca de mí", systemImage: "location.fill.viewfinder")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .shadow(radius: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("spotMap.nearbyButton")
        .disabled(viewModel.state != .loaded)
    }

    @ViewBuilder
    private var nearbyNoticeBar: some View {
        if let message = viewModel.nearbyMessage {
            HStack(spacing: 12) {
                Label(message, systemImage: "location.slash.fill")
                    .font(.subheadline)
                Spacer()
                Button {
                    viewModel.dismissNearbyNotice()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("spotMap.dismissNearbyNotice")
            }
            .padding()
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("spotMap.nearbyNotice")
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(SpotMapViewModel.unavailableMessage, systemImage: "map")
        } description: {
            Text("La capa de datos no está disponible en este momento.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spotMap.unavailable")
    }

    private static func distanceText(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }
}

private extension MKCoordinateRegion {
    init(spotRegion: SpotRegion) {
        self.init(
            center: spotRegion.center.mkCoordinate,
            latitudinalMeters: spotRegion.latitudinalMeters,
            longitudinalMeters: spotRegion.longitudinalMeters
        )
    }

    var spotRegion: SpotRegion {
        let cosLatitude = max(cos(center.latitude * .pi / 180), 0.01)
        return SpotRegion(
            center: LocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            latitudinalMeters: max(span.latitudeDelta, 0) * 111_320,
            longitudinalMeters: max(span.longitudeDelta, 0) * 111_320 * cosLatitude
        )
    }
}

private extension LocationCoordinate2D {
    var mkCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension SpotCategory {
    var systemImage: String {
        switch self {
        case .river: "water.waves"
        case .lake: "drop.fill"
        case .sea: "fish.fill"
        case .shore: "mountain.2.fill"
        }
    }
}