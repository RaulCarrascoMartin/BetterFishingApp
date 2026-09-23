# Research & Design Decisions: spot-discovery

## Summary
- **Feature**: spot-discovery
- **Discovery Scope**: Extensión (feature nueva en una app existente) con integración doble: UI de mapa nueva (MapKit) y provisioning de backend nuevo (PostGIS en Supabase) sobre los seams de la capa base «supabase-foundation». Se aplicó discovery ligero orientado a integración: análisis de seams existentes (SpotRepository a definir, seams de fundación consumidos, localización compartida), verificación rápida de las capacidades de MapKit (iOS 17 SwiftUI) y del patrón RPC/RLS de Supabase para geometría y favoritos.
- **Key Findings**:
  - La capa base expone `SupabaseDatabaseAccess` con solo `select<T>` y `rpc<T>`: las mutaciones de favoritos y las consultas de distancia PostGIS deben modelarse como funciones RPC del propio backend de esta feature (no se amplía el seam base — sería un cambio de contrato y trigger de revalidación).
  - La lectura de spots por región y el mapeo JSON a modelos es más robusto con columnas `longitude`/`latitude` numéricas junto a la geometría PostGIS (`geom geometry(Point,4326)`), reservando el PostGIS para las consultas de distancia vía RPC.
  - La app ya dispone de `LocationCoordinate2D` (modelo compartido), `DeviceLocationProviding`/`DeviceLocationProvider` (Core) y de `NSLocationWhenInUseUsageDescription` en Info.plist: no hace falta tolerar permisos nuevos ni romper el seam de localización de catch-log.
  - MapKit en iOS 17 expone `Map` de SwiftUI con `MapContentBuilder` (anotaciones `Annotation`/`Marker`); conviene representar la región visible con un valor propio `Sendable` (`SpotRegion`) en vez de `MKCoordinateRegion` (no `Sendable`) para cruzar la frontera de actores/Swift 6.
  - El test target de la base ya aporta `SupabaseBaseFake` para los tres seams y la repo ya tiene doubles de localización (`DeviceLocationProviderDouble`, `CompositionTestLocationProvider`) que se reutilizan.

## Research Log

### 1. Seam de base de datos de «supabase-foundation» y límites para spots
- **Context**: La feature debe leer spots, consultar distancia y guardar favoritos; el brief fija consumir la capa base y no tocar sus seams.
- **Sources Consulted**: `design.md` y `tasks.md` de supabase-foundation (seam `SupabaseDatabaseAccess`: `select<T>(columns:from:filters:limit:)` y `rpc<T>(function:arguments:)`; `SupabaseFilter`/`SupabaseFilterOperator`/`SupabaseJSONValue`/`SupabaseRPCArguments`; `SupabaseAuthProviding` con `currentUser()` y `stateChanges()`; `SupabaseBaseFake` en el test target).
- **Findings**:
  - El seam de BD es de solo lectura (`select`) más invocación remota (`rpc`); no expone insert/update/delete.
  - Ampliar el seam base es un «Revalidation Trigger» explícito de la base: no debe hacerse desde esta spec.
  - La autenticación se consulta con `currentUser() async -> SupabaseUser?`; `SupabaseUser` es el modelo común de la base (permitido consumir), los tipos del SDK no deben filtrarse.
- **Implications**: Las funciones RPC de spots/favoritos y su RLS viven en el provisioning de esta feature (`db/spot-discovery`), no en la base.

### 2. PostGIS + PostgREST para «spots cerca de mí»
- **Context**: Se requiere distancia y ordenación geográfica; la semilla es curada (v1, sin subida).
- **Sources Consulted**: Documentación de PostGIS (`geography`, `ST_DWithin`, `ST_Distance`), estructura de datos fija para selección por PostgREST estudiada en el diseño de la base.
- **Findings**:
  - La tabla `spots` guarda `geom geometry(Point,4326)` para consultas PostGIS y, en paralelo, `longitude`/`latitude` numéricas para `select` simple y mapeo plano a JSON (PostgREST devuelve objetos planos).
  - Un RPC `nearby_spots(lat, lng, radius_km)` que devuelve filas con `distance_m` y ordena por distancia abstrae el PostGIS del cliente.
  - Índice GiST sobre `geom` habilita `ST_DWithin` eficiente.
- **Implications**: Las anotaciones del mapa se sirven con `select` + filtros de caja delimitadora por la región visible (curated seed pequeño); la distancia solo se calcula en el flujo «cerca de mí» vía RPC.

