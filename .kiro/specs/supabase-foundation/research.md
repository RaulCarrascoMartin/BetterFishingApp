# Research & Design Decisions: supabase-foundation

## Summary
- **Feature**: supabase-foundation
- **Discovery Scope**: Extensión de infraestructura (nueva capa de servicios en una app existente) con una dependencia externa nueva (Supabase Swift SDK), ampliada posteriormente para cubrir RPC Postgres sin cuerpo. Se aplicó discovery ligero con verificación web del SDK, análisis de patrones existentes (config vía xcconfig/Info.plist, seams tras protocolos, composition root, fake en test target, stubs HTTP) y análisis de integración.
- **Key Findings**:
  - supabase-swift v2 (SPM `https://github.com/supabase/supabase-swift.git`, producto `Supabase`) expone `SupabaseClient`, y los namespaces `auth`, `storage` y `postgrest`/`rpc`; el SDK persiste la sesión en almacenamiento local (Keychain) por defecto.
  - El repositorio ya tiene un patrón probado de configuración por xcconfig → Info.plist → `Bundle.main.object(forInfoDictionaryKey:)` (FishialCredentials), reutilizable tal cual para URL/anon key de Supabase.
  - El SDK expone tipos de usuario/sesión (`Supabase.Session`, `Supabase.User`) que no deben filtrar fuera del boundary base; se mapean a modelos comunes propios (`Codable`/`Sendable`).
  - Swift 6 en modo estricto puede rechazar `SupabaseClient` por no ser `Sendable`; conviene aislar el cliente en implementaciones `actor` para cumplir los protocolos `Sendable` sin depender de anotaciones del SDK.
  - Las funciones Postgres `RETURNS void` responden con éxito y cuerpo vacío; PostgREST Swift ofrece un overload de `execute()` que devuelve `PostgrestResponse<Void>`, mientras que el overload genérico intenta decodificar `T` y falla si no hay JSON.

## Research Log

### 1. Supabase Swift SDK: verificación de API y compatibilidad
- **Context**: El brief fija "Supabase Swift SDK" como única librería externa nueva (tech.md ya lo declaraba como dependencia outbound planificada). Se verificó la superficie de API y el modo de integración.
- **Sources Consulted**: https://supabase.com/docs/reference/swift/introduction, /swift/installing, /swift/initializing; https://github.com/supabase/supabase-swift (v2.x, MIT).
- **Findings**:
  - Paquete SPM `supabase-swift` desde `2.0.0`; expone los productos `Supabase` (cliente completo), `Auth`, `Storage`, `Postgrest`, `Realtime`, `Functions`.
  - Inicialización: `SupabaseClient(supabaseURL: URL, supabaseKey: String, options: SupabaseClientOptions?)`.
  - Auth: `supabase.auth.signUp`, `signIn`, `signOut`, `session`, `user`, `stateChanges`.
  - Storage: `supabase.storage.from(bucket).upload(path:_:options:)`, `.download(path:)`.
  - Database: `supabase.postgrest` (query builder `from/select/eq/limit/execute`) y `supabase.rpc(name, params:)`.
  - La sesión se restaura automáticamente desde el almacenamiento local por defecto al construir el cliente.
- **Implications**: Diseñamos la capa base sobre esos namespaces; el contrato de la capa base NO expone tipos del SDK (los seams emiten solo tipos comunes propios).

### 2. Patrón de configuración existente (xcconfig → Info.plist)
- **Context**: El brief exige URL y anon key desde xcconfig gitignored, sin hardcodear.
- **Sources Consulted**: Código existente: `AppCompositionSupport.swift` (`FishialCredentials(bundle:)`), `App/Resources/Debug.xcconfig.example`, `App/Resources/Info.plist`, `.gitignore`.
- **Findings**:
  - Patrón probado: variable en xcconfig (`FISHIAL_CLIENT_ID`), referencia `$(...)` en Info.plist, lectura con `Bundle.main.object(forInfoDictionaryKey:)` en un struct dedicado.
  - `.gitignore` ya ignora `App/Resources/*.xcconfig` y conserva los `.example` versionados.
- **Implications**: `SupabaseClientConfiguration(bundle:)` replica el patrón con las claves `SupabaseProjectURL`/`SupabaseAnonKey` y tolera valores vacíos (devuelve `nil`) para que la app arranque sin infra (el brief indica que aún no existe infra a la que apuntar).

