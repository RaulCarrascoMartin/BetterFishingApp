import Foundation

enum SupabaseBaseError: Error, Sendable, LocalizedError {
    case configurationMissing
    case invalidProjectURL
    case signUpFailed
    case signInFailed
    case signOutFailed
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
        case .signUpFailed:
            return "No se pudo registrar el usuario."
        case .signInFailed:
            return "No se pudo iniciar sesión. Comprueba tus credenciales."
        case .signOutFailed:
            return "No se pudo cerrar la sesión."
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
}