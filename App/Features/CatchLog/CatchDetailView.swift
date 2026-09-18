import SwiftUI
import UIKit

struct CatchDetailView: View {
    @State private var viewModel: CatchDetailViewModel
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingErrorAlert = false
    @State private var deleteDecisionMade = false
    @State private var errorDecisionMade = false

    init(viewModel: CatchDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("Cargando captura…")
                    .accessibilityIdentifier("detail.loading")
            case .loaded, .deletingConfirmation, .deleting, .deleteFailed:
                loadedContainer
            case .editing, .saving, .saveFailed:
                editingContent
            case .notFound:
                notFoundView
            case .loadFailed:
                loadFailedView
            case .removed:
                removedView
            }
        }
        .navigationTitle("Detalle de captura")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel.state == .loading else { return }
            await viewModel.load()
        }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .deletingConfirmation:
                deleteDecisionMade = false
                showingDeleteConfirmation = true
            case .loadFailed, .saveFailed, .deleteFailed:
                errorDecisionMade = false
                showingErrorAlert = true
            default:
                showingDeleteConfirmation = false
                showingErrorAlert = false
            }
        }
        .onChange(of: showingDeleteConfirmation) { _, presented in
            if !presented, !deleteDecisionMade, viewModel.state == .deletingConfirmation {
                viewModel.cancelDelete()
            }
        }
        .onChange(of: showingErrorAlert) { _, presented in
            if !presented, !errorDecisionMade,
               viewModel.state == .loadFailed || viewModel.state == .saveFailed || viewModel.state == .deleteFailed {
                viewModel.dismissError()
            }
        }
        .alert(
            "¿Eliminar esta captura?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Eliminar captura", role: .destructive) {
                deleteDecisionMade = true
                Task { await viewModel.confirmDelete() }
            }
            .accessibilityIdentifier("detail.confirmDelete")
            Button("Cancelar", role: .cancel) {
                deleteDecisionMade = true
                viewModel.cancelDelete()
            }
            .accessibilityIdentifier("detail.cancelDelete")
        } message: {
            Text("La captura se eliminará del historial. Esta acción no se puede deshacer.")
        }
        .alert(
            viewModel.errorMessage ?? "Error",
            isPresented: $showingErrorAlert
        ) {
            Button("Reintentar") {
                errorDecisionMade = true
                retryCurrentOperation()
            }
            .accessibilityIdentifier("detail.errorRetry")
            Button("Cerrar", role: .cancel) {
                errorDecisionMade = true
                viewModel.dismissError()
            }
            .accessibilityIdentifier("detail.errorDismiss")
        } message: {
            Text("La captura se conserva en tu registro. Inténtalo de nuevo.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.state == .loaded, viewModel.speciesCommonName != nil {
                    Button("Editar") {
                        seedLocationText()
                        viewModel.startEditing()
                    }
                    .accessibilityIdentifier("detail.editButton")
                }
            }
        }
    }

    // MARK: - Estado de detalle cargado

    @ViewBuilder
    private var loadedContainer: some View {
        if viewModel.speciesCommonName == nil {
            ContentUnavailableView {
                Label("Captura no disponible", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("No se pudo cargar el contenido de esta captura.")
            }
            .accessibilityIdentifier("detail.unavailable")
        } else {
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 4) {
                    Text(viewModel.speciesCommonName ?? "Especie no disponible")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("detail.speciesName")
                    if let scientific = viewModel.speciesScientificName {
                        Text(scientific)
                            .font(.subheadline.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("detail.speciesScientific")
                    }
                }

                if let data = viewModel.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("detail.photo")
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("detail.photo")
                }

                infoRow(icon: "calendar", title: "Fecha y hora", value: viewModel.formattedDate ?? "No disponible", id: "detail.date")
                infoRow(icon: "mappin.and.ellipse", title: "Ubicación", value: formattedLocation ?? "No disponible", id: "detail.location")

                VStack(alignment: .leading, spacing: 4) {
                    Label("Notas", systemImage: "text.alignleft")
                        .font(.headline)
                    Text(viewModel.notes ?? "Sin notas")
                        .font(.body)
                        .accessibilityIdentifier("detail.notes")
                }

                Button(role: .destructive) {
                    deleteDecisionMade = false
                    viewModel.beginDelete()
                } label: {
                    Label("Eliminar captura", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityIdentifier("detail.deleteButton")
            }
            .padding()
        }
        .overlay {
            if viewModel.state == .deleting {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }

    // MARK: - Modo edición

    private var editingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Especie", systemImage: "lock.fill")
                        .font(.headline)
                    Text(viewModel.speciesCommonName ?? "—")
                        .font(.body)
                    if let scientific = viewModel.speciesScientificName {
                        Text(scientific)
                            .font(.subheadline.italic())
                            .foregroundStyle(.secondary)
                    }
                }

                if let data = viewModel.thumbnailData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("detail.editPhoto")
                }

                DatePicker("Fecha y hora", selection: $viewModel.editDate)
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("detail.editDate")

                HStack(spacing: 12) {
                    TextField("Latitud", text: $latitudeText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("detail.latitudeField")
                    TextField("Longitud", text: $longitudeText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("detail.longitudeField")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notas")
                        .font(.headline)
                    TextEditor(text: $viewModel.editNotes)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("detail.editNotes")
                }
            }
            .padding()
        }
        .overlay {
            if viewModel.state == .saving {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") {
                    viewModel.cancel()
                }
                .accessibilityIdentifier("detail.cancelButton")
                .disabled(viewModel.state == .saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    updateEditLocation()
                    Task { await viewModel.save() }
                }
                .accessibilityIdentifier("detail.saveButton")
                .disabled(viewModel.state == .saving)
            }
        }
    }

    // MARK: - Estados vacíos y de error

    private var notFoundView: some View {
        ContentUnavailableView {
            Label("Captura no encontrada", systemImage: "questionmark.circle")
        } description: {
            Text("No se encuentra ninguna captura con este identificador.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.notFound")
    }

    private var loadFailedView: some View {
        ContentUnavailableView {
            Label(CatchDetailViewModel.loadFailedMessage, systemImage: "exclamationmark.triangle")
        } description: {
            Text("La captura se conserva en tu registro. Comprueba el almacenamiento e inténtalo de nuevo.")
        } actions: {
            Button("Reintentar") {
                Task { await viewModel.load() }
            }
            .accessibilityIdentifier("detail.errorRetry")
            Button("Cerrar") {
                viewModel.dismissError()
            }
            .accessibilityIdentifier("detail.errorDismiss")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.loadFailed")
    }

    private var removedView: some View {
        ContentUnavailableView {
            Label("Captura eliminada", systemImage: "trash")
        } description: {
            Text("La captura se ha eliminado de tu registro.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.removed")
    }

    // MARK: - Helpers

    private func infoRow(icon: String, title: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(value)
                .font(.body)
                .accessibilityIdentifier(id)
        }
    }

    private var formattedLocation: String? {
        guard let location = viewModel.location else { return nil }
        return String(format: "%.4f, %.4f", location.latitude, location.longitude)
    }

    private func retryCurrentOperation() {
        switch viewModel.state {
        case .loadFailed:
            Task { await viewModel.load() }
        case .saveFailed:
            Task { await viewModel.save() }
        case .deleteFailed:
            Task { await viewModel.confirmDelete() }
        default:
            break
        }
    }

    private func seedLocationText() {
        latitudeText = viewModel.location.map { String(format: "%.4f", $0.latitude) } ?? ""
        longitudeText = viewModel.location.map { String(format: "%.4f", $0.longitude) } ?? ""
        updateEditLocation()
    }

    private func updateEditLocation() {
        if let latitude = Double(latitudeText), let longitude = Double(longitudeText) {
            viewModel.editLocation = LocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else if latitudeText.isEmpty, longitudeText.isEmpty {
            viewModel.editLocation = nil
        }
    }
}