### 3. Swift 6 y concurrencia (Sendable del cliente)
- **Context**: Swift 6 estricto en el proyecto; `SupabaseClient` es una clase y su conformidad `Sendable` puede no estar garantizada.
- **Sources Consulted**: Especificación Swift 6 (Sendable/actors); issues conocidos del ecosistema supabase-swift sobre `Sendable`.
- **Findings**:
  - Envolver el cliente en implementaciones `actor` aísla su estado de forma segura y permite que los servicios conformen protocolos `Sendable` sin `@unchecked Sendable`.
  - La creación del cliente ocurre en el composition root (MainActor); los actores se crean ahí y reciben la instancia compartida.
- **Implications**: `SupabaseAuthService`, `SupabaseStorageService` y `SupabaseDatabaseService` se diseñan como `actor`. El task de integración del SDK debe verificar la compatibilidad `Sendable` del SDK y confirmar el patrón elegido.

### 4. Diseño del seam de base de datos (`SupabaseDatabaseAccess`)
- **Context**: La base no conoce el esquema (lo definen spot-discovery/account-personal), pero debe exponer acceso a la BD sin filtrar tipos del SDK ni duplicar la capa de red.
- **Sources Consulted**: Brief (seam `SupabaseDatabaseAccess`, DDL fuera de scope); API de PostgREST del SDK.
- **Findings**:
  - Un seam genérico y agnóstico al esquema basta: lectura (`select` con columnas, filtros y límite) e invocación de funciones remotas (`rpc`, necesario para que spot-discovery use PostGIS "spots cerca de mí").
  - Tipos de valor propios (filtros, argumentos JSON tipados) mantienen el contrato cerrado sin filtrar `PostgrestQueryBuilder` ni `AnyJSON`.
- **Implications**: El seam queda acotado a `select<M>` y `rpc<M>` con el requisito de que los consumidores tipen sus queries sobre estos; el diseño evita una abstracción de query builder completa (simplificación).

### 5. Build vs. Adopt para testear sin red
- **Context**: Los flujos de la capa base deben verificarse sin red real (Req 7).
- **Sources Consulted**: Código existente: `MockURLProtocol.swift`, `HTTPStub.swift`, `FishialClientTests.swift`.
- **Findings**: El repositorio ya dispone del patrón de stub HTTP (`MockURLProtocol`+`URLProtocol`) para testear clientes sin contactar la red.
- **Implications**: Los tests de los servicios usarán `URLProtocol` personalizado inyectado vía `SupabaseClientOptions.global.session` para stubbear los endpoints de auth/storage/PostgREST. Para los tests de features aguas abajo se añade un `SupabaseBaseFake`.

### 6. Extensión del seam para RPC sin cuerpo
- **Context**: Las specs consumidoras definieron funciones Postgres mutaciones cuyo retorno es `void`. PostgREST representa esa respuesta con un cuerpo vacío, no con un objeto JSON artificially válido.
- **Sources Consulted**: Código local de supabase-swift 2.55.2 (`Sources/PostgREST/PostgrestBuilder.swift` y `Tests/PostgRESTTests/PostgrestRpcBuilderTests.swift`) y fuente oficial de `PostgrestBuilder` en GitHub.
- **Findings**:
  - `PostgrestBuilder.execute(options:) async throws -> PostgrestResponse<Void>` ignora deliberadamente el body y representa el éxito con `Void`.
  - El overload genérico `execute<T: Decodable>()` siempre decodifica el body; usarlo para una RPC void convierte un HTTP 2xx válido en un error de decodificación.
  - El seam actual `rpc<T>` cubre correctamente funciones que devuelven JSON, pero no expresa la diferencia entre “respuesta JSON” y “mutación sin resultado”.
- **Implications**: La capa base mantiene `rpc<T>` y añade una operación void explícita al protocolo, al actor real, al fake compartido y a los dobles de tests. La capa no interpreta nombres ni esquemas de RPC; la elección entre ambas operaciones corresponde al consumidor.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| SDK oficial supabase-swift v2 | Cliente completo de Supabase (adoptar) | Soportado oficialmente, cubre auth/storage/db, restaura sesión | Dependencia externa nueva; compatibilidad Sendable | Tech.md ya decidió adoptar el SDK |
| Overload oficial `execute() -> PostgrestResponse<Void>` para RPC sin cuerpo | Adoptar la primitiva del SDK tras un seam void explícito | Representa correctamente HTTP 2xx sin decodificar body; no requiere DTO sentinel | Amplía protocolo, fake y conformance tests | La base mantiene `rpc<T>` para JSON y añade `rpcVoid` para mutaciones |
| Cliente REST propio sobre URLSession | Construir auth/storage/db a mano | Sin dependencia externa | Duplica el SDK, riesgo de bugs de seguridad/refresh, mantenimiento propio | Descartado |
| Aislar el SDK tras protocolos por feature | Cada feature crea su propio wrapper | — | Duplica auth/storage y viola el "único seam de red" del roadmap | Descartado en el brief/roadmap |
| Servicios como structs con `@unchecked Sendable` | Envolver el cliente con anotaciones | Implementación menos verbosa | Riesgo de data races si el SDK cambia; Swift 6 estricto lo penaliza | Se prefiere `actor` |

