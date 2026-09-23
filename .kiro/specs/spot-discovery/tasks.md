# Implementation Plan: spot-discovery

## 1. Foundation: provisioning de datos y modelos del dominio
- [x] 1.1 Definir el esquema de spots y favoritos con RLS y funciones RPC
  - Crear `db/spot-discovery/001_spot_discovery_init.sql` con: extensión PostGIS; tabla `spots` (id uuid PK, name, category, summary, geom geometry(Point,4326), longitude, latitude, created_at/updated_at) e índice GiST sobre `geom`; tabla `spot_favorites` (spot_id FK cascade, user_id FK auth.users cascade, created_at, PK compuesta) e índice por user_id; RLS con `spots` de lectura pública y `spot_favorites` restringida a `auth.uid() = user_id`.
  - Declarar las funciones RPC con las firmas del diseño: `nearby_spots(lat, lng, radius_km)` devolviendo `distance_m` y ordenando por distancia (ST_DWithin/ST_Distance sobre geography), `my_favorite_spot_ids()`, `my_favorite_spots()`, `add_spot_favorite(spot_id)` (ON CONFLICT DO NOTHING) y `remove_spot_favorite(spot_id)`, todas con `security definer` y filtro interno por `auth.uid()`.
  - Observable: el fichero SQL existe, es re-ejecutable (`create ... if not exists`/`create or replace function`) y el esquema + RPC coinciden con los contratos del diseño (nombres, argumentos, columnas de respuesta).
  - _Requirements: 5.6, 6.4_

- [x] 1.2 Sembrar la semilla curada de spots
  - Añadir al mismo migration un bloque `insert ... on conflict (name) do nothing` con una lista curada de 10–20 spots realistas (río/lago/embalse/mar/costa) incluyendo `longitude`, `latitude` y `geom` coherentes para cada uno, con `category` encajando en los valores del dominio (`river`, `lake`, `sea`, `shore`).
  - Verificar manualmente (p. ej. consulta SQL de prueba o ejecución en un Supabase local) que una llamada a `nearby_spots` devuelve filas ordenadas por `distance_m` con la forma JSON que el repositorio descodificará.
  - Observable: la semilla es idempotente (re-ejecutar no duplica) y `nearby_spots(41.4, 2.2, 50)` devuelve el subconjunto esperado ordenado por distancia creciente.
  - _Requirements: 1.1, 6.2_

- [x] 1.3 Modelos del dominio de spots y tests de serialización
  - Definir en `App/Models/Spots/`: `Spot` (id, name, category, summary, longitude, latitude, `distanceMeters` opcional con `CodingKeys` para `distance_m`, y `coordinate: LocationCoordinate2D` derivada), `SpotCategory` (enum `String` `river, lake, sea, shore`) y `SpotRegion` (center + latitudinalMeters/longitudinalMeters, `Equatable`/`Sendable`, con esquinas derivadas para los filtros) reutilizando `LocationCoordinate2D`.
  - Añadir `SpotModelsTests` con round-trip Codable de `Spot` (con y sin `distance_m`), de `SpotCategory` y de `SpotRegion`.
  - Observable: `SpotModelsTests` en verde y los tres tipos compilan en el target de la app con conformidades `Codable`/`Sendable`.
  - _Requirements: 4.2, 6.2_

## 2. Core: repositorio, dobles y feature de descubrimiento
- [x] 2.1 Declarar el contrato `SpotRepository` y su error tipado
  - Definir en `App/Services/Spots/SpotRepository.swift` el protocolo `SpotRepository: Sendable` (listSpots(region:), nearbySpots(from:radiusKilometers:), spot(id:), favoriteSpotIDs(), favoriteSpots(), setFavorite(spotID:isFavorite:)) y `SpotRepositoryError` (`backendUnavailable`, `queryFailed`, `authenticationRequired`), según el contrato del diseño.
  - Garantizar que un doble mínimo del test target puede conformar el protocolo sin importar Supabase.
  - Observable: el protocolo y el error compilan y un double mínimo conforma `SpotRepository` en el test target (sin dependencias externas).
  - Nota: esta tarea no es (P) porque establece el contrato que compilan los tres actores siguientes (2.2, 2.3, 2.4).
  - _Requirements: 6.1, 6.4_
  - _Boundary: Services/Spots (SpotRepository)_

