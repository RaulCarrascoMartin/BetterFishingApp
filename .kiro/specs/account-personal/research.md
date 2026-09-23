# Research & Design Decisions: account-personal

## Summary
- **Feature**: account-personal
- **Discovery Scope**: Complex Integration (auth + perfil + favoritos + sync sobre Supabase sobre seams ya especificados)
- **Key Findings**:
  - El seam `SupabaseDatabaseAccess` de supabase-foundation expone únicamente `select` y `rpc`: todas las escrituras de la cuenta (catch upsert, perfil upsert) deben hacerse por RPC, no por el query builder. Los favoritos de spots los persigue spot-discovery (dueño de `spot_favorites` y sus RPC); account-personal solo los consume.
  - `LocalFileCatchRepository` no expone forma de escribir una captura conservando su `Catch.id` (su `saveCatch` genera un UUID nuevo); la pull del sync necesita un store local paralelo que escriba con el id remoto preservado, sin tocar los ficheros ni protocolos de catch-log.
  - spot-discovery (upstream) define `SpotRepository` con favoritos por cuenta (`favoriteSpotIDs()`/`favoriteSpots()`/`setFavorite(spotID:isFavorite:)`); account-personal lo consume vía el adaptador anti-corrupción `SpotRepositorySpotPresenting` sin duplicar tabla/RPC propias; cualquier cambio en su contrato es trigger de revalidación.

## Research Log

### 1. Escrituras por RPC dentro del seam `SupabaseDatabaseAccess`
- **Context**: El diseño de supabase-foundation define `SupabaseDatabaseAccess` con `select(columns:from:filters:limit:)` y `rpc(_:arguments:)` (sin insert/update/delete). account-personal necesita escribir en `profiles` y `catches`; los favoritos los escribe spot-discovery vía su propio `SpotRepository`.
- **Sources Consulted**: `.kiro/specs/supabase-foundation/design.md` (contrato del seam).
- **Findings**:
  - El seam es la única vía; no se debe modificar supabase-foundation (mantuvenir el seam).
  - PostgreSQL + PostgREST soportan funciones SQL (`rpc`) que encapsulan INSERT/UPDATE/DELETE con RLS y `auth.uid()`.
  - `Catch` es `Codable`: la función `upsert_catch` puede recibir el `Catch` serializado como JSON (texto) y castearlo a `jsonb` en SQL.
- **Implications**: Toda escritura pasa por RPC; las lecturas (perfil, favoritos, lista remota de capturas) usan `select`. El esquema y las funciones se entregan como artefacto SQL versionado.

### 2. Preservar `Catch.id` en la pull: store local de sync paralelo
- **Context**: La pull trae capturas remotas al registro local y debe hacer merge idempotente por `Catch.id` (Req 5.3). `LocalFileCatchRepository.saveCatch` crea un UUID nuevo; su `updateCatch` no permite cambiar especie/foto/id. Los protocolos de catch-log no se pueden modificar.
- **Sources Consulted**: `.kiro/specs/catch-log/design.md` (layout `<uuid>.jpg` + `<uuid>.json`), `App/Services/CatchLog/LocalFileCatchRepository.swift` (`directoryURL` privado).
- **Findings**:
  - Un store paralelo (`SyncCatchLocalStore` implementado por `FileSyncCatchStore`) puede escribir `<id>.json` + `<id>.jpg` en el mismo directorio `Application Support/Catches/` siguiendo el layout documentado de catch-log; el repositorio real lo leerá igualmente en `listCatches`.
  - `LocalFileCatchRepository.photoData(for:)` devuelve nil si el `.jpg` no existe → una captura importada sin foto degrada con thumbnail nil (ya soportado por la UI).
  - El directorio se comparte vía composition root (misma URL derivada del mismo constante), no vía repliegue de privados de catch-log.
