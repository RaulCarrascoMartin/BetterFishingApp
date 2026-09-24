import PhotosUI
import SwiftUI
import UIKit

@MainActor
struct ProfileEditView: View {
    @State private var viewModel: AccountViewModel
    @State private var displayNameDraft = ""
    @State private var didSeedDisplayName = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var isSavingName = false
    @State private var isPreparingAvatar = false

    init(viewModel: AccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 20) {
            avatarSection
            nameSection
            if let message = viewModel.errorMessage {
                errorNotice(message)
            }
        }
        .padding()
        .onAppear {
            seedDisplayNameIfNeeded()
        }
        .onChange(of: viewModel.profile) { _, _ in
            seedDisplayNameIfNeeded()
        }
        .task(id: selectedAvatarItem) {
            await handleAvatarSelection()
        }
    }

    private var avatarSection: some View {
        VStack(spacing: 12) {
            avatarView
                .frame(width: 120, height: 120)
            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Label(isPreparingAvatar ? "Subiendo avatar…" : "Cambiar avatar", systemImage: "photo.on.rectangle")
            }
            .disabled(isPreparingAvatar)
            .accessibilityIdentifier("account.avatarPicker")
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImage {
            avatarImage
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .accessibilityIdentifier("account.avatar")
        } else if let data = viewModel.avatarData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .accessibilityIdentifier("account.avatar")
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                Text(avatarInitial)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .accessibilityIdentifier("account.avatarPlaceholder")
        }
    }

    private var avatarInitial: String {
        let source = viewModel.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? viewModel.sessionUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = source?.first else { return "?" }
        return String(first).uppercased()
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nombre")
                .font(.headline)
            HStack {
                TextField("Nombre", text: $displayNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("account.displayName")
                Button("Guardar") {
                    Task { await saveName() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveName)
                .accessibilityIdentifier("account.saveName")
            }
        }
    }

    private var canSaveName: Bool {
        let trimmed = trimmedDisplayName
        return !trimmed.isEmpty
            && trimmed != (viewModel.profile?.displayName ?? "")
            && !isSavingName
            && !isPreparingAvatar
    }

    private var trimmedDisplayName: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func seedDisplayNameIfNeeded() {
        guard !didSeedDisplayName, viewModel.profile != nil else { return }
        displayNameDraft = viewModel.profile?.displayName ?? ""
        didSeedDisplayName = true
    }

    private func saveName() async {
        isSavingName = true
        defer { isSavingName = false }
        let previousError = viewModel.errorMessage
        await viewModel.saveDisplayName(trimmedDisplayName)
        if viewModel.errorMessage != previousError {
            displayNameDraft = viewModel.profile?.displayName ?? ""
        }
    }

    private func handleAvatarSelection() async {
        guard let item = selectedAvatarItem else { return }
        selectedAvatarItem = nil
        isPreparingAvatar = true
        defer { isPreparingAvatar = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data), let jpegData = image.jpegData(compressionQuality: 0.8) else { return }
        let previousError = viewModel.errorMessage
        avatarImage = Image(uiImage: image)
        await viewModel.uploadAvatar(data: jpegData, contentType: "image/jpeg")
        if viewModel.errorMessage != previousError {
            avatarImage = nil
        }
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("account.error")
    }
}