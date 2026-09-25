import Foundation
import os

actor SupabaseProfileRepository: ProfileManaging {
    private static let logger = Logger(subsystem: "com.betterfishing.BetterFishing", category: "Account")

    private let auth: any SupabaseAuthProviding
    private let database: any SupabaseDatabaseAccess
    private let storage: any SupabaseStoring

    init(auth: any SupabaseAuthProviding, database: any SupabaseDatabaseAccess, storage: any SupabaseStoring) {
        self.auth = auth
        self.database = database
        self.storage = storage
    }

    private func currentUser() async throws -> SupabaseUser {
        guard let user = await auth.currentUser() else {
            throw AccountProfileError.notAuthenticated
        }
        return user
    }

    func profile() async throws -> AccountProfile {
        let user = try await currentUser()
        return try await profile(user: user)
    }

    private func profile(user: SupabaseUser) async throws -> AccountProfile {
        do {
            let rows: [AccountProfile] = try await database.select(
                columns: "user_id,display_name,avatar_path",
                from: "profiles",
                filters: [SupabaseFilter(column: "user_id", operator: .eq, value: user.id.uuidString)],
                limit: 1
            )
            return rows.first ?? AccountProfile(userID: user.id, displayName: nil, avatarPath: nil)
        } catch {
            throw AccountProfileError.loadFailed(Self.errorText(error))
        }
    }

    func updateDisplayName(_ name: String) async throws {
        let user = try await currentUser()
        let current = try await profile(user: user)
        try await persistProfile(userID: user.id, displayName: name, avatarPath: current.avatarPath)
        Self.logger.info("Nombre de perfil actualizado: \(user.id, privacy: .public)")
    }

    func updateAvatar(data: Data, contentType: String) async throws -> String {
        let user = try await currentUser()
        do {
            let avatarPath = "\(user.id.uuidString)/avatar.jpg"
            _ = try await storage.upload(
                bucket: "avatars",
                path: avatarPath,
                data: data,
                options: SupabaseUploadOptions(contentType: contentType, upsert: true)
            )
            let current = try await profile(user: user)
            try await persistProfile(userID: user.id, displayName: current.displayName, avatarPath: avatarPath)
            Self.logger.info("Avatar subido: \(user.id, privacy: .public)")
            return avatarPath
        } catch let error as AccountProfileError {
            throw error
        } catch {
            throw AccountProfileError.uploadAvatarFailed(Self.errorText(error))
        }
    }

    func avatarData(avatarPath: String) async throws -> Data? {
        do {
            return try await storage.download(bucket: "avatars", path: avatarPath)
        } catch {
            Self.logger.error("Fallo al descargar avatar: \(error.localizedDescription, privacy: .public)")
            throw AccountProfileError.loadFailed(Self.errorText(error))
        }
    }

    private func persistProfile(userID: UUID, displayName: String?, avatarPath: String?) async throws {
        let displayNameArgument: SupabaseJSONValue = displayName.map { .string($0) } ?? .null
        let avatarArgument: SupabaseJSONValue = avatarPath.map { .string($0) } ?? .null
        do {
            try await database.rpcVoid(
                "upsert_profile",
                arguments: SupabaseRPCArguments([
                    "p_user_id": .string(userID.uuidString),
                    "p_display_name": displayNameArgument,
                    "p_avatar_path": avatarArgument,
                ])
            )
        } catch {
            throw AccountProfileError.updateFailed(Self.errorText(error))
        }
    }

    private static func errorText(_ error: Error) -> String {
        error.localizedDescription
    }
}