### 3. MapKit (iOS 17 SwiftUI) y representación de la región visible
- **Context**: El brief fija MapKit + CoreLocation e iOS 17+.
- **Sources Consulted**: Documentación de Apple SwiftUI `Map` (`MapContentBuilder`, `Annotation`, `Marker`, `initialPosition`/`cameraPosition`); convenciones de Swift 6 del proyecto (protocolos `Sendable`, actores).
- **Findings**:
  - iOS 17 permite anotaciones declarativas con `Map` + `MapContentBuilder`; selección manejada por `TapGesture` sobre `Annotation` o `Marker`.
  - `MKCoordinateRegion` no es `Sendable`; al cruzar actores/ViewModels conviene un valor propio `SpotRegion` (`Sendable`) con la conversión a/desde `MKCoordinateRegion` localizada en el ViewModel (import de MapKit solo en la capa de vista).
- **Implications**: `SpotMapViewModel` trabaja con `SpotRegion`/`LocationCoordinate2D` puros; la conversión MapKit queda en el borde de la vista.

### 4. Favoritos con cuenta sin UI de login
- **Context**: Favoritos requieren cuenta (auth de la base); el flujo de login es de «account-personal» (fuera de boundary).
- **Sources Consulted**: Summary breve y design de supabase-foundation (el seam `SupabaseAuthProviding` emite `SupabaseUser`/`SupabaseSession`, no tipos del SDK); boundary de «account-personal».
- **Findings**:
  - El gate de sesión se resuelve con `currentUser()` y el estado vivo con `stateChanges()` (`.signedIn`/`.signedOut`).
  - Las mutaciones sobre `spot_favorites` viajan como RPC que resuelve `auth.uid()` en el servidor con RLS, desacoplando el cliente del id.
- **Implications**: `SpotDetailViewModel` bloquea el favorito sin sesión y muestra un aviso de que requiere iniciar sesión, sin navegar al flujo de cuenta (respeto del boundary).

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Ampliar `SupabaseDatabaseAccess` con insert/update/delete | Añadir mutaciones al seam base | Cubriría favoritos con queries directas | Cambia contrato de la base; viola su Revalidation Trigger | Descartado |
| Mutaciones y PostGIS como RPC del backend de spots | Funciones SQL propias (`nearby_spots`, favoritos) + RLS | Mantiene seam base intacto; PostGIS en SQL; RLS en el servidor | La feature debe definir y versionar el SQL | **Elegido** |
| Persistir favoritos/spots en local | Duplicar datos del descubrimiento en el dispositivo | Funcionamiento offline | Rompe «sin persistencia local duplicada» del brief y la consistencia entre dispositivos | Descartado |
| `SpotDiscovery` separado de `SpotRepository` | Dos protocolos (lecturas geo + favoritos) | Segregación más fina | Abstracción especulativa sin segundo consumidor claro | Descartado; un solo seam |

## Design Decisions

### Decision: Un único seam `SpotRepository` (sin `SpotDiscovery`)
- **Context**: El brief propone `SpotRepository` (CRUD/geográfico) como seam; «account-personal» consumirá los favoritos con el mismo repositorio.
- **Alternatives Considered**:
  1. Dos protocolos (`SpotDiscovery` lecturas + `SpotRepository` favoritos) — segregación fina.
  2. Un único protocolo `SpotRepository` con geografía, lecturas y favoritos.
- **Selected Approach**: Un único protocolo `SpotRepository` (`Sendable`) que cubre lista por región, cercanos por distancia, detalle, ids favoritos, spots favoritos y toggle de favorito; implementado por el actor `SupabaseSpotRepository`.
- **Rationale**: Es el seam que programa el brief; un solo contrato es el diseño más pequeño que satisface los requisitos y queda estable para el downstream (cuenta reutiliza favoritos). Separar un `SpotDiscovery` sería abstracción especulativa (síntesis: simplificación).
- **Trade-offs**: El contrato agrupa lecturas geográficas y favoritos; aceptable porque comparten fuente (Supabase/Postgres) y consumidor único.
- **Follow-up**: No añadir un segundo protocolo salvo que «account-personal» demuestre necesidad real.

### Decision: PostGIS y favoritos mediante RPC del propio backend, sin tocar el seam de la base
- **Context**: El seam base expone `select` y `rpc`; las mutaciones de favoritos y la distancia PostGIS necesitan SQL.
- **Alternatives Considered**:
  1. Ampliar `SupabaseDatabaseAccess` con insert/update/delete — cambio de contrato de la base.
  2. RPC propias de spots (`nearby_spots`, `my_favorite_spot_ids`, `my_favorite_spots`, `add_spot_favorite`, `remove_spot_favorite`) con RLS.
- **Selected Approach**: Funciones RPC y esquema propios versionados en `db/spot-discovery/001_spot_discovery_init.sql` (tablas `spots` y `spot_favorites`, índices GiST, RLS, semilla curada) consumidas por `SupabaseSpotRepository` vía `SupabaseDatabaseAccess.rpc`/`select`.
- **Rationale**: La base permanece agnóstica; PostGIS y el control de acceso viven en el servidor; los contratos RPC quedan tipados por esta spec.
- **Trade-offs**: La feature es responsable de su SQL y de su despliegue; acceptable para una spec que define su propio esquema.
- **Follow-up**: El cambio en las firmas/nombres de las RPC o en el esquema es un Revalidation Trigger.

