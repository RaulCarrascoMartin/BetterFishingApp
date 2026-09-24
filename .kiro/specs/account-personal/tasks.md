# Plan de Implementación: account-personal

Fases: Foundation → Core → Integración → Validación.

## 1. Foundation

- [x] 1.1 Crear el esquema remoto de la cuenta (DDL idempotente)
  - Escribir `Supabase/schema/account_personal.sql` con: extensión `pgcrypto`, tablas `public.profiles` (user_id PK → auth.users, display_name, avatar_path, updated_at) y `public.catches` (id PK, user_id con índice, species jsonb, date, location jsonb, notes, created_at, updated_at, photo_path, unique(id, user_id)).
  - Incluir políticas RLS (`profiles_own`, `catches_own` con `auth.uid() = user_id`) para las dos tablas y `security invoker` en las funciones.
  - Incluir RPCs `upsert_profile` (insert/on conflict con guard `auth.uid()`) y `upsert_catch` (jsonb de `Catch` a columnas, on conflict por id con guard `auth.uid()`).
  - NO crear ningún esquema/RPC de favoritos: la tabla `spot_favorites`, sus RPC (`my_favorite_*` / `add_spot_favorite` / `remove_spot_favorite`) y su RLS son propiedad de spot-discovery; account-personal solo los consume vía `SpotRepository`.
  - Anotar el provisioning del bucket `avatars` y `catches` con políticas de objeto por `user_id` (dashboard/CLI, fuera del SQL).
  - Observable: el DDL es aplicable de forma idempotente (create table if not exists / create or replace function) a una instancia Supabase y todas las tablas usadas por los servicios tienen RLS y RPC disponibles.
  - _Requirements: 3.1, 5.1, 5.2_

- [ ] 1.2 Registrar los ficheros nuevos en el target de la app
  - El proyecto usa referencias explícitas en `BetterFishing.xcodeproj/project.pbxproj` (PBXBuildFile/PBXFileReference), no grupos sincronizados por sistema de ficheros.
  - Registar cada fichero Swift nuevo (modelos, services, features y tests) en el target correspondiente siguiendo el patrón existente, a medida que se vayan creando.
  - Observable: `xcodebuild` compila el target de la app y los targets de test con todos los ficheros nuevos de la feature sin errores de "no such file" ni de equivalencia de objetos.
  - _Requirements: 6.1_

- [x] 1.3 Modelos de dominio de cuenta
  - Crear `AccountProfile` (userID, displayName, avatarPath) `Codable` para el perfil en `profiles`.
  - Crear `FavoriteSpot` (spotID, name, category) `Codable/Sendable/Equatable/Identifiable` sin ningún campo geométrico.
  - Crear `RemoteCatch` (id, userID, species, date, location, notes, createdAt, updatedAt, photoPath) con CodingKeys en snake_case (`photo_path`, `user_id`, `created_at`, `updated_at`) y `asCatch()` que conserva el `id`.
  - Añadir `RemoteCatchTests`: round-trip Codable con species/location como jsonb y `asCatch()` conserva el id.
  - Observable: los tres tipos compilan y `RemoteCatchTests` pasan.
  - _Requirements: 3.1, 4.8, 5.2_

- [x] 1.4 Ledger de sincronización y huellas
  - Definir `enum Fingerprint` (sha256) y las structs `CatchSyncLedgerSnapshot` (entries, tombstonedIDs, lastSyncedRemoteIDs), `CatchSyncLedgerEntry` (lastLocalFingerprint, lastRemoteUpdatedAt, lastLocalPushedAt).
  - Implementar el actor `CatchSyncLedger` con `snapshot()` y `commit(_:)` persistido en `Application Support/CatchSync/sync-ledger.json` con escritura atómica (fichero temporal + rename) y directorio inyectable para tests.
  - Añadir `CatchSyncLedgerTests`: round-trip del snapshot en directorio temporal y commit fallido no altera el snapshot previo.
  - Observable: `CatchSyncLedgerTests` pasan y el fichero del ledger se persiste atómicamente.
  - _Requirements: 5.3, 5.5, 5.7_

## 2. Servicios de cuenta (Core)

- [x] 2.1 Sesión y autenticación (AccountSessionManaging + AccountSessionManager)
  - Definir `enum AccountSessionState` (signedOut / signedIn(SupabaseUser)), `enum AccountError` (signUpFailed/signInFailed/signOutFailed/sessionUnavailable) y el protocolo `AccountSessionManaging` (currentUser, sessionState como AsyncStream, signUp/signIn/signOut).
  - Implementar el actor `AccountSessionManager` que envuelve `SupabaseAuthProviding` sin filtrar tipos del SDK: signUp/signIn dejan currentUser no nil y emiten signedIn; signOut emite signedOut y deja currentUser nil; errores mapeados con motivo distinto (credenciales inválidas, red, configuración); restauración de sesión y renovación por refresh delegadas en la capa base (evento sessionRestored → signedIn) y proyección del stream de eventos de sesión.
  - No registrar tokens ni credenciales en logs (os.Logger categoría `Account`).
  - Añadir `AccountSessionManagerTests` con `SupabaseBaseFake`: signUp/signIn emiten signedIn; signOut emite signedOut; fallo de signin → `AccountError.signInFailed`; restauración de sesión → signedIn.
  - Observable: `AccountSessionManagerTests` pasan y la UI puede observar `sessionState` sin conocer el SDK.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_

