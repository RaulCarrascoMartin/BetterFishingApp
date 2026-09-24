import SwiftUI

@MainActor
struct SignInSignUpFormView: View {
    private enum AuthMode: String, CaseIterable {
        case signUp = "Crear cuenta"
        case signIn = "Iniciar sesión"
    }

    @State private var viewModel: AccountViewModel
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""

    init(viewModel: AccountViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Modo de acceso", selection: $mode) {
                ForEach(AuthMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account.authMode")

            Text(invitationText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account.email")

            SecureField("Contraseña", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("account.password")

            Button {
                submit()
            } label: {
                Group {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(submitTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .accessibilityIdentifier("account.submit")

            if let message = viewModel.errorMessage {
                errorNotice(message)
            }
        }
        .padding()
        .onChange(of: viewModel.sessionState) { _, newState in
            if case .signedIn = newState {
                email = ""
                password = ""
            }
        }
    }

    private var canSubmit: Bool {
        !viewModel.isSubmitting
            && !trimmedEmail.isEmpty
            && !trimmedPassword.isEmpty
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var submitTitle: String {
        mode == .signUp ? "Crear cuenta" : "Iniciar sesión"
    }

    private var invitationText: String {
        switch mode {
        case .signUp:
            "Crea tu cuenta para guardar tus favoritos y sincronizar tu registro entre dispositivos."
        case .signIn:
            "¿Ya tienes cuenta? Inicia sesión para acceder a tu perfil, favoritos y registro sincronizado."
        }
    }

    private func submit() {
        switch mode {
        case .signUp:
            Task { await viewModel.signUp(email: trimmedEmail, password: trimmedPassword) }
        case .signIn:
            Task { await viewModel.signIn(email: trimmedEmail, password: trimmedPassword) }
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