### Decision: Columnas `longitude`/`latitude` + geom PostGIS
- **Context**: PostgREST devuelve filas planas y el seam `select` decodifica a `[T]` genérico; la distancia requiere PostGIS.
- **Alternatives Considered**:
  1. Solo `geom` y funciones PostGIS por columna en `select` — frágil con el decodificador genérico.
  2. Columnas numéricas + geom para distancia.
- **Selected Approach**: `spots` guarda `geom geometry(Point,4326)` y `longitude`/`latitude` numéricas sincronizadas; `Spot` decodifica las planas y deriva `coordinate: LocationCoordinate2D`; el RPC de cercanía añade `distance_m` (mapeada a `distanceMeters`).
- **Rationale**: Mapeo JSON robusto para el seam `select` y PostGIS disponible para distancia vía RPC; la semilla curada garantiza consistencia (misma coordenada en ambos campos).
- **Trade-offs**: Redundancia de coordenadas en la tabla; gestionada por la semilla y los checks del SQL.
- **Follow-up**: Un `check` en el SQL mantiene `geom` coherente con `longitude`/`latitude` (opcional, verificado en la tarea de provisioning).

### Decision: Degradación cuando `supabase == nil` mantiene el resto de la app viva
- **Context**: La base construye el stack solo con credenciales válidas (xcconfig); sin infra, `supabase == nil` y la app arranca.
- **Selected Approach**: `SpotRepository` es opcional en el composition root (`any SpotRepository?`); sin stack no se construye `SupabaseSpotRepository`, la pestaña «Mapa» muestra «no disponible» y el resto de pestañas sigue funcionando.
- **Rationale**: Coherente con la degradación elegida en la base; el shutdown del mapa no puede romper el arranque (Req 2).
- **Trade-offs**: El ViewModel del mapa debe contemplar el repositorio opcional y sus estados.
- **Follow-up**: Test de composición con stack nil y con `SupabaseBaseFake`.

### Decision: Reutilizar localización compartida para «cerca de mí»
- **Context**: El brief exige CoreLocation sin cambiar el seam que ya existe (`DeviceLocationProviding`/`DeviceLocationProvider`).
- **Selected Approach**: `SpotMapViewModel` inyecta `DeviceLocationProviding` (el mismo `DeviceLocationProvider` de Core) para pedir permiso y obtener la ubicación cuando el usuario pulsa «cerca de mí».
- **Rationale**: No se duplica la lógica de permisos/fetch; el seam de Core ya está testeado y es ajeno al registro de capturas se mantiene.
- **Trade-offs**: «cerca de mí» es una acción explícita del usuario (no auto-localización del mapa), decisión de producto que reduce fricción de permisos.
- **Follow-up**: Ninguno; los doubles existentes cubren los tests del ViewModel.

## Risks & Mitigations
- **Cambio del contrato de la base (`SupabaseDatabaseAccess`) durante implementación** — Mitigación: esta spec consume solo `select`/`rpc` fijados en la base; si hiciera falta otra operación se detendría antes de tocar el seam base.
- **Semilla curada desalineada con la geometría (geom vs columnas)** — Mitigación: inserts con una única fuente de coordenadas y `check` de coherencia en el SQL.
- **`MKCoordinateRegion` no `Sendable` en Swift 6** — Mitigación: la capa de vista convierte a/desde `MKCoordinateRegion`; el ViewModel y los protocolos trabajan con `SpotRegion`/`LocationCoordinate2D`.
- **PostgREST y nombres en snake_case (`distance_m`, `spot_id`)** — Mitigación: mapeo explícito con `CodingKeys` en `Spot` y en los rows de las RPC, cubierto por tests de decodificación.
- **Favoritos sin sesión** — Mitigación: gate doble (UI con `currentUser()` y RPC con `auth.uid()`/RLS); el repositorio lanza `authenticationRequired` si `currentUser() == nil`.

## References
- [PostGIS: geography](https://postgis.net/workshops/postgis-intro/geography.html) — `ST_DWithin`/`ST_Distance` sobre `geography`.
- [Supabase: PostgreSQL Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security) — políticas RLS con `auth.uid()`.
- [Apple: Map](https://developer.apple.com/documentation/mapkit/map) — MapKit SwiftUI (iOS 17).
- Specs locales: `supabase-foundation/design.md` y `supabase-foundation/tasks.md` (seams consumidos); `catch-log` (patrones de repositorio/seam y localización); `App/Core/Location/DeviceLocationProvider.swift` (seam de localización compartida).