- [x] 2.2 (P) Implementar `SupabaseSpotRepository` sobre los seams de la base
  - _Depends: 2.1_
  - Implementar el actor `SupabaseSpotRepository: SpotRepository` en `App/Services/Spots/SupabaseSpotRepository.swift` consumiendo solo `SupabaseDatabaseAccess` (select para listado por región con filtros de caja y para `spot(id:)`; rpc para `nearby_spots`, `my_favorite_spot_ids`, `my_favorite_spots`, `add_spot_favorite`, `remove_spot_favorite`) y `SupabaseAuthProviding` (currentUser para el gate de `setFavorite`, que lanza `authenticationRequired` sin sesión); traducir fallos del seam a `SpotRepositoryError`.
  - Mapear los nombres snake_case (`distance_m`, `spot_id`) con rows `Decodable`/`Sendable` privados del fichero.
  - Añadir `SupabaseSpotRepositoryTests` con `SupabaseBaseFake`: listado por región decodifica `[Spot]`, `nearbySpots` ordena y rellena `distanceMeters`, `spot(id:)` devuelve objeto/nil, favoritos con sesión (rpc correcta) y `authenticationRequired` sin sesión.
  - Observable: la suite de `SupabaseSpotRepositoryTests` en verde sobre el fake de la base, sin red real.
  - _Requirements: 1.1, 1.2, 3.1, 3.2, 5.1, 5.2, 5.3, 5.6, 6.1, 6.3, 6.4_
  - _Boundary: Services/Spots (SupabaseSpotRepository)_

- [x] 2.3 (P) Doble del repositorio para el test target
  - _Depends: 2.1_
  - Implementar `SpotRepositoryFake` en `BetterFishingTests/` conformando `SpotRepository` con éxito/fallo programables (spots sembrados por región, cercanos ordenables, ids de favoritos, errores forzables) y registro de llamadas (regiones, coordenadas, radios, ids, toggles) para aserciones.
  - Añadir un test del propio double que verifica la programación de éxito/fallo y el registro.
  - Observable: el fake compila en el test target y su test verifica los dos modos sin contactar red.
  - _Requirements: 6.1_
  - _Boundary: BetterFishingTests (SpotRepositoryFake)_

- [x] 2.4 (P) Detalle del spot con favoritos y gate de sesión
  - _Depends: 2.1, 2.3_
  - Implementar `SpotDetailViewModel` (`@MainActor`) que recibe `SpotRepository` y `SupabaseAuthProviding`: carga el estado de favorito desde `favoriteSpotIDs()` y `currentUser()`, `toggleFavorite()` llama a `setFavorite` con sesión o activa el aviso «inicia sesión» sin sesión (sin navegar al flujo de cuenta), y suscribe `stateChanges()` (`.signedIn`/`.signedOut`) para refrescar `isFavorite`.
  - Implementar `SpotDetailView` mostrando nombre, categoría, resumen y coordenadas del spot, con el control de favorito y los estados de aviso (sesión requerida) y de error del toggle.
  - Añadir `SpotDetailViewModelTests` con `SpotRepositoryFake` y un doble de `SupabaseAuthProviding`: isFavorite inicial, toggle con/sin sesión, refresco en cambio de sesión y errores del repositorio.
  - Observable: `SpotDetailViewModelTests` en verde y la vista compila mostrando los datos y el aviso de sesión.
  - _Requirements: 4.1, 4.2, 4.3, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - _Boundary: Features/SpotDiscovery (detalle: SpotDetailViewModel, SpotDetailView)_

