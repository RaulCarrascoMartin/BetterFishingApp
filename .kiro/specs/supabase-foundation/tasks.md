# Implementation Plan: supabase-foundation

## 1. Foundation: integración del SDK, configuración y modelos comunes
- [x] 1.1 Integrar el SDK de Supabase como dependencia de paquete SPM
  - Añadir `supabase-swift` (v2.x, producto `Supabase`) como dependencia de paquete en `BetterFishing.xcodeproj` (project.pbxproj) y vincularla al target de la app; el test target también la referencia para construir opciones de cliente en los tests de integración.
  - Verificar en Swift 6 estricto (`xcodebuild build` y `test`) la compatibilidad `Sendable` del `SupabaseClient` con el patrón de actores del diseño (aislar el cliente dentro de actores); registrar el hallazgo en las notas de implementación.
  - Seguir el patrón existente del proyecto para registrar ficheros nuevos en el target (cada fichero que añadan las tareas siguientes se registra igual).
  - Observable: `xcodebuild build` compila con la dependencia resuelta y un test de humo que referencia el producto `Supabase` compila.
  - _Requirements: 1.3_

- [x] 1.2 Configuración centralizada de URL y anon key
  - Añadir `SUPABASE_PROJECT_URL` y `SUPABASE_ANON_KEY` a `Debug.xcconfig.example` y `Release.xcconfig.example` (vacías) y las claves `SupabaseProjectURL`/`SupabaseAnonKey` (mapeadas a `$()` ) en `Info.plist`, respetando el patrón de `FishialCredentials`.
  - Implementar `SupabaseClientConfiguration` con `init?(bundle:)` que devuelve `nil` si la URL o la anon key faltan, están vacías o la URL no es parseable.
  - Definir `SupabaseBaseError` (configurationMissing, invalidProjectURL, signUpFailed/signInFailed/signOutFailed, sessionUnavailable, uploadFailed/downloadFailed, queryFailed/rpcFailed) como `Error`/`Sendable`/`LocalizedError`.
  - Observable: tests en verde que verifican config válida, clave ausente, clave vacía y URL malformada → `nil`; las plantillas `.example` versionadas quedan sin valores.
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 1.3 Modelos comunes de sesión y usuario
  - Definir `SupabaseUser` (id UUID, email opcional, createdAt) y `SupabaseSession` (accessToken, refreshToken, expiresAt, user) como `Codable`, `Equatable`, `Sendable`.
  - Observable: tests de round-trip Codable de sesión y usuario completos en verde.
  - _Requirements: 6.1_

## 2. Core: seam de auth
- [x] 2.1 (P) Declarar el protocolo de auth y los eventos de sesión
  - Declarar `SupabaseAuthProviding` (`Sendable`) con signUp/signIn/signOut/currentUser/currentSession y `stateChanges()`, y `SupabaseAuthEvent` (signedIn, sessionRestored, signedOut), según el contrato del diseño.
  - Garantizar que el protocolo no referencia tipos del SDK de Supabase y que cualquier tipo `Sendable` puede conformarlo (sustituible por fake).
  - Observable: el protocolo y el evento compilan en el target de la app y un double mínimo del test target conforma el protocolo sin importar el SDK.
  - _Requirements: 1.2, 3.7, 7.4_
  - _Boundary: Services/Supabase/SupabaseAuthProviding_

- [x] 2.2 Implementar el servicio de auth sobre Supabase
  - Implementar `SupabaseAuthService` como actor que mantiene el `SupabaseClient` compartido y cumple `SupabaseAuthProviding` sobre `supabase.auth`.
  - Mapear los tipos de sesión/usuario del SDK a `SupabaseSession`/`SupabaseUser` dentro del servicio (sin filtrarlos fuera), traducir fallos a `SupabaseBaseError` tipado y proyectar los cambios de estado del SDK a `SupabaseAuthEvent` (incluida la restauración de sesión del almacenamiento local).
  - Observable: suite de tests con stubs HTTP (`MockURLProtocol`) en verde: signUp y signIn devuelven `SupabaseSession`, credenciales inválidas (401) → `signInFailed`, signOut termina la sesión, currentSession/currentUser consultan el estado, y `stateChanges()` emite signedIn/sessionRestored/signedOut.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 6.2_
  - _Boundary: Services/Supabase/SupabaseAuthService_

