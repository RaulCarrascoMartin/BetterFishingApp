import AVFoundation
import SwiftUI
import UIKit

struct CameraView: View {
    let cameraManager: CameraManager

    var body: some View {
        CameraPreview(cameraManager: cameraManager)
            .onDisappear {
                Task { await cameraManager.stopRunning() }
            }
    }
}

struct CameraPreview: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> CameraPreviewView {
        let preview = CameraPreviewView()
        bind(preview)
        return preview
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        bind(uiView)
    }

    private func bind(_ view: CameraPreviewView) {
        view.previewLayer.session = cameraManager.previewSession
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

#Preview {
    CameraView(cameraManager: CameraManager())
}