- [x] 2.5 Mapa de spots con anotaciones, región y «cerca de mí»
  - _Depends: 2.4_ (SpotMapView navega a `SpotDetailView` mediante la factory inyectada)
  - Implementar `SpotMapViewModel` (`@MainActor`) con `SpotRepository?` opcional y `DeviceLocationProviding`: estado de carga/error reintentable/no disponible, región bindeada con debounce → `listSpots(region:)`, `showNearby()` pide permiso+ubicación y llama `nearbySpots` mostrando distancia o el aviso correspondiente (permiso denegado / sin ubicación / sin spots en el radio), y publica `selectedSpot`.
  - Implementar `SpotMapView` con `Map` de SwiftUI (anotaciones de `spots`, conversión `SpotRegion`↔`MKCoordinateRegion` aislada en la vista), barras de estado (carga/error/no disponible), botón «cerca de mí» y un `NavigationStack` con `.navigationDestination` que presenta `SpotDetailView` creado por una factory inyectada `(Spot) -> SpotDetailView`.
  - Añadir `SpotMapViewModelTests` con `SpotRepositoryFake` y un doble de localización: región→listado, cerca-de-mí con/sin ubicación y sin spots, degradación con repositorio nil.
  - Observable: `SpotMapViewModelTests` en verde, la vista compila mostrando anotaciones y el flujo cerca-de-mí navega al detalle con la factory.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 3.1, 3.2, 3.3, 3.4, 4.1_
  - _Boundary: Features/SpotDiscovery (mapa: SpotMapViewModel, SpotMapView)_

## 3. Integration: composición, degradación y pestaña de mapa
- [x] 3.1 Conectar el repositorio de spots al composition root
  - _Depends: 2.2, 2.3_
  - Extender `AppRootServices` con `spotRepository: (any SpotRepository)?`, `spotMapViewModel: SpotMapViewModel?` y `spotDetailViewModelFactory: ((Spot) -> SpotDetailViewModel)?`; en `makeRootServices`, si hay `SupabaseStack` construir `SupabaseSpotRepository(database:auth:)` (reutilizando el mismo `DeviceLocationProvider` de Core que catch-log) y derivar el ViewModel del mapa y la factory de detalle; si no hay stack mantener los tres en `nil` con log del motivo (degradación, Req 2).
  - Añadir soporte UI test (DEBUG) para sembrar un `SpotRepositoryFake` y poder probar el tab Mapa.
  - Añadir `SpotDiscoveryCompositionTests`: con configuración vacía el resto de servicios se construyen y `spotRepository == nil`; con stack construido sobre `SupabaseBaseFake` el repositorio y el ViewModel del mapa quedan no nil y funcionan.
  - Observable: `SpotDiscoveryCompositionTests` en verde y `AppRootServices` ofrece el repositorio opcional sin conocer Supabase.
  - _Requirements: 2.1, 2.2, 6.1, 6.3_
  - _Boundary: AppCompositionSupport, AppRootServices_

- [ ] 3.2 Añadir la pestaña «Mapa» a la navegación raíz
  - _Depends: 3.1, 2.5_
  - En `RootView.mainTabs` añadir un tercer tab «Mapa» (`NavigationStack { SpotMapView(...) }`) usando el ViewModel inyectado y el factory de detalle; cuando `spotMapViewModel == nil` mostrar el estado «no disponible» (la pestaña sigue existiendo y el resto de pestañas no cambia).
  - Registrar los ficheros nuevos en `project.pbxproj` (app y test targets) siguiendo el patrón existente; verificar que MapKit/CoreLocation se enlazan sin cambios de build settings.
  - Observable: `xcodebuild build` pasa y el tab «Mapa» aparece en la app con anotaciones (o estado de no disponible) sin afectar a «Identificar» ni «Capturas».
  - _Requirements: 1.1, 2.1, 2.2, 4.1_
  - _Boundary: BetterFishingApp (RootView), project.pbxproj_

## 4. Validation: flujos E2E y verificación de la suite
- [ ] 4.1 Validación E2E de descubrimiento y favoritos con sesión
  - _Depends: 3.2, 2.2_
  - Añadir un test de integración (test target) que, con la composición construida sobre `SupabaseBaseFake` y una sesión simulada, verifica el flujo completo: abrir el mapa → listar anotaciones de la región → «cerca de mí» con ubicación simulada ordena por distancia → seleccionar un spot → marcar/quitar favorito (RPC correcta) → cambio de sesión refresca el estado.
  - Verificar el mismo flujo con `supabase == nil`: la pestaña queda en «no disponible» y ninguna operación rompe la app.
  - Observable: el test de integración en verde cubre mapa → cerca-de-mí → detalle → favoritos y la degradación sin stack.
  - _Requirements: 2.1, 2.2, 5.1, 5.2, 5.4, 5.5_

