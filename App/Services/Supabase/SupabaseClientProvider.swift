import Foundation
import Supabase

enum SupabaseBaseError: Error, Sendable, Equatable, LocalizedError {
    case configurationMissing
    case invalidProjectURL
    case signUpFailed(SupabaseAuthFailure)
    case signInFailed(SupabaseAuthFailure)
    case signOutFailed(SupabaseAuthFailure)
    case sessionUnavailable
    case uploadFailed
    case downloadFailed
    case queryFailed
    case rpcFailed

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Configuración de Supabase ausente: no se encontraron SUPABASE_PROJECT_URL y SUPABASE_ANON_KEY."
        case .invalidProjectURL:
            return "La URL del proyecto de Supabase no es válida."
        case .signUpFailed(let failure):
            return "No se pudo registrar el usuario: \(Self.reasonText(for: failure.reason))"
        case .signInFailed(let failure):
            return "No se pudo iniciar sesión: \(Self.reasonText(for: failure.reason))"
        case .signOutFailed(let failure):
            return "No se pudo cerrar la sesión: \(Self.reasonText(for: failure.reason))"
        case .sessionUnavailable:
            return "No hay una sesión de Supabase disponible."
        case .uploadFailed:
            return "No se pudo subir el objeto al almacenamiento de Supabase."
        case .downloadFailed:
            return "No se pudo descargar el objeto del almacenamiento de Supabase."
        case .queryFailed:
            return "Falló la consulta a la base de datos de Supabase."
        case .rpcFailed:
            return "Falló la llamada remota a la base de datos de Supabase."
        }
    }

    var reasonDescription: String? {
        switch self {
        case .signUpFailed(let failure), .signInFailed(let failure), .signOutFailed(let failure):
            return Self.reasonText(for: failure.reason)
        case .configurationMissing, .invalidProjectURL, .sessionUnavailable,
             .uploadFailed, .downloadFailed, .queryFailed, .rpcFailed:
            return nil
        }
    }

    private static func reasonText(for reason: SupabaseAuthFailureReason) -> String {
        switch reason {
        case .invalidCredentials:
            return "las credenciales no son válidas."
        case .network:
            return "no hay conexión con el servidor."
        case .configuration:
            return "la configuración de Supabase no es válida."
        case .server:
            return "el servicio de autenticación no está disponible."
        case .unknown:
            return "inténtalo de nuevo."
        }
    }
}

struct SupabaseStack: Sendable {
    let auth: any SupabaseAuthProviding
    let storage: any SupabaseStoring
    let database: any SupabaseDatabaseAccess
}

struct SupabaseClientProvider: Sendable {
    let configuration: SupabaseClientConfiguration

    func makeStack(options: SupabaseClientOptions? = nil) throws -> SupabaseStack {
        let client = try makeClient(options: options)
        return SupabaseStack(
            auth: SupabaseAuthService(client: client),
            storage: SupabaseStorageService(client: client),
            database: SupabaseDatabaseService(client: client)
        )
    }

    func makeClient(options: SupabaseClientOptions? = nil) throws -> SupabaseClient {
        let url = configuration.projectURL
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false),
              !host.isEmpty else {
            throw SupabaseBaseError.invalidProjectURL
        }
        return SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.anonKey,
            options: options ?? SupabaseClientOptions()
        )
    }
}