## 3. Core: seam de storage
- [x] 3.1 (P) Declarar el protocolo de storage y sus opciones
  - Declarar `SupabaseStoring` (`Sendable`) con upload(bucket:path:data:options:) y download(bucket:path:), más `SupabaseUploadOptions` (contentType, upsert), sin tipos del SDK en el contrato.
  - Observable: el protocolo compila en el target de la app y un double mínimo del test target conforma el protocolo sin importar el SDK.
  - _Requirements: 1.2, 4.4, 7.4_
  - _Boundary: Services/Supabase/SupabaseStoring_

- [x] 3.2 Implementar el servicio de storage sobre Supabase
  - Implementar `SupabaseStorageService` como actor que cumple `SupabaseStoring` sobre `supabase.storage.from(bucket)`, devolviendo la ruta en upload y los `Data` en download, y traduciendo fallos a `SupabaseBaseError` tipado.
  - Observable: suite de tests con stubs HTTP en verde: upload devuelve la ruta del objeto, download devuelve los `Data`, y un 404/error en descarga → `downloadFailed`.
  - _Requirements: 4.1, 4.2, 4.3_
  - _Boundary: Services/Supabase/SupabaseStorageService_

## 4. Core: seam de base de datos
- [x] 4.1 (P) Declarar el protocolo de base de datos y sus tipos de valor
  - Declarar `SupabaseDatabaseAccess` (`Sendable`) con select(columns:from:filters:limit:) y rpc(function:arguments:), más los tipos de valor `SupabaseFilter`, `SupabaseFilterOperator`, `SupabaseJSONValue` y `SupabaseRPCArguments` según el contrato del diseño.
  - Garantizar que el seam es agnóstico al esquema (no menciona tablas de ninguna feature) y no filtra tipos del query builder del SDK.
  - Observable: el protocolo y los tipos compilan en el target de la app y un double mínimo conforma el protocolo sin importar el SDK.
  - _Requirements: 1.2, 5.2, 5.3, 7.4_
  - _Boundary: Services/Supabase/SupabaseDatabaseAccess_

- [ ] 4.2 Implementar el servicio de base de datos sobre Supabase
  - Implementar `SupabaseDatabaseService` como actor que cumple `SupabaseDatabaseAccess` sobre `supabase.postgrest`/`rpc`: aplica columnas, filtros (eq/neq/gt/gte/lt/lte) y límite en select, y codifica `SupabaseRPCArguments` a JSON para rpc, decodificando a tipos genéricos.
  - Traducir fallos a `SupabaseBaseError` tipado (queryFailed/rpcFailed).
  - Observable: suite de tests con stubs HTTP en verde: select devuelve `[T]` decodificado con filtro y límite aplicados, rpc devuelve `T`, un error 4xx/5xx → `queryFailed`/`rpcFailed`, y la codificación JSON de `SupabaseRPCArguments` queda cubierta por tests unitarios.
  - _Requirements: 5.1, 5.2, 5.3_
  - _Boundary: Services/Supabase/SupabaseDatabaseService_

## 5. Integration: provider, stack y composition root
- [ ] 5.1 Construir el provider y el stack de Supabase
  - _Depends: 2.2, 3.2, 4.2_
  - Implementar `SupabaseClientProvider` (makeClient/makeStack) que crea UNA instancia del `SupabaseClient` desde la configuración y la reutiliza en los tres actores, agrupados en `SupabaseStack` (auth/storage/database).
  - Permitir inyectar opciones de cliente (URLSession personalizada) para los tests de stubs sin cambiar la configuración.
  - Observable: tests del provider en verde: config válida → stack con los tres seams no nil, y URL inválida → `SupabaseBaseError.invalidProjectURL`.
  - _Requirements: 1.1, 1.3, 2.1_
  - _Boundary: Services/Supabase/SupabaseClientProvider_