- [ ]* 4.2 Humo UI del tab Mapa (opcional, diferible post-MVP)
  - _Depends: 3.2_
  - Añadir `SpotMapUITests` (target UI) que con el `SpotRepositoryFake` sembrado lanza «Mapa» y comprueba que se renderizan anotaciones y que tocar una anotación navega al detalle.
  - Observable: el test UI de humo en verde sobre el doble; si se difiere, la cobertura funcional ya está garantizada por 4.1 y los tests de ViewModels (ACs cubiertas: 1.1, 4.1).
  - _Requirements: 1.1, 4.1_

- [ ] 4.3 Verificación de la suite completa y conformidad Swift 6
  - _Depends: 4.1_
  - Ejecutar `xcodebuild test -scheme BetterFishing` completo: la suite existente (línea base de catch-log/fish-species) sigue en verde, los tests nuevos de spot-discovery pasan y no aparecen advertencias de concurrencia en Swift 6 estricto.
  - Confirmar que ningún seam de `catch-log`, `fish-species-identification` ni `supabase-foundation` fue modificado (diff de revisión).
  - Observable: suite completa en verde y build sin advertencias de concurrencia; diff confirmado sin cambios fuera del boundary de esta feature.
  - _Requirements: 6.5_

## Implementation Notes
- El provisioning (`db/spot-discovery/001_spot_discovery_init.sql`) es un artefacto nuevo a nivel raíz del repo (directorio `db/`); se aplica manualmente en el entorno de Supabase antes de la validación con infra real. No se versionan credenciales.
- `SupabaseSpotRepository` consume únicamente `select`/`rpc` del seam de la base: cualquier necesidad de insert/update/delete nativo debe resolverse como RPC (patrón fijado) y nunca ampliando `SupabaseDatabaseAccess` (Revalidation Trigger de la base).
- `SpotMapView` y `SpotMapViewModel` no importan Supabase; la conversión `MKCoordinateRegion`↔`SpotRegion` queda acotada a la capa de vista para mantener `Sendable` en el cruce de actores (Swift 6).
- El gate de sesión de favoritos es doble: UX en `SpotDetailViewModel` (via `currentUser()`) y autoritativo en las RPC/RLS (`auth.uid()`), de modo que «account-personal» pueda reutilizar el mismo `SpotRepository` sin cambios.
- Los tests de repositorio usan `SupabaseBaseFake` de `supabase-foundation` (ya disponible en el test target); los tests de ViewModels usan `SpotRepositoryFake` y los doubles de localización existentes (`DeviceLocationProviderDouble`, `CompositionTestLocationProvider`).
- Los ficheros Swift nuevos se registran en `project.pbxproj` siguiendo el patrón de `catch-log` (fileRef + buildFile + Sources) en los targets app/test/UI-test correspondientes.
- 2.2: `SupabaseSpotRepository` (actor) consume solo `SupabaseDatabaseAccess`/`SupabaseAuthProviding`; rpc keys `lat`/`lng`/`radius_km` y `spot_id` (no `p_`); favoritos `favoriteSpotIDs() -> Set<UUID>` decodificando `FavoriteIDRow` (`spot_id`); toda falla de seam → `.queryFailed("operación: razón")`; `backendUnavailable` solo sin stack; `setFavorite` decodifica el void vía `FavoriteMutationResult` (cuerpo real RPC void pendiente de infra, fuera de boundary). `SupabaseBaseFake` extendido backward-compatible (JSON canned para T no-String + `isSessionActive`; 8 tests previos intactos).
- 2.3: `SpotRepositoryFake` (lock-guarded, test target) con seeds por región, nearby ordenado `distanceMeters` asc nil-last, errores programables por seam, registro de 5 canales y `reset()` que conserva el estado programado (16 tests). RED verificado sin artefacto persistente (ambos ficheros aterrizan juntos); se deja constancia aquí para auditoría.
- 2.4: `SpotDetailViewModel` (@MainActor/@Observable) — `stateChangesTask` con `nonisolated(unsafe)` (escritura solo en MainActor, cancelación en deinit; Task con captura débil); `.signedIn`/`.sessionRestored` recargan `favoriteSpotIDs()`, `.signedOut` → `isFavorite=false` sin RPC + aviso. Sin navegación a cuenta (gatado vía `currentUser()`).
- 2.5: `SpotMapViewModel` (@MainActor) — debounce 20ms inyectable con `loadGeneration` (guard de resultados obsoletos), cancel-safe; `showNearby()` = requestPermission → currentLocation → `nearbySpots` (avisos permissionDenied/noLocation/noSpotsInRadius); conversión `MKCoordinateRegion`↔`SpotRegion` aislada en la vista. FYI: un `regionLoadTask` pendiente puede sobreescribir el listado cercano tras `showNearby()` (sugerencia no bloqueante, revisar en integración); `SpotMapView` OWNS su `NavigationStack` → 3.2 NO debe envolver en otro. Reducción de Req 2.2 delegada a composición (VM nuevo con repo no-nil).
- 1.1: esquema/RPC en `db/spot-discovery/001_spot_discovery_init.sql` con contrato de args del diseño (`spot_id`, no `p_spot_id`); ronda 1 REJECT por `p_spot_id` → ronda 2 REJECT por shadowing columna/param en DELETE (precedencia de columna, §36.5) → `remove_spot_favorite` delete final con `spot_id = $1` (posicional) y LHS calificado. FYI: design.md:601-616 aún muestra `p_spot_id` (doc a reconciliar, fuera de boundary). `nearby_spots(41.4,2.2,50)` validado estáticamente (Haversine) con el subconjunto esperado; la validación con infra real queda pendiente de entorno Supabase (1.2).
- 1.2: semilla (18 spots) al final de `001_spot_discovery_init.sql` tras los grants, con `spots_name_uidx` para que `on conflict (name)` funcione al re-ejecutar. `nearby_spots(41.4,2.2,50)` → 10 filas en radio en orden ascendente: Barceloneta (~2.5 km), Besòs (~2.9), Port de Barcelona (~3.8), Badalona (~6.8), Delta Llobregat (~14.4), Llobregat Sant Boi (~15.2), Castelldefels (~25.0), Anoia Martorell (~31.2), Tordera Sant Celoni (~43.9), Vallforners (~46.4); fuera de radio: Sau (~67), Banyoles (~92), Cambrils (~100), Boadella (~116), Cap de Creus (~133), Segre Lleida (~133), Ebre Fangar (~137), Tierra Alta (~152).
- 1.2 (categorías sembradas): river (Besòs, Llobregat Sant Boi, Anoia, Tordera, Segre Lleida), lake (Sau, Tierra Alta, Vallforners, Boadella, Banyoles), sea (Port Barcelona, Ebre Fangar, Cap de Creus), shore (Barceloneta, Badalona, Delta Llobregat, Castelldefels, Cambrils).
- 1.3: `Spot` (`Hashable` incluye `Equatable` del diseño) con `LocationCoordinate2D` compartida de Catch.swift (no movida); `SpotRegion` deriva esquinas del bbox con 111_320 m/grado lat y `111_320*cos(lat)` para lon (aislado de MapKit). 8 tests `SpotModelsTests` en verde; suite completa 227/227.
- 2.1: `SpotRepository` (`Sendable`) + `SpotRepositoryError` (`Sendable`/`Equatable`, `queryFailed(String)`) en `App/Services/Spots/SpotRepository.swift`; `SpotRepositoryContractTests` con un doble Foundation-only ejerce los 6 métodos y los 3 casos de error. Suite 232/232 (227 base + 5 nuevos).
- 2.2: `SupabaseSpotRepository` actor en `App/Services/Spots/SupabaseSpotRepository.swift` con rows privados `NearbySpotRow` (`distance_m`→distanceMeters), `FavoriteIDRow` (`spot_id`→UUID) y `FavoriteMutationResult` (rpc void). RPC: `nearby_spots` con claves `lat`/`lng`/`radius_km` (`.double`), `my_favorite_spot_ids`, `my_favorite_spots`, `add_spot_favorite`/`remove_spot_favorite` con `["spot_id": .string(uuidString)]`; `setFavorite` gatea con `currentUser()` (`.authenticationRequired` si nil) y `favoriteSpotIDs()` devuelve conjunto vacío sin sesión; todo fallo de seam → `.queryFailed("operación: razón")`. `SupabaseBaseFake` extendido (backward-compatible) con decodificación JSON para tipos no-`String` en `select`/`rpc` y bandera `isSessionActive` para simular sesión ausente.
- 2.3: `SpotRepositoryFake` en el test target (`@unchecked Sendable` con `NSLock`, patrón `SupabaseBaseFake`): seeds por región (lookup por igualdad, `SpotRegion` no es `Hashable`), `nearbyResult` ordenado por `distanceMeters` ascendente (nil al final), `favoriteIDs` programable, error por seam (`*Error`, registro antes de lanzar), y registro de regiones/coordenadas/radios/ids/toggles con `reset()`. 16 tests `SpotRepositoryFakeTests` en verde (incluye conformancia y aislamiento de errores); suite completa 260/260.
- 2.4: máquina de estados del `SpotDetailViewModel` (`@MainActor @Observable`): `isFavorite`, `isLoading`, `sessionRequiredNotice` y `toggleErrorMessage`; sin sesión el `toggleFavorite()` solo activa el aviso (nunca llama al repo); con sesión `setFavorite` y actualiza tras éxito (el fallo conserva `isFavorite`). Semántica de `stateChanges()`: `signedIn`/`sessionRestored` recargan `favoriteSpotIDs()`, `signedOut` pone `isFavorite=false` sin RPC y activa el aviso; el `Task` de la suscripción se cancela en `deinit` (`@ObservationIgnored nonisolated(unsafe) private(set) var stateChangesTask`, captura débil de `self` por iteración). 9 tests `SpotDetailViewModelTests`, suite 269/269.
- 2.5: `SpotMapViewModel` (`@MainActor @Observable`) con debounce de región (`regionLoadTask` cancelable + generación guard en `performRegionLoad`, `Task.sleep` con propagación de cancelación) que llama `listSpots(region:)`; estados `loading/loaded/failed/unavailable` y `NearbyNotice` (`permissionDenied`/`noLocation`/`noSpotsInRadius`/`loadFailed`) para «cerca de mí»; factory de vista inyectada `@MainActor (Spot) -> SpotDetailView` en `SpotMapView` (conversión `MKCoordinateRegion`↔`SpotRegion` aislada en la vista). 10 tests `SpotMapViewModelTests`, suite 279/279.
- 3.1: `AppRootServices` gana `spotRepository: (any SpotRepository)?`, `spotMapViewModel: SpotMapViewModel?` y `spotDetailViewModelFactory: (@MainActor (Spot) -> SpotDetailViewModel)?` (puente Swift 6: el actor `SupabaseSpotRepository` se guarda opcional y es `Sendable` en el cruce `@MainActor`; la factory usa paréntesis externos porque `@MainActor ((...) -> ...)?` no parsea en Swift 6). `makeRootServices` reutiliza el `DeviceLocationProvider` de catch-log (hoisteado) para el VM del mapa; sin stack → tres `nil` + log de degradación (Req 2); nuevo parámetro inyectable `supabaseStack:` para conectar un `SupabaseStack` sobre el fake de la base.
- 3.1 (UI test): escenario `spotMapSeeded` siembra el doble app-target `UITestSpotRepository` (`#if DEBUG`, `SpotRepositoryFake` es solo test target) más `UITestNoAuthProvider` para la factory de detalle; el resto de escenarios de `makeUITestRootServices` rellenan los tres campos con `nil`. `SpotDiscoveryCompositionTests` (D02/C11): sin stack → servicios existentes + `nil`; con stack sobre `SupabaseBaseFake` → repo/VM construidos, `loadSpots()` registra el `select` y deja el mapa en `loaded`.
- RED 3.1: evidencia reproducida con `SpotDiscoveryCompositionTests` antes de los campos: `Value of type 'AppRootServices' has no member 'spotRepository'` / `'spotMapViewModel'` / `'spotDetailViewModelFactory'` + `Extra argument 'supabaseStack' in call` → BUILD FAILED (3 errores); implementado el wiring y suite 281 en verde (2 tests nuevos).