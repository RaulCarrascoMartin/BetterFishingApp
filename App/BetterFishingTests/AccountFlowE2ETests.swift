import Foundation
import Supabase
import XCTest

@testable import BetterFishing

/// Base de datos falsa con guion de filas: devuelve por turnos cada lote de `rowsScript`
/// (repitiendo el último al agotarse) e inyecta fallos de red bajo demanda.
/// `SupabaseBaseFake.cannedRows` es estado de instancia no-avanzante (un único lote para
/// cualquier tabla), por eso la sync usa esta doble que puede devolver el lote autoritativo
/// tras el push (idempotencia) y fallar después.
actor RecordingCatchDB: SupabaseDatabaseAccess {
    private var rowsScript: [[String]]
    private var lastBatch: [String] = []
    private var databaseError: SupabaseBaseError?
    private var recordedSelectValues: [BaseFakeRecordedSelect] = []
    private var recordedRPCValues: [BaseFakeRecordedRPC] = []

    init(rowsScript: [[String]]) {
        self.rowsScript = rowsScript
    }

    var recordedSelects: [BaseFakeRecordedSelect] { recordedSelectValues }
    var recordedRPCs: [BaseFakeRecordedRPC] { recordedRPCValues }

    func setDatabaseError(_ error: SupabaseBaseError?) {
        databaseError = error
    }

    func select<T: Decodable & Sendable>(
        columns: String,
        from table: String,
        filters: [SupabaseFilter],
        limit: Int?
    ) async throws -> [T] {
        recordedSelectValues.append(
            BaseFakeRecordedSelect(columns: columns, table: table, filters: filters, limit: limit)
        )
        if let databaseError {
            throw databaseError
        }
        let batch: [String]
        if rowsScript.isEmpty {
            batch = lastBatch
        } else {
            lastBatch = rowsScript.removeFirst()
            batch = lastBatch
        }
        return try batch.compactMap { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }

    func rpc<T: Decodable & Sendable>(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws -> T {
        recordedRPCValues.append(BaseFakeRecordedRPC(function: function, arguments: arguments))
        if let databaseError {
            throw databaseError
        }
        throw SupabaseBaseFakeError(reason: "JSON RPC is not configured")
    }

    func rpcVoid(
        _ function: String,
        arguments: SupabaseRPCArguments?
    ) async throws {
        recordedRPCValues.append(BaseFakeRecordedRPC(function: function, arguments: arguments))
        if let databaseError {
            throw databaseError
        }
    }
}

/// Espejo del perfil remoto: delega las mutaciones en `SupabaseProfileRepository` real
/// (registra RPC/upload/download en el fake) y conserva el estado posterior a cada
/// mutación, que el fake de base no refleja (sus filas canónicas son estáticas).
actor ProfileStateStore: ProfileManaging {
    private let real: SupabaseProfileRepository
    private var current: AccountProfile

    init(real: SupabaseProfileRepository, initial: AccountProfile) {
        self.real = real
        self.current = initial
    }

    func profile() async throws -> AccountProfile {
        current
    }

    func updateDisplayName(_ name: String) async throws {
        try await real.updateDisplayName(name)
        current = AccountProfile(userID: current.userID, displayName: name, avatarPath: current.avatarPath)
    }

    func updateAvatar(data: Data, contentType: String) async throws -> String {
        let path = try await real.updateAvatar(data: data, contentType: contentType)
        current = AccountProfile(userID: current.userID, displayName: current.displayName, avatarPath: path)
        return path
    }

    func avatarData(avatarPath: String) async throws -> Data? {
        try await real.avatarData(avatarPath: avatarPath)
    }
}

@MainActor
final class AccountFlowE2ETests: XCTestCase {

    private static let referenceTime: TimeInterval = 800_000_000

    private struct FlowHarness {
        let directory: TemporaryTestDirectory
        let repository: LocalFileCatchRepository
        let store: FileSyncCatchStore
        let ledger: CatchSyncLedger
        let viewModel: AccountViewModel
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Condición no alcanzada antes del timeout")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func makeSpecies() -> Species {
        Species(
            id: "species-largemouth",
            commonName: "Largemouth Bass",
            scientificName: "Micropterus salmoides"
        )
    }

    private static func makeLocation() -> LocationCoordinate2D {
        LocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)
    }

    private static func makeRegion() -> SpotRegion {
        SpotRegion(
            center: LocationCoordinate2D(latitude: 41.0, longitude: 2.0),
            latitudinalMeters: 111_320.0,
            longitudinalMeters: 111_320.0
        )
    }

    private static func makeRemoteCatch(
        id: UUID,
        userID: UUID,
        updatedAt: TimeInterval,
        notes: String = "Sincronizada desde la cuenta"
    ) -> RemoteCatch {
        RemoteCatch(
            id: id,
            userID: userID,
            species: makeSpecies(),
            date: Date(timeIntervalSinceReferenceDate: referenceTime),
            location: makeLocation(),
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: referenceTime + 1),
            updatedAt: Date(timeIntervalSinceReferenceDate: updatedAt),
            photoPath: "\(userID.uuidString)/\(id.uuidString).jpg"
        )
    }

    /// Serializa la captura remota con el codificador por defecto (fechas numéricas en
    /// segundos de referencia y claves anidadas de species/location) para que la
    /// `RecordingCatchDB` la decodifique con su `JSONDecoder` por defecto.
    private static func remoteRowJSON(_ remote: RemoteCatch) throws -> String {
        String(decoding: try JSONEncoder().encode(remote), as: UTF8.self)
    }

    /// Fila canónica de `profiles` en snake_case: el fake la decodifica como `AccountProfile`
    /// (CodingKeys user_id/display_name/avatar_path) descartando campos sobrantes.
    private static func profileRowJSON(
        userID: UUID = SupabaseBaseFake.defaultUser.id,
        displayName: String? = "Ana",
        avatarPath: String? = nil
    ) -> String {
        let nameValue = displayName.map { "\"\($0)\"" } ?? "null"
        let avatarValue = avatarPath.map { "\"\($0)\"" } ?? "null"
        return "{\"user_id\":\"\(userID.uuidString)\",\"display_name\":\(nameValue),\"avatar_path\":\(avatarValue)}"
    }

    private func makeHarnessParts() throws -> (
        directory: TemporaryTestDirectory,
        repository: LocalFileCatchRepository,
        store: FileSyncCatchStore,
        ledger: CatchSyncLedger
    ) {
        let directory = try makeTemporaryDirectory()
        let repository = LocalFileCatchRepository(directoryURL: directory.url)
        let store = FileSyncCatchStore(directoryURL: directory.url)
        let ledger = CatchSyncLedger(directoryURL: directory.url)
        return (directory, repository, store, ledger)
    }

    /// Planta una captura local escribiendo los ficheros `<id>.json` y `<id>.jpg` en el
    /// directorio compartido, respetando el layout de `LocalFileCatchRepository`.
    private func seedLocalCatch(
        id: UUID,
        notes: String,
        photoData: Data,
        in directory: TemporaryTestDirectory
    ) throws {
        let entry = Catch(
            id: id,
            species: Self.makeSpecies(),
            photoPath: "\(id.uuidString).jpg",
            date: Date(timeIntervalSinceReferenceDate: Self.referenceTime - 100),
            location: Self.makeLocation(),
            notes: notes,
            createdAt: Date(timeIntervalSinceReferenceDate: Self.referenceTime - 90)
        )
        try JSONEncoder().encode(entry).write(
            to: directory.url.appendingPathComponent("\(id.uuidString).json"),
            options: .atomic
        )
        try photoData.write(
            to: directory.url.appendingPathComponent("\(id.uuidString).jpg"),
            options: .atomic
        )
    }

    @MainActor
    private func makeFlowHarness(
        directory: TemporaryTestDirectory,
        repository: LocalFileCatchRepository,
        store: FileSyncCatchStore,
        ledger: CatchSyncLedger,
        fake: SupabaseBaseFake,
        database: any SupabaseDatabaseAccess,
        favorites: any SpotRepository,
        seededProfile: AccountProfile
    ) -> FlowHarness {
        let auth = AccountSessionManager(auth: fake)
        let profileRepository = SupabaseProfileRepository(auth: fake, database: fake, storage: fake)
        let profileStore = ProfileStateStore(real: profileRepository, initial: seededProfile)
        let presenting = SpotRepositorySpotPresenting(repository: favorites)
        let syncService = CatchSyncService(
            repository: repository,
            photoDataProvider: { repository.photoData(for: $0) },
            localStore: store,
            ledger: ledger,
            database: database,
            storage: fake
        )
        let viewModel = AccountViewModel(auth: auth, profile: profileStore, favorites: presenting, sync: syncService)
        return FlowHarness(
            directory: directory,
            repository: repository,
            store: store,
            ledger: ledger,
            viewModel: viewModel
        )
    }

    // MARK: - 6.1 Sesión

    func testSessionFlowE2E() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.cannedRows = [Self.profileRowJSON(displayName: "Ana", avatarPath: "legacy/avatar.jpg")]
        let sau = Spot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Embalse de Sau",
            category: .lake,
            summary: "Amplia lámina de agua.",
            longitude: 2.2486,
            latitude: 42.0037,
            distanceMeters: nil
        )
        let favorites = SpotRepositoryFake()
        favorites.seed([sau], for: Self.makeRegion())
        favorites.favoriteIDs = [sau.id]
        let db = RecordingCatchDB(rowsScript: [[], []])
        let seededProfile = AccountProfile(
            userID: SupabaseBaseFake.defaultUser.id,
            displayName: "Ana",
            avatarPath: "legacy/avatar.jpg"
        )

        let parts = try makeHarnessParts()
        let harness = makeFlowHarness(
            directory: parts.directory,
            repository: parts.repository,
            store: parts.store,
            ledger: parts.ledger,
            fake: fake,
            database: db,
            favorites: favorites,
            seededProfile: seededProfile
        )
        let viewModel = harness.viewModel

        XCTAssertEqual(
            viewModel.sessionState,
            .signedOut,
            "Sin sesión activa el VM arranca en signedOut y la vista muestra el formulario (Req 6.2)"
        )

        fake.isSessionActive = true
        await viewModel.signIn(email: "angler@example.com", password: "correct-horse")

        await waitUntil { viewModel.profile != nil && !viewModel.favorites.isEmpty }
        XCTAssertEqual(
            viewModel.sessionState,
            .signedIn(SupabaseBaseFake.defaultUser),
            "El login con éxito refleja la sesión activa (Req 1.6)"
        )
        XCTAssertEqual(viewModel.profile?.displayName, "Ana", "La sesión activa expone el perfil (Req 6.3)")
        XCTAssertEqual(
            viewModel.favorites,
            [FavoriteSpot(spotID: sau.id, name: sau.name, category: sau.category.rawValue)],
            "El login carga los favoritos de la cuenta (Req 4.5)"
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            fake.recordedSignIns.last,
            BaseFakeRecordedCredentials(email: "angler@example.com", password: "correct-horse")
        )

        let saved = try await harness.repository.saveCatch(
            species: Self.makeSpecies(),
            photoData: Data([0xAA]),
            date: Date(timeIntervalSinceReferenceDate: Self.referenceTime),
            location: Self.makeLocation(),
            notes: "Captura local pendiente de sincronizar"
        )
        await viewModel.sync()
        XCTAssertEqual(
            viewModel.lastSyncResult,
            CatchSyncResult(pushed: 1, pulled: 0, skipped: 0),
            "Sincronizar desde la cuenta sube la captura local (Req 6.4)"
        )
        XCTAssertTrue(
            fake.recordedUploads.contains {
                $0.bucket == "catches"
                    && $0.path == "\(SupabaseBaseFake.defaultUser.id.uuidString)/\(saved.id.uuidString).jpg"
                    && $0.data == Data([0xAA])
            },
            "La foto se sube a catches/{user}/{id}.jpg"
        )

        await viewModel.signOut()
        await waitUntil { viewModel.sessionState == .signedOut }
        XCTAssertNil(viewModel.profile, "El cierre de sesión deja de exponer el perfil (Req 6.5)")
        XCTAssertTrue(viewModel.favorites.isEmpty, "El cierre de sesión deja de exponer los favoritos (Req 6.5)")
        XCTAssertNil(viewModel.lastSyncResult, "El cierre de sesión limpia el resultado de sync (Req 2.4)")
        XCTAssertNil(viewModel.sessionUser)
    }

    // MARK: - 6.2 Perfil

    func testProfileEditE2E() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.cannedRows = [Self.profileRowJSON(displayName: "Ana", avatarPath: "legacy/avatar.jpg")]
        fake.downloadResultData = Data([0x10, 0x20, 0x30])
        let userID = SupabaseBaseFake.defaultUser.id
        let seededProfile = AccountProfile(userID: userID, displayName: "Ana", avatarPath: "legacy/avatar.jpg")

        let parts = try makeHarnessParts()
        let harness = makeFlowHarness(
            directory: parts.directory,
            repository: parts.repository,
            store: parts.store,
            ledger: parts.ledger,
            fake: fake,
            database: RecordingCatchDB(rowsScript: [[], []]),
            favorites: SpotRepositoryFake(),
            seededProfile: seededProfile
        )
        let viewModel = harness.viewModel

        fake.isSessionActive = true
        await viewModel.signIn(email: "angler@example.com", password: "correct-horse")
        await waitUntil { viewModel.profile != nil }
        XCTAssertEqual(viewModel.profile, seededProfile, "El perfil de la cuenta se expone al autenticarse (Req 3.1)")
        XCTAssertEqual(
            viewModel.avatarData,
            Data([0x10, 0x20, 0x30]),
            "El avatar se recupera desde el storage de la cuenta (Req 3.4)"
        )

        await viewModel.saveDisplayName("Marina")
        XCTAssertEqual(viewModel.profile?.displayName, "Marina", "Editar el nombre lo expone actualizado (Req 3.2)")
        XCTAssertEqual(
            viewModel.profile?.avatarPath,
            "legacy/avatar.jpg",
            "Editar el nombre conserva el avatar previo (read-modify-write)"
        )
        let nameRPC = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(nameRPC.function, "upsert_profile")
        XCTAssertEqual(nameRPC.arguments?.values["p_user_id"], .string(userID.uuidString))
        XCTAssertEqual(nameRPC.arguments?.values["p_display_name"], .string("Marina"))
        XCTAssertEqual(nameRPC.arguments?.values["p_avatar_path"], .string("legacy/avatar.jpg"))

        fake.databaseError = SupabaseBaseError.queryFailed
        await viewModel.saveDisplayName("Roto")
        XCTAssertEqual(
            viewModel.profile?.displayName,
            "Marina",
            "Un fallo de guardado conserva el valor anterior visible (Req 3.6)"
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            AccountProfileError.loadFailed("Falló la consulta a la base de datos de Supabase.").localizedDescription
        )
        fake.databaseError = nil

        let avatarBytes = Data([0x01, 0x02, 0x03, 0x04])
        await viewModel.uploadAvatar(data: avatarBytes, contentType: "image/jpeg")
        XCTAssertEqual(
            viewModel.profile?.avatarPath,
            "\(userID.uuidString)/avatar.jpg",
            "Aportar un avatar lo expone actualizado (Req 3.3)"
        )
        XCTAssertEqual(viewModel.avatarData, avatarBytes, "El VM expone los bytes del avatar aceptado")
        let upload = try XCTUnwrap(fake.recordedUploads.last)
        XCTAssertEqual(upload.bucket, "avatars")
        XCTAssertEqual(upload.path, "\(userID.uuidString)/avatar.jpg")
        XCTAssertEqual(upload.options?.contentType, "image/jpeg")
        XCTAssertEqual(upload.options?.upsert, true)
        let avatarRPC = try XCTUnwrap(fake.recordedRPCs.last)
        XCTAssertEqual(avatarRPC.function, "upsert_profile")
        XCTAssertEqual(avatarRPC.arguments?.values["p_avatar_path"], .string("\(userID.uuidString)/avatar.jpg"))

        fake.downloadError = SupabaseBaseError.downloadFailed
        await viewModel.signOut()
        fake.isSessionActive = true
        await viewModel.signIn(email: "angler@example.com", password: "correct-horse")
        await waitUntil {
            viewModel.profile != nil && viewModel.avatarData == nil && viewModel.errorMessage != nil
        }
        XCTAssertEqual(
            viewModel.profile?.avatarPath,
            "\(userID.uuidString)/avatar.jpg",
            "El perfil se mantiene y el fallo de descarga solo afecta al avatar (Req 3.4)"
        )
        XCTAssertNil(viewModel.avatarData)
        XCTAssertEqual(
            viewModel.errorMessage,
            AccountProfileError.loadFailed("No se pudo descargar el objeto del almacenamiento de Supabase.").localizedDescription
        )
    }

    // MARK: - 6.3 Favoritos

    func testFavoritesE2E() async throws {
        let fake = SupabaseBaseFake()
        fake.isSessionActive = false
        fake.cannedRows = [Self.profileRowJSON(displayName: "Ana", avatarPath: nil)]
        let sau = Spot(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Embalse de Sau",
            category: .lake,
            summary: "Amplia lámina de agua.",
            longitude: 2.2486,
            latitude: 42.0037,
            distanceMeters: nil
        )
        let barc = Spot(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Barceloneta",
            category: .shore,
            summary: "Playa urbana junto al puerto.",
            longitude: 2.1891,
            latitude: 41.3754,
            distanceMeters: nil
        )
        let ebro = Spot(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Delta del Ebro",
            category: .river,
            summary: "Gran delta fluvial.",
            longitude: 0.734,
            latitude: 40.701,
            distanceMeters: nil
        )
        let favorites = SpotRepositoryFake()
        favorites.seed([sau, barc, ebro], for: Self.makeRegion())
        favorites.favoriteIDs = [sau.id]
        let seededProfile = AccountProfile(userID: SupabaseBaseFake.defaultUser.id, displayName: "Ana", avatarPath: nil)

        let parts = try makeHarnessParts()
        let harness = makeFlowHarness(
            directory: parts.directory,
            repository: parts.repository,
            store: parts.store,
            ledger: parts.ledger,
            fake: fake,
            database: RecordingCatchDB(rowsScript: [[], []]),
            favorites: favorites,
            seededProfile: seededProfile
        )
        let viewModel = harness.viewModel

        fake.isSessionActive = true
        await viewModel.signIn(email: "angler@example.com", password: "correct-horse")
        await waitUntil { !viewModel.favorites.isEmpty }
        XCTAssertEqual(
            viewModel.favorites,
            [FavoriteSpot(spotID: sau.id, name: sau.name, category: sau.category.rawValue)],
            "Al autenticarse se exponen los favoritos de la cuenta (Req 4.4)"
        )

        await viewModel.toggleFavorite(barc.id)
        XCTAssertTrue(
            viewModel.favorites.contains { $0.spotID == barc.id },
            "Marcar favorito lo refleja en la lista (Req 4.2)"
        )
        XCTAssertTrue(favorites.favoriteIDs.contains(barc.id), "El seam SpotRepository queda actualizado al marcar (Req 4.2)")
        XCTAssertEqual(
            favorites.recordedFavoriteToggles.last,
            SpotRepositoryFake.RecordedFavoriteToggle(spotID: barc.id, isFavorite: true)
        )

        await viewModel.toggleFavorite(sau.id)
        XCTAssertFalse(
            viewModel.favorites.contains { $0.spotID == sau.id },
            "Desmarcar favorito lo retira de la lista (Req 4.3)"
        )
        XCTAssertEqual(favorites.favoriteIDs, [barc.id], "El seam SpotRepository queda actualizado al desmarcar (Req 4.3)")
        XCTAssertEqual(
            favorites.recordedFavoriteToggles.last,
            SpotRepositoryFake.RecordedFavoriteToggle(spotID: sau.id, isFavorite: false)
        )

        favorites.setFavoriteError = .queryFailed("red caída")
        await viewModel.toggleFavorite(ebro.id)
        XCTAssertEqual(
            viewModel.favorites,
            [FavoriteSpot(spotID: barc.id, name: barc.name, category: barc.category.rawValue)],
            "Un fallo de marcado conserva el estado previo re-consultado (Req 4.7)"
        )
        XCTAssertEqual(favorites.favoriteIDs, [barc.id])
        XCTAssertEqual(viewModel.errorMessage, FavoritesError.saveFailed("red caída").localizedDescription)
    }

    // MARK: - 6.4 Sincronización

    func testSyncE2E() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = []
        fake.downloadResultData = Data([0x0B, 0x0C])
        let userID = SupabaseBaseFake.defaultUser.id
        let localL = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let remoteR = Self.makeRemoteCatch(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            userID: userID,
            updatedAt: Self.referenceTime + 1000,
            notes: "Capturada en otro dispositivo"
        )

        let parts = try makeHarnessParts()
        try seedLocalCatch(
            id: localL,
            notes: "Captura local pendiente de sincronizar",
            photoData: Data([0xAA]),
            in: parts.directory
        )
        let remoteL = Self.makeRemoteCatch(
            id: localL,
            userID: userID,
            updatedAt: Self.referenceTime + 2000,
            notes: "Captura local pendiente de sincronizar"
        )
        let db = RecordingCatchDB(rowsScript: [
            [try Self.remoteRowJSON(remoteR)],
            [try Self.remoteRowJSON(remoteR), try Self.remoteRowJSON(remoteL)],
            [try Self.remoteRowJSON(remoteR), try Self.remoteRowJSON(remoteL)]
        ])
        let seededProfile = AccountProfile(userID: userID, displayName: nil, avatarPath: nil)

        let harness = makeFlowHarness(
            directory: parts.directory,
            repository: parts.repository,
            store: parts.store,
            ledger: parts.ledger,
            fake: fake,
            database: db,
            favorites: SpotRepositoryFake(),
            seededProfile: seededProfile
        )
        let viewModel = harness.viewModel

        await waitUntil { viewModel.sessionUser != nil }

        await viewModel.sync()
        XCTAssertEqual(
            viewModel.lastSyncResult,
            CatchSyncResult(pushed: 1, pulled: 1, skipped: 0),
            "Sync sube la captura local y descarga la remota (Req 5.1, 5.2)"
        )

        let recordedRPCs = await db.recordedRPCs
        let rpc = try XCTUnwrap(recordedRPCs.first)
        XCTAssertEqual(rpc.function, "upsert_catch")
        XCTAssertEqual(rpc.arguments?.values["p_user_id"], .string(userID.uuidString))
        guard case .string(let payload)? = rpc.arguments?.values["p_catch"] else {
            XCTFail("p_catch debe ser el catch serializado como JSON string")
            return
        }
        XCTAssertTrue(payload.contains(localL.uuidString), "El payload del push identifica la captura local")
        XCTAssertTrue(payload.contains("T"), "La fecha del payload se serializa en ISO8601 (contrato upsert_catch)")

        XCTAssertTrue(
            fake.recordedUploads.contains {
                $0.bucket == "catches"
                    && $0.path == "\(userID.uuidString)/\(localL.uuidString).jpg"
                    && $0.data == Data([0xAA])
            },
            "El push sube la foto a catches/{user}/{id}.jpg"
        )
        XCTAssertTrue(
            fake.recordedDownloads.contains {
                $0.bucket == "catches" && $0.path == "\(userID.uuidString)/\(remoteR.id.uuidString).jpg"
            },
            "El pull descarga la foto remota del bucket catches"
        )

        let listed = try await harness.repository.listCatches()
        XCTAssertEqual(
            listed.map(\.id).sorted { $0.uuidString < $1.uuidString },
            [localL, remoteR.id].sorted { $0.uuidString < $1.uuidString },
            "La captura remota se importa al registro local preservando el id (Req 5.2)"
        )
        let pulled = try XCTUnwrap(listed.first { $0.id == remoteR.id })
        XCTAssertEqual(pulled.photoPath, "\(remoteR.id.uuidString).jpg", "La captura importada usa el layout local de fotos")
        XCTAssertEqual(
            harness.repository.photoData(for: pulled),
            Data([0x0B, 0x0C]),
            "La foto descargada queda disponible en el registro local"
        )
        var snapshot = try await harness.ledger.snapshot()
        XCTAssertEqual(snapshot.entries.count, 2, "El ledger refleja ambas capturas tras el primer sync")
        XCTAssertTrue(snapshot.tombstonedIDs.isEmpty)

        await viewModel.sync()
        XCTAssertEqual(
            viewModel.lastSyncResult,
            CatchSyncResult(pushed: 0, pulled: 0, skipped: 2),
            "Un segundo sync no duplica capturas (idempotencia, Req 5.3)"
        )
        XCTAssertEqual(recordedRPCs.count, 1, "No se re-ejecuta el upsert tras la re-lectura autoritativa")

        await db.setDatabaseError(SupabaseBaseError.queryFailed)
        await viewModel.sync()
        XCTAssertEqual(
            viewModel.lastSyncResult,
            CatchSyncResult(pushed: 0, pulled: 0, skipped: 2),
            "Un fallo de red no descarta el último resultado conocido"
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            CatchSyncError.remoteLoadFailed("Falló la consulta a la base de datos de Supabase.").localizedDescription,
            "El fallo de red se expone al usuario (Req 5.5)"
        )
        let listedAfterFailure = try await harness.repository.listCatches()
        XCTAssertEqual(listedAfterFailure.count, 2, "El registro local queda intacto ante el fallo (Req 5.5)")
        snapshot = try await harness.ledger.snapshot()
        XCTAssertEqual(snapshot.entries.count, 2, "El ledger no se altera cuando el sync falla (Req 5.5)")
        XCTAssertTrue(snapshot.tombstonedIDs.isEmpty)

        await db.setDatabaseError(nil)
        await viewModel.sync()
        XCTAssertEqual(
            viewModel.lastSyncResult,
            CatchSyncResult(pushed: 0, pulled: 0, skipped: 2),
            "Reintentar tras el fallo sincroniza de nuevo con éxito (Req 5.5)"
        )
        XCTAssertFalse(viewModel.isSyncing)
    }

    func testRPCVoidWithNoContentBodyCompletes() async throws {
        HTTPStubRegistry.shared.reset()
        let rpcURL = "https://project-ref.supabase.co/rest/v1/rpc/upsert_profile"
        HTTPStubRegistry.shared.register(
            HTTPStub(statusCode: 204, data: Data(), headers: [:]),
            for: rpcURL
        )

        let userID = UUID()
        let arguments = SupabaseRPCArguments([
            "p_user_id": .string(userID.uuidString),
            "p_display_name": .string("Ana"),
            "p_avatar_path": .null,
        ])
        let database = try Self.makeDatabaseService()

        try await database.rpcVoid("upsert_profile", arguments: arguments)

        XCTAssertEqual(HTTPStubRegistry.shared.requestCount(for: rpcURL), 1)
        let body = try XCTUnwrap(HTTPStubRegistry.shared.requestBodies(for: rpcURL).first)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["p_user_id"] as? String, userID.uuidString)
        XCTAssertEqual(json["p_display_name"] as? String, "Ana")
        XCTAssertTrue(json["p_avatar_path"] is NSNull)
    }

    private static func makeDatabaseService() throws -> SupabaseDatabaseService {
        let supabaseURL = try XCTUnwrap(URL(string: "https://project-ref.supabase.co"))
        let options = SupabaseClientOptions(
            auth: .init(storage: InMemoryAuthLocalStorage(), autoRefreshToken: false),
            global: .init(session: .mockSession())
        )
        let client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: "test-anon-key",
            options: options
        )
        return SupabaseDatabaseService(client: client)
    }

    // MARK: - 6.1 Composition root

    func testCompositionWiresAccountViewModelOverStack() async throws {
        let fake = SupabaseBaseFake()
        fake.cannedRows = [Self.profileRowJSON(displayName: "Ana", avatarPath: nil)]
        let stack = SupabaseStack(auth: fake, storage: fake, database: fake)

        let services = AppComposition.makeRootServices(arguments: [], supabaseStack: stack)

        let viewModel = try XCTUnwrap(services.accountViewModel, "Con stack la cuenta debe componerse (Req 6.1)")
        await waitUntil { viewModel.profile != nil }
        XCTAssertEqual(viewModel.profile?.displayName, "Ana", "La composición expone el perfil cargado del stack (Req 6.1)")
        XCTAssertEqual(viewModel.profile?.userID, SupabaseBaseFake.defaultUser.id)
        XCTAssertTrue(viewModel.favorites.isEmpty)
        XCTAssertNil(viewModel.avatarData)

        await viewModel.signOut()
        await waitUntil { viewModel.sessionState == .signedOut }
        XCTAssertNil(viewModel.profile, "Cerrar sesión limpia el perfil expuesto por la composición (Req 6.5)")
        XCTAssertNil(viewModel.sessionUser)
    }
}