- **Implications**: account-personal no toca ningún fichero de catch-log; añade `SyncCatchLocalStore`/`FileSyncCatchStore`. El layout compartido es un trigger de revalidación y se cubre con tests de integración cruzada (write-via-sync → read-via-repository).

### 3. Resolución de conflictos "variante más reciente" sin reloj local
- **Context**: Req 5.4 (misma id, contenidos distintos → conservar la más reciente). El modelo local no tiene `updatedAt`; el fichero `.json` local no ofrece timestamps fiables de edición.
- **Findings**:
  - Se mantiene un ledger (`CatchSyncLedger`) con el hash del contenido local y el `updated_at` remoto por cada id.
  - Regla LWW determinista: si cambió solo local → push; solo remoto → pull; ambos → gana el lado con timestamp mayor (remoto `updated_at` vs `lastLocalPushAt` del ledger); si hay empate, gana local (el registro local es la fuente de verdad local, Req 5.6).
- **Implications**: `CatchSyncMerger` es una función pura testeable con timestamps inyectados; el ledger persiste en `Application Support/CatchSync/sync-ledger.json`.

### 4. Favoritos sin acoplar a la geometría
- **Context**: El brief exige consumir `SpotRepository` de spot-discovery para la presentación de favoritos sin acoplarse a su geometría. spot-discovery aún no está especificado.
- **Findings**: `spot-discovery` (spec activa) define `SpotRepository` con favoritos por cuenta: `favoriteSpotIDs()`/`favoriteSpots()`/`setFavorite(spotID:isFavorite:)`, tabla `spot_favorites` y RPC `my_favorite_*`/`add_spot_favorite`/`remove_spot_favorite`.
- **Decisión**: account-personal consume `any SpotRepository` (de spot-discovery) vía el adaptador `SpotRepositorySpotPresenting` y construye `FavoriteSpot` sin campos geométricos. `favoriteSpotIDs()`, `favorites()` y `setFavorite(spotID:isFavorite:)` delegan en el seam; la cuenta no crea tablas ni RPC propias de favoritos (spot-discovery es el dueño de la persistencia).
- **Implications**: El contrato consumido de `SpotRepository` (`favoriteSpotIDs`/`favoriteSpots`/`setFavorite`) es el definido por spot-discovery; cualquier cambio en él es Revalidation Trigger de `SpotRepositorySpotPresenting`.

### 5. Avatar y fotos de capturas en storage
- **Context**: Perfil (avatar) y capturas (foto) requieren storage de la cuenta.
- **Decisión**: Buckets `avatars` (objeto `{user_id}/avatar.jpg`) y `catches` (objeto `{user_id}/{catch_id}.jpg`). La ruta se guarda en las filas (`profiles.avatar_path`, `catches.photo_path`); la UI descarga los datos vía `SupabaseStoring` bajo demanda.
- **Implications**: `SupabaseProfileRepository`/`CatchSyncService` dependen de `SupabaseStoring` con buckets arbitrarios (contrato de supabase-foundation). El avatar puede recuperarse tras reinstalar (Req 3.4).

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Escrituras al estilo query builder | Extender `SupabaseDatabaseAccess` con insert/update/delete | Natural, evita SQL | Cambia el seam base especificado | Rechazada: no se modifica supabase-foundation |
| Todo vía RPC | Funciones SQL para upsert/delete de perfil, favoritos y catches | Respetar el seam sin tocarlo; RLS centralizado | Más SQL a mantener | **Elegida** |
| Import local vía repositorio | Añadir `importCatch` a `LocalFileCatchRepository` | Reutiliza persistencia | Toca un fichero de catch-log | Rechazada: no se tocan ficheros ajenos |
| Store local de sync paralelo | `FileSyncCatchStore` escribe `<id>.json`+`<id>.jpg` en el mismo directorio | Catch-log intacto; id preservado | Layout compartido (drift) | **Elegida** con tests cruzados |
| Favoritos con geometría | Almacenar el spot completo en el favorito | Simple de renderizar | Acopla al modelo geométrico | Rechazada: brief pide sin geometría |