- [ ] 5.2 Conectar la capa base al composition root
  - _Depends: 5.1_
  - Añadir `supabase: SupabaseStack?` a `AppRootServices` y construirlo en `makeRootServices` desde la configuración del Bundle, permitiendo inyectar config/opciones de test; si no hay config o falla la construcción, registrar con `Logger` el motivo y mantener `supabase == nil` sin romper el arranque.
  - Garantizar que las features consumidoras solo reciben los protocolos del stack y que la capa base no conoce ninguna feature.
  - Observable: tests de composición en verde: con config vacía el resto de servicios se construyen y `supabase == nil`; con config válida inyectada el stack es no nil y expone los tres protocolos.
  - _Requirements: 1.1, 1.2, 1.4, 2.2, 6.3_
  - _Boundary: AppCompositionSupport, AppRootServices_

## 6. Validation: fake y verificación de la capa base
- [ ] 6.1 Fake de la capa base para el test target
  - _Depends: 2.1, 3.1, 4.1_
  - Implementar `SupabaseBaseFake` en el test target que conforma los tres protocolos con éxito/fallo programables y registra las llamadas (credenciales, bucket/rutas, filtros) para aserciones.
  - Observable: tests del fake en verde que verifican flujos de auth y storage con éxito y con fallo sin contactar la red (ya listos para que las features aguas abajo los consuman).
  - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - _Boundary: BetterFishingTests/SupabaseBaseFake_

- [ ] 6.2 Verificación E2E de la capa base
  - _Depends: 5.2, 6.1_
  - Añadir una prueba de integración que construye la composición con configuración vacía (la app construye el resto de servicios, `supabase == nil`) y un flujo completo de sesión con stubs HTTP: signIn → currentSession consultable → `stateChanges()` emite signedIn → signOut → signedOut.
  - Confirmar que la suite completa y el build pasan en Swift 6 estricto sin advertencias de concurrencia.
  - Observable: `xcodebuild test -scheme BetterFishing` en verde con la que la suite existente (línea base) sigue pasando.
  - _Requirements: 2.2, 3.2, 3.3, 3.4, 3.5, 3.6_
  - _Boundary: BetterFishingTests, AppCompositionSupport_