## Design Decisions

### Decision: Protocolos base nombrados del brief y una sola instancia compartida
- **Context**: El brief fija los seams `SupabaseAuthProviding`, `SupabaseStoring`, `SupabaseDatabaseAccess` y exige una instancia compartida creada en el composition root.
- **Alternatives Considered**:
  1. Un único protocolo `SupabaseProviding` — mezcla auth/storage/db en un contrato grueso.
  2. Tres protocolos segregados por responsabilidad.
- **Selected Approach**: Tres protocolos segregados agrupados en un `SupabaseStack` (auth/storage/database no opcionales dentro del stack, el stack opcional en el composition root).
- **Rationale**: Segregación de interfaces; los consumidores inyectan solo el seam que necesitan; el stack representa el "cliente compartido" sin exponer el `SupabaseClient` interno.
- **Trade-offs**: Un nivel de indirección mayor; aceptable porque es la frontera base que consumen dos specs.
- **Follow-up**: Verificar en la task de integración que `SupabaseStack` y los actores compilan en Swift 6 estricto.

### Decision: Configuración failable y degradación sin infra
- **Context**: Req 2.1–2.4; el brief indica que aún no hay infra de Supabase a la que apuntar; con xcconfig vacío la app debe arrancar igual.
- **Alternatives Considered**:
  1. No arrancar la app sin configuración — inaceptable (no hay infra aún).
  2. `SupabaseClientConfiguration(bundle:)` opcional + stack opcional con log del motivo.
- **Selected Approach**: Lectura opcional de config; si falta o es inválida, el composition root no construye el stack, registra un error claro con `Logger` y la app continúa con `supabase == nil`.
- **Rationale**: Degradación elegante y observable (Req 2.2) sin bloquear el arranque; downstream specs resolverán su comportamiento cuando el stack sea nil.
- **Trade-offs**: Las features consumidoras deben contemplar el stack nil en fases tempranas.
- **Follow-up**: Un test de composición verifica que con config vacía la app construye el resto de servicios y el stack es nil.

### Decision: Servicios auth/storage/db como `actor`
- **Context**: Swift 6 estricto; `SupabaseClient` compartido entre seams.
- **Selected Approach**: Implementaciones `actor` que mantienen el `SupabaseClient` compartido e implementan los protocolos `Sendable`.
- **Rationale**: Concurrencia segura sin `@unchecked Sendable`; las APIs del SDK ya son async y encajan con actores.
- **Trade-offs**: Los actores serializan el acceso al cliente; irrelevante para un cliente compartido rápido.
- **Follow-up**: Task de integración verifica que los métodos del SDK alcanzados desde un actor no bloquean (las APIs son async).

### Decision: Seam de base de datos genérico (select + rpc) con tipos de valor propios
- **Context**: La base no conoce el esquema; spot-discovery necesitará PostGIS (rpc "spots cerca de mí") y reads; account-personal necesita reads/escrituras de favoritos/perfil.
- **Alternatives Considered**:
  1. Exponer el query builder PostgREST tal cual — filtra tipos del SDK, rompe el boundary.
  2. No exponer seam de BD en esta spec — el roadmap lo exige como seam base.
  3. Consultas tipadas por feature — acopla la base a esquemas futuros.
- **Selected Approach**: `select<T>` (columnas + filtros + límite) y `rpc<T>` (función + argumentos JSON tipados); tipos de valor propios (`SupabaseFilter`, `SupabaseOperator`, `SupabaseJSONValue`, `SupabaseRPCArguments`).
- **Rationale**: Agnóstico al esquema, cerrado frente al SDK, suficiente para los consumidores conocidos, implementable y testable ahora.
- **Trade-offs**: Los consumidores construyen sus queries tipadas sobre este seam; si un consumidor necesitara combinadores PostgREST avanzados, ampliar el seam será un cambio de contrato (revalidación diseñada).
- **Follow-up**: Documentado como Revalidation Trigger.