- [x] 2.2 (P) Perfil (ProfileManaging + SupabaseProfileRepository)
  - Definir `enum AccountProfileError` (loadFailed/updateFailed/uploadAvatarFailed/notAuthenticated) y el protocolo `ProfileManaging` (profile, updateDisplayName, updateAvatar, avatarData).
  - Implementar el actor `SupabaseProfileRepository` sobre `SupabaseDatabaseAccess`/`SupabaseStoring`: `profile()` con select sobre `profiles` por `user_id` y fila por defecto (nombre vacío, sin avatar) si no existe; `updateDisplayName` vía rpc `upsert_profile` con el `user_id` autenticado; `updateAvatar` subiendo al bucket `avatars` la ruta `{user_id}/avatar.jpg` (upsert) y devolviendo la ruta; `avatarData` descargando por esa ruta; el `user_id` actual se obtiene del seam de auth (sin tokens en logs).
  - Añadir `SupabaseProfileRepositoryTests` con fakes de db/storage: perfil por defecto si no existe; updateName invoca `upsert_profile`; uploadAvatar devuelve la ruta y download la recupera.
  - Observable: `SupabaseProfileRepositoryTests` pasan y el perfil es recuperable y editable vía los seams base.
  - _Boundary: Services/Account (perfil)_
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [x] 2.3 (P) Consumo de favoritos (FavoritesPresenting + SpotRepositorySpotPresenting)
  - Definir `FavoriteSpot` (ya del 1.3), el protocolo `FavoritesPresenting` (favorites, favoriteSpotIDs, isFavorite, setFavorite) y `enum FavoritesError` (loadFailed/saveFailed/removeFailed/notAuthenticated/authenticationRequired).
  - Implementar `FavoritesPresenting` vía el adaptador anticorrupción `SpotRepositorySpotPresenting` que inyecta el seam `SpotRepository` de spot-discovery (desde el composition root) y delega: `favoriteSpotIDs()` → `repository.favoriteSpotIDs()`; `favorites()` → `repository.favoriteSpots()` mapeado a `FavoriteSpot` (solo id/name/category, sin geometría); `isFavorite(spotID:)` → contiene en `favoriteSpotIDs()`; `setFavorite(spotID:isFavorite:)` → `repository.setFavorite(spotID:isFavorite:)`. La cuenta NO crea tabla, RPC, seam ni lógica propios de favoritos: la persistencia y su autoría son de spot-discovery.
  - Traducir `SpotRepositoryError` a `FavoritesError`: sin sesión → `authenticationRequired`; backend/query → `loadFailed`/`saveFailed`/`removeFailed` según la operación.
  - Añadir `SpotRepositorySpotPresentingTests` con un doble de `SpotRepository` de spot-discovery (patrón `SpotRepositoryFake` de spot-discovery): marcar/desmarcar delega en `setFavorite`, lista y favoriteSpotIDs filtran la presentación, sin sesión se traduce `authenticationRequired`, y el adaptador no depende de la geometría.
  - Observable: `SpotRepositorySpotPresentingTests` pasan y los favoritos quedan ligados a la cuenta vía el seam `SpotRepository` de spot-discovery (RLS/RPC de spot-discovery).
  - _Boundary: Services/Account (consumo de favoritos) + anticorrupción spot-discovery_
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8_

## 3. Sincronización del registro (Core)

- [x] 3.1 (P) Motor de decisión de sincronización (CatchSyncMerger)
  - Definir `enum CatchSyncAction` (push(Catch)/pull(RemoteCatch)/skip), `CatchSyncMergerInput` y `struct CatchSyncMerger.decide(for:input:)` como función pura sin efectos secundarios.
  - Implementar las reglas por `Catch.id`: solo local → push; solo remoto → pull salvo que esté tombstoned (skip); ambos sin cambios → skip (idempotencia comparando huella local y updated_at remoto con el ledger); solo local cambió → push; solo remoto cambió → pull; ambos cambiaron → LWW comparando `updated_at` remoto con `lastLocalPushedAt` (empate exacto → push, la fuente local manda).
  - Definir el `Fingerprint` como hash (CryptoKit) de la serialización canónica de `Catch` (id, species, date, location, notes).
  - Añadir `CatchSyncMergerTests` con la matriz completa de decisiones: push, pull, skip por idempotencia, LWW ambos sentidos, empate → push y tombstone bloqueando el pull.
  - Observable: `CatchSyncMergerTests` pasan y el merger no toca red ni disco.
  - _Boundary: Services/CatchLog (merger)_
  - _Depends: 1.4_
  - _Requirements: 5.3, 5.4, 5.7_

