import SwiftUI
import UIKit

@MainActor
struct FishScannerView: View {
    @State private var cameraManager: CameraManager
    @State private var isShowingCamera = false
    @State private var presentingCameraError = false

    let viewModel: FishScannerViewModel

    init(viewModel: FishScannerViewModel, cameraManager: CameraManager = CameraManager()) {
        self.viewModel = viewModel
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

            PhotoPickerView { data in
                viewModel.setImage(data: data)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("scanner.gallerySource")

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

    private func identifiedView(_ result: IdentificationResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text(result.species.localizedName ?? result.species.commonName)
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
#endif