## Implementation Notes
- La tarea 1.1 debe resolver la versión v2.x de `supabase-swift` y confirmar el patrón de actores frente a `Sendable`; si el SDK ya conforma `Sendable`, se mantienen igualmente los actores por el aislamiento del cliente compartido y la consistencia del diseño.
- Cada fichero Swift nuevo (1.2–6.2) debe registrarse en el target correspondiente en `project.pbxproj` siguiendo el patrón existente (fileRef + buildFile + Sources), igual que hizo `catch-log`.
- `stateChanges()` se expone como `AsyncStream<SupabaseAuthEvent>`; en el actor la proyección del stream del SDK debe evitar capturar contexto inseguro en Swift 6.
- La restauración de sesión (Req 3.5) la entrega el SDK con su almacenamiento por defecto al construir el cliente; el mapa `initialSession` → `.sessionRestored` en `stateChanges()` es la evidencia observable (tarea 6.2).
- Con xcconfig vacío (no hay infra de Supabase todavía) la capa base debe degradar a `supabase == nil` con log; ninguna feature incorporada consume aún los seams, por lo que el resto de la app no se ve afectado (verificado en 5.2 y 6.2).
- Los tests de servicios usan `MockURLProtocol`/`HTTPStub` (patrón ya existente en la repo) inyectando la `URLSession` vía `SupabaseClientOptions.global.session`; no se construye ni se firma ningún request Supabase a mano.
- La integración SPM de la dependencia `supabase-swift` (resuelta v2.55.2, producto `Supabase`, fromVersion 2.0.0) se registra con una nueva PBXFrameworksBuildPhase (F16) en el target de la app y en la fase F0B del test target; verificado en Swift 6 estricto: `SupabaseClient` declara `Sendable` en el SDK (`public final class SupabaseClient: Sendable`), por lo que el patrón de actores del diseño se mantiene por aislamiento del cliente compartido y consistencia, no por necesidad de conformidad.
- 1.2: `SupabaseClientConfiguration.init?(bundle:)` exige URL con esquema http/https y host no vacío (Foundation `URL(string:)` es laxo y acepta "not a url" como URL relativa), y recorta espacios en blanco en ambos valores; los tests de config leen un Bundle temporal con Info.plist generado, sin red ni credenciales reales (5 tests, suite 161 en verde).
- 1.3: modelos con Codable sintetizado (claves = nombres de propiedad) y fechas por estrategia por defecto `deferredToDate` en encoder/decoder; `SupabaseModelsTests` cubre round-trip de usuario (email presente y ausente) y sesión completa más claves JSON e igualdad/identidad (5 tests; suite 166 en verde).
- 2.1: `SupabaseAuthProviding` y `SupabaseAuthEvent` declarados sin importar el SDK; `SupabaseAuthFakeConformanceTests` define un `AuthTestDouble` solo con Foundation que conforma el protocolo y consume el `AsyncStream` (3 tests; suite 169 en verde).
- 2.2: endpoints exactos de los stubs (base `https://project-ref.supabase.co`) — signUp `/auth/v1/signup`, signIn `/auth/v1/token?grant_type=password`, signOut POST `/auth/v1/logout?scope=global` — y el shape real del stream del SDK v2.55 es `AsyncStream<(event: AuthChangeEvent, session: Session?)>` (con `@_spi(Experimental) import Supabase`).
- RED 2.2: evidencia reproducida moviendo `app/Services/Supabase/SupabaseAuthService.swift` fuera de los sources del target: `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project BetterFishing.xcodeproj -scheme BetterFishing -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -only-testing:BetterFishingTests/SupabaseAuthServiceTests` → `error: Build input file cannot be found: '.../App/Services/Supabase/SupabaseAuthService.swift'. Did you forget to declare this file as an output of a script phase or custom build rule which produces it? ... ** TEST FAILED ** (3 failures)`; fichero restaurado y suite 176 en verde tras ello.
- 2.2: `currentSession()` se declara `throws` por el protocolo aprobado, pero devuelve `nil` cuando no hay sesión (`.sessionUnavailable` queda sin usar en la superficie); `signUp` sin sesión (confirmación de email pendiente → `AuthResponse.user`) traduce a `.signUpFailed` porque la Req 3.1 exige sesión devuelta.
- 3.1: `SupabaseStoring` + `SupabaseUploadOptions` declarados solo con Foundation (sin tipos del SDK) en `Services/Supabase/SupabaseStoring.swift`; `SupabaseStoringFakeConformanceTests` define `StorageTestDouble` con caja `Sendable` que registra uploads y devuelve ruta fija o error programable (5 tests; suite 181 en verde tras RED `Cannot find type 'SupabaseStoring' in scope`).
- 3.2: endpoints exactos de los stubs (base `https://project-ref.supabase.co`, sin `useNewHostname`) — upload POST y download GET `/storage/v1/object/{bucket}/{path}`; el SDK v2.55 devuelve `FileUploadResponse` y el servicio devuelve `fullPath` (el `Key`/ruta almacenada, p. ej. `catches/2026/season/catch-1.jpg`).
- RED 3.2: evidencia reproducida moviendo `App/Services/Supabase/SupabaseStorageService.swift` fuera de los sources del target (`Build input file cannot be found: '.../SupabaseStorageService.swift' ... ** TEST FAILED **`); fichero restaurado y suite 185 en verde tras ello (reproducido por el reviewer en ronda de revisión de 3.2).
- 4.1: `SupabaseDatabaseAccess` + `SupabaseFilter`/`SupabaseFilterOperator`/`SupabaseJSONValue`/`SupabaseRPCArguments` declarados solo con Foundation (sin tipos del SDK ni tablas de features) en `Services/Supabase/SupabaseDatabaseAccess.swift`; `SupabaseDatabaseFakeConformanceTests` define `DatabaseTestDouble` (`any SupabaseDatabaseAccess`) que registra select (filtros/límite) y rpc (función/argumentos) con caja `Sendable` (5 tests; suite 190 en verde tras RED `Cannot find 'SupabaseDatabaseAccess' in scope`).