- [x] 3.2 (P) Escritura local de descargas (SyncCatchLocalStore + FileSyncCatchStore)
  - Definir el protocolo `SyncCatchLocalStore` (importCatch, localCatch, localModificationDate, photoData).
  - Implementar el actor `FileSyncCatchStore` que escribe `<id>.json` (metadatos `Catch` con el `id` dado) y, si hay `photoData`, `<id>.jpg` en `Application Support/Catches/` respetando el layout compartido de catch-log sin tocar su código; escritura atómica (el JSON primero, luego la foto) y nunca pisando el `.json` de otra id; directorio inyectable desde el composition root (misma URL que `LocalFileCatchRepository`).
  - Añadir `FileSyncCatchStoreTests`: importCatch con id fijo es leída después por `CatchRepository.listCatches()` (integración cruzada con catch-log); foto opcional (sin thumbnail); escritura no atómica no deja ficheros huérfanos.
  - Observable: `FileSyncCatchStoreTests` pasan y la captura importada es visible para el registro local con su id preservado.
  - _Boundary: Services/CatchLog (store local)_
  - _Depends: 1.3_
  - _Requirements: 5.2, 5.6_

- [x] 3.3 Sincronización orquestada (CatchSynchronizing + CatchSyncService)
  - Definir `CatchSyncResult` (pushed/pulled/skipped), `enum CatchSyncError` (noSession/remoteLoadFailed/pushFailed/pullFailed/ledgerFailed) y el protocolo `CatchSynchronizing` (sync(userID:) → CatchSyncResult).
  - Implementar el actor `CatchSyncService` con la secuencia: (1) leer capturas locales vía `CatchRepository.listCatches()`; (2) leer capturas remotas vía `select` sobre `catches` por `user_id`; (3) cargar el snapshot del `CatchSyncLedger`; (4) decidir acción por id con `CatchSyncMerger`; (5) ejecutar push (`rpc upsert_catch` + upload de la foto a `catches/{user_id}/{id}.jpg`) y pull (download de la foto + `FileSyncCatchStore.importCatch` preservando el id); (6) commit del ledger solo si toda la secuencia tiene éxito (los fallos no actualizan el ledger → reintento seguro).
  - Registrar tombstones: ids presentes en `lastSyncedRemoteIDs` del ledger y ausentes del registro local no se vuelven a descargar.
  - Añadir `CatchSyncServiceTests` con `SupabaseBaseFake` (select/rpc) + `FileSyncCatchStore` + `CatchRepository` reales en directorios temporales: push de capturas locales idempotente (segunda llamada → 0 pushed); pull trae capturas remotas al registro local preservando el id; tras borrar localmente una captura sincronizada el siguiente sync no la re-descarga (tombstone); conflicto LWW con captura local más reciente gana; fallo de red no altera el registro local ni el ledger.
  - Observable: `CatchSyncServiceTests` pasan y `sync` expone `CatchSyncResult` consistente con el requerimiento 5.8.
  - _Depends: 3.1, 3.2_
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.4_

## 4. Interfaz de cuenta (UI)

- [x] 4.1 AccountViewModel
  - Implementar `@MainActor @Observable AccountViewModel` con estados sessionState, profile, favorites, isSyncing, lastSyncResult y errorMessage.
  - Suscribirse a `sessionState`; al pasar a signedIn cargar perfil y favoritos; al pasar a signedOut limpiar los datos personales (profile/favorites/resultado de sync).
  - Acciones signUp/signIn/signOut con bloqueo de envíos duplicados y estado de carga; saveDisplayName y uploadAvatar conservando el valor anterior si falla (mostrar error tipado); toggleFavorite re-consultando el estado real si falla; sync exponiendo `CatchSyncResult` o `CatchSyncError`.
  - Añadir test unitario del VM: al emitir signedOut se limpian profile y favorites y se conserva nada de la cuenta anterior.
  - Observable: el VM compila, orquesta los cuatro servicios sin dependencias UI, y el test de limpieza en signOut pasa.
  - _Requirements: 1.5, 1.6, 2.5, 3.5, 4.6, 6.4_

- [x] 4.2 (P) Formulario de registro e inicio de sesión (SignInSignUpFormView)
  - Construir el formulario email + contraseña con pestañas registro/login que consume `AccountViewModel`.
  - Mostrar estado de carga mientras opera e impedir envíos duplicados; presentar los errores tipados distintamente (credenciales inválidas, email en uso, red, configuración).
  - Observable: el formulario compila; en estado signedOut muestra la invitación a registrarse/iniciar sesión y refleja carga y errores.
  - _Boundary: Features/Account (formulario)_
  - _Depends: 4.1_
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 6.2_

