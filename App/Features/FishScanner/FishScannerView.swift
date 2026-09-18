import SwiftUI
import UIKit

@MainActor
struct FishScannerView: View {
    @State private var cameraManager: CameraManager
    @State private var isShowingCamera = false
    @State private var presentingCameraError = false
    @State private var showingSaveConfirmation = false
    @State private var showingSaveFailed = false
    @State private var showingSavedSuccess = false

    let viewModel: FishScannerViewModel
    private let gallerySelectionProvider: (@MainActor () -> Data?)?

    init(
        viewModel: FishScannerViewModel,
        cameraManager: CameraManager = CameraManager(),
        gallerySelectionProvider: (@MainActor () -> Data?)? = nil
    ) {
        self.viewModel = viewModel
        self.gallerySelectionProvider = gallerySelectionProvider
        _cameraManager = State(initialValue: cameraManager)
    }

    var body: some View {
        Group {
            switch viewModel.scanState {
            case .idle:
                sourceSelectionView
            case .imageReady, .identifying:
                identifyingView
            case .identified(let result):
                identifiedView(result)
            case .noMatch:
                noMatchView
            case .failed(let message):
                failedView(message)
            }
        }
        .navigationTitle("Identificar pez")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.saveState) { _, newState in
            showingSaveFailed = (newState == .saveFailed)
            showingSavedSuccess = (newState == .saved)
        }
        .alert("No se pudo guardar la captura", isPresented: $showingSaveFailed) {
            Button("Reintentar") {
                Task { await viewModel.saveCapturedCatch() }
            }
            .accessibilityIdentifier("scanner.saveRetry")
            Button("Cancelar", role: .cancel) {}
                .accessibilityIdentifier("scanner.saveCancel")
        } message: {
            Text("La especie identificada se mantiene en pantalla. Comprueba tu conexión e inténtalo de nuevo.")
                .accessibilityIdentifier("scanner.saveFailedMessage")
        }
        .alert("Captura guardada", isPresented: $showingSavedSuccess) {
            Button("Volver al inicio") {
                viewModel.retryWithAnotherPhoto()
            }
            .accessibilityIdentifier("scanner.saveSuccessContinue")
        } message: {
            Text("Tu captura se ha guardado con la especie identificada.")
                .accessibilityIdentifier("scanner.saveSuccessMessage")
        }
        .alert("No se pudo capturar la foto", isPresented: $presentingCameraError) {
            Button("Reintentar") {}
            Button("Cancelar", role: .cancel) { isShowingCamera = false }
        } message: {
            Text("Comprueba el acceso a la cámara e inténtalo de nuevo.")
        }
    }

    // MARK: - Selección de fuente

    @ViewBuilder
    private var sourceSelectionView: some View {
        if isShowingCamera {
            cameraCaptureView
        } else {
            idleSourceOptions
        }
    }

    private var idleSourceOptions: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "fish.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("¿Qué pez has capturado?")
                    .font(.title2.bold())
                Text("Fotografía el pez o elige una foto de tu galería para identificar la especie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Button {
                isShowingCamera = true
            } label: {
                Label("Usar cámara", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scanner.cameraSource")

            if let gallerySelectionProvider {
                Button {
                    if let data = gallerySelectionProvider() {
                        viewModel.setImage(data: data)
                    }
                } label: {
                    Label("Elegir de la galería", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("scanner.gallerySource")
            } else {
                PhotoPickerView { data in
                    viewModel.setImage(data: data)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("scanner.gallerySource")
            }

            Spacer()
        }
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.sourceSelector")
    }

    // MARK: - Captura con cámara

    private var cameraCaptureView: some View {
        Group {
            switch cameraManager.cameraAccessDenied {
            case .some(true):
                cameraDeniedView
            case .some(false):
                liveCameraView
            case .none:
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Preparando cámara…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: isShowingCamera) {
            guard isShowingCamera else { return }
            _ = await cameraManager.requestCameraAccessIfNeeded()
        }
    }

    private var liveCameraView: some View {
        ZStack {
            CameraView(cameraManager: cameraManager)
                .ignoresSafeArea()
                .accessibilityIdentifier("scanner.cameraPreview")
            VStack {
                HStack {
                    Button {
                        isShowingCamera = false
                    } label: {
                        Label("Cancelar", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityIdentifier("scanner.cameraCancel")
                    Spacer()
                }
                .padding()
                Spacer()
                Button {
                    Task { await capturePhoto() }
                } label: {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 72))
                }
                .accessibilityLabel("Capturar foto")
                .accessibilityIdentifier("scanner.cameraShutter")
                .padding(.bottom, 40)
            }
        }
        .background(.black)
    }

    private var cameraDeniedView: some View {
        ContentUnavailableView {
            Label("Sin acceso a la cámara", systemImage: "camera")
        } description: {
            Text("Habilita el acceso a la cámara en Ajustes para fotografiar el pez e identificar la especie.")
        } actions: {
            Button {
                openSettings()
            } label: {
                Label("Abrir Ajustes", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scanner.openSettings")

            Button("Volver") {
                isShowingCamera = false
            }
            .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.cameraDenied")
    }

    @MainActor
    private func capturePhoto() async {
        guard let data = await cameraManager.capturePhoto() else {
            presentingCameraError = true
            return
        }
        isShowingCamera = false
        viewModel.setImage(data: data)
    }

    @MainActor
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Procesamiento

    private var identifyingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Identificando la especie…")
                .font(.headline)
            Text("Esto suele tardar unos segundos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                viewModel.cancelCapture()
            } label: {
                Label("Cancelar", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("scanner.cancel")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.identifying")
    }

    // MARK: - Resultado

    @ViewBuilder
    private func identifiedView(_ result: IdentificationResult) -> some View {
        let speciesName = result.species.localizedName ?? result.species.commonName

        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(speciesName)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("scanner.speciesName")
                    Text(result.species.scientificName)
                        .font(.title3.italic())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                if result.confidence == .low {
                    Label {
                        Text("Confianza baja: este resultado puede no ser fiable. Intenta con otra foto.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("scanner.lowConfidenceWarning")
                }

                Group {
                    switch viewModel.saveState {
                    case .idle, .saveFailed:
                        Button {
                            showingSaveConfirmation = true
                        } label: {
                            Label("Guardar captura", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("scanner.saveCatch")
                    case .saving:
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Guardando captura…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("scanner.saving")
                    case .saved:
                        EmptyView()
                    }
                }

                Button {
                    viewModel.retryWithAnotherPhoto()
                } label: {
                    Label("Escanear otro pez", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("scanner.scanAnother")
                .padding(.horizontal)
            }
        }
        .alert("Guardar la captura", isPresented: $showingSaveConfirmation) {
            Button("Guardar") {
                Task { await viewModel.saveCapturedCatch() }
            }
            .accessibilityIdentifier("scanner.saveConfirm")
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se guardará la captura con la especie pre-rellena: \(speciesName) (\(result.species.scientificName)).")
                .accessibilityIdentifier("scanner.saveConfirmationSpecies")
        }
    }

    private var noMatchView: some View {
        ContentUnavailableView {
            Label("No se pudo identificar", systemImage: "questionmark.circle")
        } description: {
            Text("No se ha encontrado ninguna especie con suficiente confianza. Prueba con otra foto más clara y bien iluminada.")
        } actions: {
            Button {
                viewModel.retryWithAnotherPhoto()
            } label: {
                Label("Reintentar con otra foto", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scanner.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.noMatch")
    }

    private func failedView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("La identificación falló", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                viewModel.retryWithAnotherPhoto()
            } label: {
                Label("Reintentar con otra foto", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("scanner.retry")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.failure")
    }
}

#if DEBUG
#Preview("Idle") {
    NavigationStack {
        FishScannerView(viewModel: FishScannerPreviewSupport.makeViewModel(state: .idle))
    }
}

#Preview("Identificando") {
    NavigationStack {
        FishScannerView(viewModel: FishScannerPreviewSupport.makeViewModel(state: .identifying))
    }
}

#Preview("Identificada") {
    NavigationStack {
        FishScannerView(
            viewModel: FishScannerPreviewSupport.makeViewModel(
                state: .identified(FishScannerPreviewSupport.reliableBass)
            )
        )
    }
}

#Preview("Confianza baja") {
    NavigationStack {
        FishScannerView(
            viewModel: FishScannerPreviewSupport.makeViewModel(
                state: .identified(FishScannerPreviewSupport.lowConfidenceBluegill)
            )
        )
    }
}

#Preview("Sin coincidencia") {
    NavigationStack {
        FishScannerView(viewModel: FishScannerPreviewSupport.makeViewModel(state: .noMatch))
    }
}

#Preview("Error") {
    NavigationStack {
        FishScannerView(
            viewModel: FishScannerPreviewSupport.makeViewModel(
                state: .failed(message: "No se pudo completar la identificación")
            )
        )
    }
}

#Preview("Guardando captura") {
    SaveStatePreviewView(target: .saving)
}

#Preview("Guardado fallido") {
    SaveStatePreviewView(target: .saveFailed)
}

#Preview("Guardado con éxito") {
    SaveStatePreviewView(target: .saved)
}
#endif