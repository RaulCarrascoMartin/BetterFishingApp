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

- [ ] 3.2 (P) Escritura local de descargas (SyncCatchLocalStore + FileSyncCatchStore)
  - Definir el protocolo `SyncCatchLocalStore` (importCatch, localCatch, localModificationDate, photoData).
  - Implementar el actor `FileSyncCatchStore` que escribe `<id>.json` (metadatos `Catch` con el `id` dado) y, si hay `photoData`, `<id>.jpg` en `Application Support/Catches/` respetando el layout compartido de catch-log sin tocar su código; escritura atómica (el JSON primero, luego la foto) y nunca pisando el `.json` de otra id; directorio inyectable desde el composition root (misma URL que `LocalFileCatchRepository`).
  - Añadir `FileSyncCatchStoreTests`: importCatch con id fijo es leída después por `CatchRepository.listCatches()` (integración cruzada con catch-log); foto opcional (sin thumbnail); escritura no atómica no deja ficheros huérfanos.
  - Observable: `FileSyncCatchStoreTests` pasan y la captura importada es visible para el registro local con su id preservado.
  - _Boundary: Services/CatchLog (store local)_
  - _Depends: 1.3_
  - _Requirements: 5.2, 5.6_

- [ ] 3.3 Sincronización orquestada (CatchSynchronizing + CatchSyncService)
  - Definir `CatchSyncResult` (pushed/pulled/skipped), `enum CatchSyncError` (noSession/remoteLoadFailed/pushFailed/pullFailed/ledgerFailed) y el protocolo `CatchSynchronizing` (sync(userID:) → CatchSyncResult).
  - Implementar el actor `CatchSyncService` con la secuencia: (1) leer capturas locales vía `CatchRepository.listCatches()`; (2) leer capturas remotas vía `select` sobre `catches` por `user_id`; (3) cargar el snapshot del `CatchSyncLedger`; (4) decidir acción por id con `CatchSyncMerger`; (5) ejecutar push (`rpc upsert_catch` + upload de la foto a `catches/{user_id}/{id}.jpg`) y pull (download de la foto + `FileSyncCatchStore.importCatch` preservando el id); (6) commit del ledger solo si toda la secuencia tiene éxito (los fallos no actualizan el ledger → reintento seguro).
  - Registrar tombstones: ids presentes en `lastSyncedRemoteIDs` del ledger y ausentes del registro local no se vuelven a descargar.
  - Añadir `CatchSyncServiceTests` con `SupabaseBaseFake` (select/rpc) + `FileSyncCatchStore` + `CatchRepository` reales en directorios temporales: push de capturas locales idempotente (segunda llamada → 0 pushed); pull trae capturas remotas al registro local preservando el id; tras borrar localmente una captura sincronizada el siguiente sync no la re-descarga (tombstone); conflicto LWW con captura local más reciente gana; fallo de red no altera el registro local ni el ledger.
  - Observable: `CatchSyncServiceTests` pasan y `sync` expone `CatchSyncResult` consistente con el requerimiento 5.8.
  - _Depends: 3.1, 3.2_
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8, 6.4_

## 4. Interfaz de cuenta (UI)

- [ ] 4.1 AccountViewModel
  - Implementar `@MainActor @Observable AccountViewModel` con estados sessionState, profile, favorites, isSyncing, lastSyncResult y errorMessage.
  - Suscribirse a `sessionState`; al pasar a signedIn cargar perfil y favoritos; al pasar a signedOut limpiar los datos personales (profile/favorites/resultado de sync).
  - Acciones signUp/signIn/signOut con bloqueo de envíos duplicados y estado de carga; saveDisplayName y uploadAvatar conservando el valor anterior si falla (mostrar error tipado); toggleFavorite re-consultando el estado real si falla; sync exponiendo `CatchSyncResult` o `CatchSyncError`.
  - Añadir test unitario del VM: al emitir signedOut se limpian profile y favorites y se conserva nada de la cuenta anterior.
  - Observable: el VM compila, orquesta los cuatro servicios sin dependencias UI, y el test de limpieza en signOut pasa.
  - _Requirements: 1.5, 1.6, 2.5, 3.5, 4.6, 6.4_

- [ ] 4.2 (P) Formulario de registro e inicio de sesión (SignInSignUpFormView)
  - Construir el formulario email + contraseña con pestañas registro/login que consume `AccountViewModel`.
  - Mostrar estado de carga mientras opera e impedir envíos duplicados; presentar los errores tipados distintamente (credenciales inválidas, email en uso, red, configuración).
  - Observable: el formulario compila; en estado signedOut muestra la invitación a registrarse/iniciar sesión y refleja carga y errores.
  - _Boundary: Features/Account (formulario)_
  - _Depends: 4.1_
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 6.2_

- [ ] 4.3 (P) Edición de perfil (ProfileEditView)
  - Construir la vista de nombre editable (guardar vía `saveDisplayName`) y de selección de imagen de avatar (subida vía `uploadAvatar`).
  - Mostrar nombre por defecto y ningún avatar si el perfil no los tiene; conservar el valor anterior visible si el guardado/la subida fallan y presentar el error.
  - Observable: la vista compila y refleja nombre y avatar actualizados tras guardar/subir con éxito.
  - _Boundary: Features/Account (edición de perfil)_
  - _Depends: 4.1_
  - _Requirements: 3.2, 3.3, 3.5, 3.6_

- [ ] 4.4 (P) Lista de favoritos (FavoritesListView)
  - Construir la lista de favoritos con presentación sin geometría (nombre y categoría) consumiendo `AccountViewModel`.
  - Permitir marcar/desmarcar desde la lista; sin sesión activa no ofrecer favoritos y comunicar que se requiere iniciar sesión; si el guardado/eliminación falla, preservar el estado previo visible y mostrar el error.
  - Observable: la vista compila y la lista refleja los favoritos de la cuenta (y su estado al desmarcar).
  - _Boundary: Features/Account (lista de favoritos)_
  - _Depends: 4.1_
  - _Requirements: 4.1, 4.3, 4.6, 4.7_

- [ ] 4.5 Pantalla de cuenta (AccountView)
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