### Decision: API explícita para RPC con y sin resultado
- **Context**: El contrato genérico `rpc<T>` solo puede representar funciones que devuelven un body JSON decodificable; las mutaciones `RETURNS void` no tienen tal body.
- **Alternatives Considered**:
  1. Cambiar el DDL consumidor para devolver un objeto JSON — rechazada: altera contratos de dominio y RLS para acomodar una limitación del cliente.
  2. Enviar un DTO vacío o `{}` desde cada consumidor — rechazada: no funciona con un body realmente vacío y duplica una convención falsa.
  3. Sobrescribir `rpc<T>` para tratar `Data()` como `EmptyResponse` — rechazada: mezcla semántica de errores de red/HTTP con un caso de éxito específico y debilita el tipado del retorno.
  4. Exponer `rpcVoid` y usar el overload oficial `execute() -> PostgrestResponse<Void>` — seleccionada.
- **Selected Approach**: Mantener `rpc<T>` para RPC con JSON y añadir `rpcVoid(_:arguments:)` al seam para operaciones cuyo único resultado observable es el éxito HTTP.
- **Rationale**: Hace explícita la diferencia de contrato, reutiliza la abstracción oficial sin filtrar el SDK y mantiene la responsabilidad de elegir la operación en cada consumidor.
- **Trade-offs**: Amplía todos los conformers del protocolo y obliga a revalidar `account-personal` y `spot-discovery`; a cambio elimina DTO sentinel y evita tratar un body vacío como error.
- **Follow-up**: Añadir stubs para 204/body vacío, codificación de argumentos y error HTTP; migrar las cuatro mutaciones consumidoras y ejecutar sus suites antes de rehabilitar la regresión de `account-personal`.

## Risks & Mitigations
- **SupabaseClient no es `Sendable` en Swift 6 estricto** — Mitigación: implementaciones `actor` aislan el cliente; verificar en la task de integración del SDK.
- **Deriva de la API del SDK v2 durante implementación** (upload/download, rpc params, opciones de storage) — Mitigación: pin de versión en SPM, task de integración con verificación contra docs oficiales antes de implementar los servicios.
- **El stub de los endpoints de auth/storage/PostgREST puede requerir detalles de firma (storage upload)** — Mitigación: stubbear respuestas JSON de éxito/error a nivel HTTP (patrón `MockURLProtocol`), no implementar firma; los servicios no dependen del contenido interno siempre que el contrato JSON se respete.
- **xcconfig vacío rompiendo el arranque** — Mitigación: config opcional y stack opcional con log; tests de composición garantizan arranque sin config ni URL inválida.
- **La capa base sin consumidores reales hasta que aterricen spot-discovery/account-personal** — Mitigación: el seam queda validado con la suite de tests de la propia base (config, servicios con stub, fake, composición) para no fijar contratos sin evidencia.
- **RPC void puede confundirse con una respuesta JSON mal formada** — Mitigación: una API `rpcVoid` separada usa el overload oficial que descarta el body; un status 2xx cualquiera es éxito y cualquier status no 2xx conserva el mapeo a `rpcFailed`.
- **Ampliar un protocolo base rompe conformers y fixtures aguas abajo** — Mitigación: actualizar simultáneamente `SupabaseBaseFake` y todos los dobles de tests, ejecutar sus conformance tests y revalidar `account-personal` y `spot-discovery` antes de cerrar la dependencia.

## References
- [Supabase Swift: Introduction](https://supabase.com/docs/reference/swift/introduction) — namespaces del SDK v2.
- [Supabase Swift: Installing](https://supabase.com/docs/reference/swift/installing) — integración SPM (`supabase-swift` desde 2.0.0).
- [Supabase Swift: Initializing](https://supabase.com/docs/reference/swift/initializing) — `SupabaseClient` y `SupabaseClientOptions`.
- [supabase-swift (GitHub)](https://github.com/supabase/supabase-swift) — repositorio oficial v2.
- [PostgrestBuilder.swift (supabase-swift)](https://github.com/supabase/supabase-swift/blob/main/Sources/PostgREST/PostgrestBuilder.swift) — overload de ejecución con y sin decodificación para RPC.
- Código local: `FishialCredentials` (patrón de configuración), `MockURLProtocol`/`HTTPStub` (patrón de test sin red), `AppRootServices`/`AppComposition` (composition root).