- [x] 4.3 (P) Edición de perfil (ProfileEditView)
  - Construir la vista de nombre editable (guardar vía `saveDisplayName`) y de selección de imagen de avatar (subida vía `uploadAvatar`).
  - Mostrar nombre por defecto y ningún avatar si el perfil no los tiene; conservar el valor anterior visible si el guardado/la subida fallan y presentar el error.
  - Observable: la vista compila y refleja nombre y avatar actualizados tras guardar/subir con éxito.
  - _Boundary: Features/Account (edición de perfil)_
  - _Depends: 4.1_
  - _Requirements: 3.2, 3.3, 3.5, 3.6_

- [x] 4.4 (P) Lista de favoritos (FavoritesListView)
  - Construir la lista de favoritos con presentación sin geometría (nombre y categoría) consumiendo `AccountViewModel`.
  - Permitir marcar/desmarcar desde la lista; sin sesión activa no ofrecer favoritos y comunicar que se requiere iniciar sesión; si el guardado/eliminación falla, preservar el estado previo visible y mostrar el error.
  - Observable: la vista compila y la lista refleja los favoritos de la cuenta (y su estado al desmarcar).
  - _Boundary: Features/Account (lista de favoritos)_
  - _Depends: 4.1_
  - _Requirements: 4.1, 4.3, 4.6, 4.7_

- [x] 4.5 Pantalla de cuenta (AccountView)
  - Componer `AccountView` sobre `AccountViewModel`: signedOut → `SignInSignUpFormView`; signedIn → cabecera de perfil con `ProfileEditView`, `FavoritesListView`, botón "Sincronizar" que expone `CatchSyncResult`/error y control de cierre de sesión que vuelve a la pantalla de registro/inicio de sesión.
  - Sin contexto de Supabase (`accountViewModel == nil`) mostrar el estado degradado "Cuenta no disponible" con explicación, sin romper el arranque.
  - Observable: la vista compila y cada estado (signedOut, signedIn con perfil/favoritos/sync, degradado) renderiza lo definido.
  - _Boundary: Features/Account (vista)_
  - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

## 5. Integración

- [ ] 5.1 Componer las dependencias de la cuenta en el composition root (AppCompositionSupport)
  - Cuando el `SupabaseStack` esté configurado (supabase != nil), construir `AccountSessionManager`, `SupabaseProfileRepository`, `SpotRepositorySpotPresenting` (inyectando el seam `SpotRepository` que spot-discovery ya expone en `AppRootServices`), `CatchSyncService` (con `FileSyncCatchStore` apuntando al mismo directorio que `LocalFileCatchRepository`) y el `AccountViewModel`.
  - Añadir `accountViewModel` a `AppRootServices`; dejar la sección de cuenta en estado degradado (nil) cuando no haya stack.
  - Observable: `AppRootServices` expone `accountViewModel` solo con Supabase configurado y el build compila.
  - _Requirements: 6.1_

- [ ] 5.2 Añadir el tab "Cuenta" a la navegación principal (BetterFishingApp)
  - Añadir el tercer tab "Cuenta" (icono `person.crop.circle`) con `AccountView` al `TabView` existente de `RootView` (BetterFishingApp.swift:59), conservando el estado por tab del patrón actual.
  - Observable: el build compila y la app muestra tres tabs con acceso a la cuenta desde la navegación principal.
  - _Requirements: 6.1_

## 6. Validación

- [ ] 6.1 Flujo E2E de sesión
  - Con dobles de servicios: sin sesión → formulario; login con un doble → perfil visible; logout → vuelve al formulario y dejan de mostrarse los datos personales.
  - Observable: el test E2E del flujo de sesión pasa.
  - _Requirements: 1.6, 6.2, 6.3, 6.5_

- [ ] 6.2 Flujo E2E de perfil
  - Con dobles de servicios: editar nombre → se muestra actualizado; aportar avatar → se muestra; simular fallo de guardado → se conserva el valor anterior y se muestra el error.
  - Observable: el test E2E del flujo de perfil pasa.
  - _Requirements: 3.2, 3.3, 3.6_

- [ ] 6.3 Flujo E2E de favoritos
  - Con dobles de servicios: marcar/desmarcar favorito → la lista refleja el cambio; `favoriteSpotIDs` del seam `SpotRepository` queda actualizado.
  - Observable: el test E2E del flujo de favoritos pasa.
  - _Requirements: 4.2, 4.3, 4.4_

- [ ] 6.4 Flujo E2E de sincronización
  - Con fakes de datos remotos: pulsar "Sincronizar" → se muestra el resultado de éxito (pushed/pulled); simular fallo de red → registro local intacto y la UI ofrece reintentar.
  - Observable: el test E2E del flujo de sync pasa.
  - _Requirements: 5.5, 5.8, 6.4_

- [ ] 6.5 Regresión completa y revisión de cobertura
  - Ejecutar la suite completa (`xcodebuild test`) de todos los targets y corregir solo fallos introducidos por esta feature.
  - Verificar que cada criterio de aceptación (39 en 6 requerimientos) aparece en al menos una tarea ejecutada y que ningún componente del diseño quedó sin tarea.
  - Observable: la suite completa pasa y la traza requerimientos → tareas está completa sin huecos.
  - _Requirements: 5.5, 5.8_
