import Foundation
import os
import Supabase

/// Almacenamiento de sesión de Auth: usa Keychain y, si no está disponible
/// (p. ej. builds sin firma y sin entitlements), cae a un archivo protegido
/// en Application Support para que la sesión no se pierda en silencio.
struct FallbackAuthLocalStorage: AuthLocalStorage {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "AuthStorage")

    private let primary: any AuthLocalStorage
    private let directory: URL

    init(
        primary: any AuthLocalStorage = KeychainLocalStorage(),
        directory: URL = FallbackAuthLocalStorage.defaultDirectory
    ) {
        self.primary = primary
        self.directory = directory
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "AuthSession", directoryHint: .isDirectory)
    }

    func store(key: String, value: Data) throws {
        do {
            try primary.store(key: key, value: value)
            if try primary.retrieve(key: key) == value {
                try? removeFile(key: key)
                return
            }
            Self.logger.error("Keychain no devolvió la sesión guardada; usando almacenamiento de respaldo")
        } catch {
            Self.logger.error("Keychain falló al guardar la sesión: \(error.localizedDescription, privacy: .public)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try value.write(to: fileURL(for: key), options: [.atomic, .completeFileProtection])
    }

    func retrieve(key: String) throws -> Data? {
        if let data = try? primary.retrieve(key: key) {
            return data
        }
        return try? Data(contentsOf: fileURL(for: key))
    }

    func remove(key: String) throws {
        try? primary.remove(key: key)
        try? removeFile(key: key)
    }

    private func removeFile(key: String) throws {
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? String($0) : "_" }.joined()
        return directory.appending(path: safe, directoryHint: .notDirectory)
    }
}
