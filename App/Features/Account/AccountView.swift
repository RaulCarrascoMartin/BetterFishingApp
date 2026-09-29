import SwiftUI

@MainActor
struct AccountView: View {
    let viewModel: AccountViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(for: viewModel)
            } else {
                unavailableView
            }
        }
        .navigationTitle("Cuenta")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for viewModel: AccountViewModel) -> some View {
        switch viewModel.sessionState {
        case .signedOut:
            SignInSignUpFormView(viewModel: viewModel)
        case .signedIn:
            signedInContent(for: viewModel)
        }
    }

    private func signedInContent(for viewModel: AccountViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileEditView(viewModel: viewModel)

                FavoritesListView(viewModel: viewModel)

                syncSection(for: viewModel)

                signOutButton(for: viewModel)
            }
            .padding()
        }
        .task {
            await viewModel.refreshFavorites()
        }
    }

    private func syncSection(for viewModel: AccountViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sincronización", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Button {
                Task { await viewModel.sync() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSyncing {
                        ProgressView()
                    }
                    Text("Sincronizar")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSyncing)
            .accessibilityIdentifier("account.syncButton")

            if let result = viewModel.lastSyncResult {
                syncResultRow(for: result)
            } else if let message = viewModel.errorMessage {
                syncErrorNotice(message)
            }
        }
    }

    private func syncResultRow(for result: CatchSyncResult) -> some View {
        HStack(spacing: 6) {
            Text("Subidos \(result.pushed)")
            Text("•")
            Text("Descargados \(result.pulled)")
            Text("•")
            Text("Omitidos \(result.skipped)")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account.syncResult")
    }

    private func signOutButton(for viewModel: AccountViewModel) -> some View {
        Button(role: .destructive) {
            Task { await viewModel.signOut() }
        } label: {
            Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .disabled(viewModel.isSubmitting)
        .accessibilityIdentifier("account.signOut")
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Cuenta no disponible", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("La capa de cuenta no está configurada en este momento. Vuelve a intentarlo más tarde.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account.unavailable")
    }

    private func syncErrorNotice(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("account.syncError")
    }
}