## Implementation Notes
- 1.1: DDL idempotente en `Supabase/schema/account_personal.sql` calcado del design.md (pgcrypto, profiles, catches + índice, RLS `profiles_own`/`catches_own`, `upsert_profile` language sql, `upsert_catch` language plpgsql con `security invoker`). Notas de clarificación: sin esquema/RPC de favoritos (spot-discovery) y buckets `avatars`/`catches` vía dashboard/CLI.
- 1.3: CodingKeys snake_case en `AccountProfile` (user_id/display_name/avatar_path) y `RemoteCatch` (photo_path/user_id/created_at/updated_at). `asCatch()` async throws es síncrono sin I/O; `photoPath` nil → `"<id>.jpg"`.
- 1.4: `Fingerprint` (CryptoKit SHA256) sobre `CatchFingerprintPayload` (id/species/date/location/notes; excluye photoPath/createdAt). Canonical fijo: `JSONEncoder.outputFormatting = [.sortedKeys]` para determinismo (RED detectó orden de claves no determinista entre llamadas).
- 1.4: Ledger en `<directoryURL>/sync-ledger.json`; `snapshot()` devuelve snapshot vacío si falta el fichero; `commit` atómico (temp + `replaceItemAt`) tras `createDirectory`. Directorio inyectable (fileURL derivado de directoryURL).
- RED: probe deliberado falló (`XCTAssertEqual(1, 2)`) y huella no determinista falló antes del fix `sortedKeys`; tras fix: RemoteCatchTests 4/4 y CatchSyncLedgerTests 4/4 verdes.
- 2.1: `sessionState` es un `AsyncStream` unbuffered-ilimitado con su continuation guardada en el actor; en `init` un Task siembra el estado actual (`currentUser()`) y proyecta `stateChanges()` (signedIn/sessionRestored→`.signedIn(user)`, signedOut→`.signedOut`). `currentUser { get async }` exige computed property async (no método) para satisfacer el protocolo; `sessionState` es `nonisolated` (getter síncrono).
- 2.1: mapeo de errores con `error.localizedDescription` (patrón `errorText`): SupabaseBaseError.signInFailed→`AccountError.signInFailed`, signUp→signUpFailed, signOut→signOutFailed, sessionUnavailable→sessionUnavailable (sin payload); operaciones fallidas NO emiten al stream (sesión preservada, Req 2.6). Logger categoría `Account` sin tokens.
- 2.2: read-modify-write obligatorio en `updateDisplayName`/`updateAvatar`: se lee el perfil actual antes del `rpc upsert_profile` y se reenvían display_name/avatar_path existentes (`upsert_profile` fija AMBOS campos; enviar null borraría el avatar o el nombre en la BD).
- 2.2: `avatarData` usa `download` del bucket `avatars`; fallos de descarga se mapean a `AccountProfileError.loadFailed` (decisión documentada).
- RED 2.1/2.2: stubs deliberados (sesión sin emisiones, perfil `"STUB"`) → 12 tests ejecutados, 16 failures; el stub también detectó en compilación que `currentUser { get async }` se satisface con computed property async. Tras implementación real: AccountSessionManagerTests 5/5 y SupabaseProfileRepositoryTests 7/7 verdes (12/12).
- REVIEW 1 2.1/2.2 (CHANGES_REQUIRED → resueltos): (1) la ruta almacenada/devolvida por `updateAvatar` pasaba por `storage.upload` cuyo fullPath incluye el prefijo del bucket (`avatars/...`) ANTES de `avatarData` que re-antepone el bucket → URL doble-prefijo y 404; se persiste/devuelve la ruta relativa `{user_id}/avatar.jpg` (la misma pasada al upload), `avatarData` recupera sin doble prefijo. (2) `testSignUpEmitsSignedIn`/`testSignInEmitsSignedIn`/`testSessionRestorationYieldsSignedInFirst` eran tautológicos (fake con `isSessionActive == true` → el seeding del init satisfacía el assert): se fuerza `isSessionActive = false` en los tres para que la única fuente de signedIn sea la operación/proyección bajo prueba. (3) `avatarData` no tenía test: se añade `testAvatarDataDownloadsFromAvatarsBucket` (bucket `avatars`, ruta relativa, datos devueltos). Suite resultante: AccountSessionManagerTests 5/5 + SupabaseProfileRepositoryTests 8/8 = 13/13.
- 2.3: `SpotRepositorySpotPresenting` (struct Sendable) delega 1:1 en el seam `SpotRepository`: `favoriteSpotIDs()`→`repository.favoriteSpotIDs()`; `favorites()`→`favoriteSpots().map { FavoriteSpot(...) }`; `isFavorite(spotID:)`→`favoriteSpotIDs().contains(spotID)`; `setFavorite`→`repository.setFavorite`. Sin tabla/RPC propias; inyección vía init.
- 2.3: decisión `category`: design.md muestra `category: $0.category` pero `FavoriteSpot.category` es `String?` y `Spot.category` es `SpotCategory` (enum String) → se usa `$0.category.rawValue`. Solo id/nombre/categoría cruzan el boundary (sin geometría).
- 2.3: traducción `SpotRepositoryError`→`FavoritesError` (helper estático por operación): `authenticationRequired`→`.authenticationRequired` (todas las rutas); `queryFailed(msg)`/`backendUnavailable`→`.loadFailed(msg|"El servidor de spots no está disponible.")` en favoriteSpotIDs/favorites/isFavorite, `.saveFailed` en `setFavorite(isFavorite: true)` y `.removeFailed` en `setFavorite(isFavorite: false)`. `notAuthenticated` se mantiene reservado sin uso local: el gate de sesión lo impone el seam, el adaptador no tiene dependencia de sesión.
- RED 2.3: adaptador stub (delegación vacía) → 7 tests, 14 failures capturados (delegación, mapeo y traducción). Tras implementación real: 7/7 verdes y suite completa BetterFishingTests 313/313 (0 fallos). `SpotRepositoryFake` (spot-discovery) reutilizado sin modificación: ya cubre favoriteIDs/favoriteSpots/setFavorite y errores programables por seam; un assert de `recordedSpotIDs` se retiró del test de `isFavorite` porque `favoriteSpotIDs()` del fake no registra IDs.
- 3.1: reglas 1-4 en `CatchSyncMerger.decide(for:input:)` (static pura, sin I/O/red): solo local→push; solo remoto→pull salvo tombstone→skip; ambos sin cambios→skip (huella local + updated_at remoto vs ledger); solo local→push; solo remoto→pull; ambos→LWW `remote.updatedAt > (lastLocalPushedAt ?? now)` → pull, si no push (empate exacto → push, fuente local manda Req 5.6). Entrada ausente en ledger == "cambiado" en ambos lados → LWW con `lastLocalPushedAt ?? now`; id nuevo jamás sincronizado con `remote.updatedAt <= now` → push (default documentado).
- 3.1: `Catch` no es `Equatable` (catch-log, sin modificar) → `Equatable` manual en `CatchSyncAction`/`CatchSyncMergerInput` comparando `Catch` campo a campo (id/species/photoPath/date/location/notes/createdAt); `Fingerprint`/`RemoteCatch` ya son `Equatable`.
- RED 3.1: stub `decide` → `.skip` → 10 tests, 8 failures (todos los push/pull esperados; skip/skip-tombstone pasan de forma tautológica). Tras implementación real: 10/10 verdes, incluido `testBrandNewIDNeverSyncedDefaultsToNowPushes` que fija el default `now`.
- 3.2: `FileSyncCatchStore` escribe `<id>.json` (metadatos `Catch` con el id dado, sin `saveCatch`) y, si hay foto, `<id>.jpg` en el mismo directorio inyectable de `LocalFileCatchRepository`, respetando el layout compartido de catch-log sin tocar su código (Revalidation Trigger).
- 3.2: escritura atómica con orden fijo: JSON primero (`.atomic`) y luego la foto (`.atomic`); si falla la foto, el JSON queda decodificable (metadatos consistentes) y nunca queda foto huérfana sin su JSON; jamás se pisa el `.json` de otra id.
- 3.2: errores tipados `SyncCatchStoreError.writeFailed` mapeados de fallos subyacentes; `localModificationDate` = fecha de modificación de `<id>.json` (attributesOfItem), nil si no existe (semántica LWW). Logger categoría `CatchSync` sin volcar contenido.
- 3.2: atomicidad probada con un directorio ocupando la ruta `<id>.jpg` (la escritura de la foto falla tras escribir el JSON) → se valida que el JSON sigue decodificándose sin foto huérfana; se descartó probar el orden de aparición de ficheros por resultar más frágil.
- RED 3.2: stub del actor lanzando `writeFailed` → 6 tests, 6 failures (import lanzado + JSON ausente en el caso atómico). Green: 6/6 y suite completa 354/354.
- 3.3: secuencia de `CatchSyncService.sync(userID:)`: (1) `listCatches()` local; (2) `select` sobre `catches` por `user_id` → `remoteLoadFailed`; (3) `ledger.snapshot()` → `ledgerFailed`; (4) `CatchSyncMerger.decide` por id (localFingerprint solo si existe local; `now = Date()`); (5) ejecutar push/pull; (6) `ledger.commit` solo si todo el batch tiene éxito — los fallos abortan antes del commit → reintento seguro (Req 5.5).
- 3.3: contrato cross-task (review 1.1): `p_catch` se serializa con `JSONEncoder.dateEncodingStrategy = .iso8601` (el SQL hace `(c ->> 'date')::timestamptz`); el `photoPath` del payload es la ruta remota relativa al bucket `\(userID)/\(id).jpg`, no la local `<id>.jpg`.
- 3.3: idempotencia vía re-lectura post-push: `upsert_catch` devuelve void → tras el lote de push se hace UN `select` adicional de `catches` por `user_id` y los `updated_at` autoritativos alimentan `lastRemoteUpdatedAt` de los ids empujados (nil si faltan). `lastSyncedRemoteIDs` usa ese conjunto post-push cuando hubo pushes (si no, el del select inicial) para reflejar el estado remoto real tras subir.
- 3.3: tombstones: ids en `lastSyncedRemoteIDs` del ledger ausentes del set local actual se añaden a `tombstonedIDs` del nuevo snapshot Y al ledger de decisión antes de iterar (bloquea el pull del merger, Req 5.7).
- 3.3: push: `upload` a `catches/{userID}/{id}.jpg` (upsert, image/jpeg) antes del rpc; si el `photoDataProvider` devuelve nil se omite el upload pero se hace igualmente el rpc (decisión documentada). Pull: `photoPath` nil → import sin foto; si el download falla se importa igual sin foto (`try?` + warning), probado por `testPullContinuesImportingWhenPhotoDownloadFails`.
- 3.3: `RecordingDB` (en el fichero de tests) conforma `SupabaseDatabaseAccess` con `rowsScript: [[String]]` que avanza desde la front y repite el último lote al agotarse; así el primer select del primer sync devuelve `[]` (fuerza push) y la re-lectura post-push devuelve las filas remotas autoritativas. Las fechas de las filas remotas son NUMÉRICAS en segundos de referencia (JSONDecoder por defecto, no iso8601) y las claves en snake_case.
- 3.3: `CatchSyncError` con `LocalizedError`; el service no usa auth (userID explícito); `noSession` queda reservado para el gate del AccountViewModel (tarea 4.1).
- RED 3.3: stub del actor (sync devuelve `(0,0,0)` sin tocar nada) → 7 tests, 21 failures (push/pull/tombstone/LWW y los dos fallos de red no lanzan). Green: 7/7 y suite completa BetterFishingTests 336/336.
- REVIEW 1 3.3 (CHANGES_REQUIRED → resuelto): el pull importaba la captura con `photoPath` = ruta remota (`userID/id.jpg`) mientras `FileSyncCatchStore` escribe la foto en `<id>.jpg` → `LocalFileCatchRepository.photoData(for:)` no resolvería ninguna foto descargada (Req 5.2 rota). Fix en `performPull`: se fuerza `photoPath = "<id>.jpg"` (layout local) conservando el resto de `asCatch()`; el test `testPullRemoteCatchesPreservingID` se endureció (photoPath local + `photoData(for:)` no nil a través del repositorio real).
- 4.1: consumo de sesión con patrón de SpotMapViewModel: Task guardado en `@ObservationIgnored nonisolated(unsafe) private(set) var sessionStateTask` (cancelado en `deinit`); el Task lee `auth.currentUser` y luego itera `auth.sessionState`. En `signedIn` carga perfil y favoritos (do/catch aislados por fuente, `errorMessage` por fallo y `profile` nil si el load falla); en `signedOut` limpia profile/favorites/lastSyncResult (Req 2.5).
- 4.1: doble guard de carga: `private(set) var isSubmitting` (observable para el formulario de la tarea 4.2, bloquea reentrada de signUp/signIn/signOut) e `isSyncing` para sync. Errores tipados vía `localizedDescription` (patrón `errorText` de sesión) → `errorMessage`; `sync` sin sesión usa `CatchSyncError.noSession` (gate reservado en 3.3).
- 4.1: `saveDisplayName`/`uploadAvatar` conservan el `profile` visible si falla y refrescan del servicio tras éxito; `toggleFavorite` es optimista-free: `setFavorite` y luego re-consulta `favorites()`; si falla, re-consulta el estado real y muestra el error (Req 4.7). `sessionUser` computed derivado de `sessionState` (sin estado redundante).
- RED 4.1: stub sin comportamiento y fakes con lock (NSLock + `withLock`, Swift 6 prohíbe `lock` directo en contextos async) → 8 tests, 14 failures capturados (clear, carga, errores, toggle y sync). Green: 8/8 y suite completa BetterFishingTests 344/344 + UITests 25/25.
- REVIEW 1 4.1 (APPROVED): conformidad total (4 seams por protocolo; `nonisolated(unsafe)` + deinit cancel; do/catch aislado por origen; clear en signedOut; guard `private(set)` isSubmitting/isSyncing; errores de seam tipados, jamás strings de servidor). RED reproducido a mano (14 failures exactos). Checkbox 4.1 intacto hasta aprobación. Mejoras opcionales no bloqueantes: test del guard de envíos duplicados, limpiar `errorMessage` al inicio de cada acción, y borrar nota de doble carga idempotente en arranque.
- REVIEW 4.1 ≤10 líneas: task 4.1 exige "estado de carga" observable para el formulario de la tarea 4.2; inicialmente `isSubmitting` era private → se expone como `private(set)` (guard de reentrada intacto).
- 4.2/4.3/4.4: layout de `Features/Account` en subcarpetas por pantalla (`SessionForm/`, `ProfileEdit/`, `FavoritesList/`) calcado de SpotDiscovery (Map/, SpotDetail/); boundary solo vista; con la ampliación de 4.3 queda UNA excepción: `AccountViewModel.avatarData` (surface de VM necesaria para Req 3.4, ver REVIEW 1 4.3). Patrón de VM `@State` + init idéntico a SpotDetailView.
- 4.3 avatar: PhotosPicker (PhotosUI) → `loadTransferable(Data)` → `UIImage` → `jpegData(0.8)` con contentType `image/jpeg`; preview local `@State`; si `errorMessage` cambia tras `uploadAvatar` se limpia el preview (Req 3.6 conserva el valor anterior). Nombre: draft local sembrado de `profile?.displayName` (onAppear/onChange) y re-sincronizado con el profile tras `saveDisplayName` (éxito→nuevo, fallo→anterior).
- REVIEW 1 4.3 (CHANGES_REQUIRED → resuelto): el preview local no cubría Req 3.4 ("avatar recuperado en cualquier dispositivo") ni la cabecera `signedIn` del diseño ("nombre + avatar"); sin acceso al seam desde la vista, se amplía la superficie del VM (propiedad suya de la feature): `accountViewModel.avatarData: Data?` (nuevo estado) → `loadPersonalData()` lo rellena vía `profileService.avatarData(avatarPath:)` en do/catch aislado (error→nil + loadFailed), `uploadAvatar` lo fija con los bytes aceptados (sin re-descarga) y `clearPersonalData()` lo resetea; `ProfileEditView` renderiza los bytes persistidos como fallback entre el preview local y el placeholder de inicial. Suite completa 344/344 tras el widen.
- 4.4 categoría: `FavoriteSpot.category` es `String?` → mapeo rawValue→etiqueta localizada igual que SpotDetailView (Río / Lago o embalse / Mar / Costa u orilla); vacío con `ContentUnavailableView` (icono heart); signedOut → callout amarillo "requiere iniciar sesión" sin ofrecer lista (el VM ya limpia favorites); fallo de toggle preservado por el VM (sin mutación local).
- RED 4.2/4.3/4.4: probe compile-only temporal referenciando los 3 tipos → 3 fallos "cannot find type in scope"; tras registrar las vistas + fix `try? await loadTransferable` → probe verde (1 test). Probe retirado tras GREEN (tasks de solo vista, sin test files; E2E en 6.1-6.3).
- GREEN 4.2/4.3/4.4: suite de cuenta 28/28 (AccountViewModelTests 8, AccountSessionManagerTests 5, SupabaseProfileRepositoryTests 8, SpotRepositorySpotPresentingTests 7); compila el target de la app con las 3 vistas registradas en pbxproj (fileRef/builfile/grupos por subcarpeta).
- 4.5: `AccountView` con `let viewModel: AccountViewModel?` y `@MainActor`. `nil` → degradado `ContentUnavailableView` "Cuenta no disponible" + explicación (patrón `mapUnavailableView`), id `account.unavailable`. `non-nil` → switch `sessionState`: `.signedOut` envuelve `SignInSignUpFormView`; `.signedIn` compone `ProfileEditView` + `FavoritesListView` + sección sync + cierre de sesión en ScrollView/VStack (layout de SpotDetailView), title "Cuenta".
- 4.5 sync (Req 6.4): botón `account.syncButton` con spinner y `.disabled(isSyncing)`; resultado `account.syncResult` con spans "Subidos X • Descargados Y • Omitidos Z" (pushed/pulled/skipped); fallo con `errorMessage` → callout rojo `account.syncError` (id propio para no colisionar con `account.error` de las subvistas); `lastSyncResult` tiene precedencia sobre el error (semántica mínima: el VM ya lo limpia en signedOut).
- 4.5 sign-out (Req 6.3/6.5): botón destructivo `account.signOut` → `viewModel.signOut()`; sin salida forzada: al emitir `.signedOut` el switch vuelve al formulario automáticamente (routing reactivo de VM, sin navegación explícita). Subvistas reutilizadas sin reimplementar internos; helper local `syncResultRow`/`syncErrorNotice` privados en el mismo fichero.
- RED 4.5: probe compile-only temporal (test que instancia `AccountView(viewModel: nil)`) → fallo real de compilación "cannot find 'AccountView' in scope"; tras implementar y registrar en pbxproj (fileRef AB5/buildFile BB5/grupo Account/Sources phase) → probe 1/1 verde. Probe retirado; suite final 344/344 (E2E en 6.1-6.5).
- REVIEW 1 4.5 (APPROVED): CONCERNS no bloqueantes escaladas, UNA resuelta — `clearPersonalData()` ahora también resetea `errorMessage = nil` (evita que un error de sync obsoleto acompañe al formulario de login tras logout o un nuevo signIn); suite 344/344 tras el cambio. Resta heredada no bloqueante: `errorMessage` es slot único compartido (fallo de perfil/favoritos podría pintarse en el callout `account.syncError`), a revisar en 6.5.