## Design Decisions

### Decision: account-personal consume seams existentes sin modificarlos
- **Context**: Dependencias obligatorias supabase-foundation (auth/storage/db) y catch-log (CatchRepository + Catch).
- **Alternatives**: Extender `SupabaseDatabaseAccess`; tocar `LocalFileCatchRepository`.
- **Selected Approach**: Escrituras por RPC; escritura local de pull por `FileSyncCatchStore` paralelo; lectura local por `CatchRepository` (seam preservado); auth por `SupabaseAuthProviding` envuelto por `AccountSessionManager`.
- **Rationale**: Mantiene la dirección de dependencias features → servicios → core y no invalida specs validadas.
- **Trade-offs**: SQL extra en provisioning; layout compartido con catch-log (mitigado con tests y revalidation trigger).
- **Follow-up**: Validar con `supabase-foundation` la forma de `rpc` (parámetros `SupabaseJSONValue`, decodificación de respuesta para funciones void).

### Decision: sesión expuesta a la UI por `AccountSessionManager` (wrapper)
- **Context**: La UI de cuenta necesita estado de sesión y errores tipados sin filtrar tipos del SDK.
- **Selected Approach**: `AccountSessionManaging` (protocolo) + `AccountSessionManager` (actor) que envuelve `SupabaseAuthProviding`, proyecta `SupabaseAuthEvent` → `AccountSessionState` y mapea `SupabaseBaseError` → `AccountError`.
- **Rationale**: Mantiene el boundary base (Req 6.2/6.3 de supabase-foundation) intacto y da errores localizables a la UI.

### Decision: la sync también sube/borra en remoto según el registro local
- **Context**: Req 5.1 (subir capturas locales) y 5.7 (borrado local no se redescarga). La distancia "fuente de verdad local" (Req 5.6) implica que borrar localmente puede reflejarse o no en remoto.
- **Selected Approach**: La sync es bidireccional y dirigida por el registro local: push upsert local→remoto para ids locales; la pull trae ids remotos ausentes localmente; los ids eliminados localmente se marcan en el ledger (tombstone) para no redescar; el borrado remoto de capturas no se propaga (fuera de alcance del brief: solo push/pull + merge). 
- **Rationale**: Cumple 5.7 sin exigir `delete_catch` remoto; mantiene el registro local como fuente.
- **Follow-up**: documentar como fuera de alcance el borrado remoto propagado.

## Risks & Mitigations
- Layout compartido entre `LocalFileCatchRepository` y `FileSyncCatchStore` → tests de integración cruzada; trigger de revalidación si catch-log cambia el layout.
- Contrato consumido de `SpotRepository` (spot-discovery no especificado) → suposición explícita + revalidación al especificar spot-discovery.
- `rpc` con payload JSON de `Catch` → validar decodificación de respuesta void en impl; `SupabaseJSONValue.string` como transporte.
- Pérdida de datos si la sync falla a mitad → el ledger solo se actualiza tras éxito; el registro local nunca se muta en push (solo el remoto); en pull el store escribe de forma atómica (JSON+JPG).
- El mapa de spots aún no existe → la visibilidad de favoritos en el mapa se entrega como seam de datos (`favoriteSpotIDs`), no como UI; revalidación al integrar el mapa.

## References
- `.kiro/specs/supabase-foundation/requirements.md`, `design.md`, `tasks.md` (seams base consumidos).
- `.kiro/specs/catch-log/requirements.md`, `design.md`, `tasks.md` (modelo `Catch`, `CatchRepository`, layout de persistencia local).
- `.kiro/specs/spot-discovery/brief.md` (contrato esperado de `SpotRepository`).
- `App/AppCompositionSupport.swift`, `App/Services/CatchLog/LocalFileCatchRepository.swift` (integración del composition root y layout real).