import Observation
import PhotosUI
import SwiftUI

protocol PhotoItemLoading: Sendable {
    func loadImageData() async -> Data?
}

extension PhotosPickerItem: PhotoItemLoading {
    func loadImageData() async -> Data? {
        try? await loadTransferable(type: Data.self)
    }
}

@MainActor
@Observable
final class PhotoSelectionPresenter {
    private(set) var isPreparing = false
    private let onImagePicked: @MainActor (Data) -> Void

    init(onImagePicked: @escaping @MainActor (Data) -> Void) {
        self.onImagePicked = onImagePicked
    }

    func handleSelection(_ item: (any PhotoItemLoading)?) async {
        guard let item else { return }
        isPreparing = true
        defer { isPreparing = false }
        guard let data = await item.loadImageData() else { return }
        onImagePicked(data)
    }
}

struct PhotoPickerView: View {
    private let presenter: PhotoSelectionPresenter
    @State private var selectedItem: PhotosPickerItem?

    @MainActor
    init(onImagePicked: @escaping @MainActor (Data) -> Void) {
        presenter = PhotoSelectionPresenter(onImagePicked: onImagePicked)
    }

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            Label("Elegir de la galería", systemImage: "photo.on.rectangle")
        }
        .task(id: selectedItem) {
            await presenter.handleSelection(selectedItem)
            selectedItem = nil
        }
        .disabled(presenter.isPreparing)
    }
}

#Preview {
    PhotoPickerView(onImagePicked: { _ in })
}