# Implementation Plan: spot-discovery

## 1. Foundation: provisioning de datos y modelos del dominio
- [ ] 1.1 Definir el esquema de spots y favoritos con RLS y funciones RPC
  - Crear `db/spot-discovery/001_spot_discovery_init.sql` con: extensión PostGIS; tabla `spots` (id uuid PK, name, category, summary, geom geometry(Point,4326), longitude, latitude, created_at/updated_at) e índice GiST sobre `geom`; tabla `spot_favorites` (spot_id FK cascade, user_id FK auth.users cascade, created_at, PK compuesta) e índice por user_id; RLS con `spots` de lectura pública y `spot_favorites` restringida a `auth.uid() = user_id`.
  - Declarar las funciones RPC con las firmas del diseño: `nearby_spots(lat, lng, radius_km)` devolviendo `distance_m` y ordenando por distancia (ST_DWithin/ST_Distance sobre geography), `my_favorite_spot_ids()`, `my_favorite_spots()`, `add_spot_favorite(spot_id)` (ON CONFLICT DO NOTHING) y `remove_spot_favorite(spot_id)`, todas con `security definer` y filtro interno por `auth.uid()`.
  - Observable: el fichero SQL existe, es re-ejecutable (`create ... if not exists`/`create or replace function`) y el esquema + RPC coinciden con los contratos del diseño (nombres, argumentos, columnas de respuesta).
  - _Requirements: 5.6, 6.4_

- [ ] 1.2 Sembrar la semilla curada de spots
  - Añadir al mismo migration un bloque `insert ... on conflict (name) do nothing` con una lista curada de 10–20 spots realistas (río/lago/embalse/mar/costa) incluyendo `longitude`, `latitude` y `geom` coherentes para cada uno, con `category` encajando en los valores del dominio (`river`, `lake`, `sea`, `shore`).
  - Verificar manualmente (p. ej. consulta SQL de prueba o ejecución en un Supabase local) que una llamada a `nearby_spots` devuelve filas ordenadas por `distance_m` con la forma JSON que el repositorio descodificará.
  - Observable: la semilla es idempotente (re-ejecutar no duplica) y `nearby_spots(41.4, 2.2, 50)` devuelve el subconjunto esperado ordenado por distancia creciente.
  - _Requirements: 1.1, 6.2_

- [ ] 1.3 Modelos del dominio de spots y tests de serialización
  - Definir en `App/Models/Spots/`: `Spot` (id, name, category, summary, longitude, latitude, `distanceMeters` opcional con `CodingKeys` para `distance_m`, y `coordinate: LocationCoordinate2D` derivada), `SpotCategory` (enum `String` `river, lake, sea, shore`) y `SpotRegion` (center + latitudinalMeters/longitudinalMeters, `Equatable`/`Sendable`, con esquinas derivadas para los filtros) reutilizando `LocationCoordinate2D`.
  - Añadir `SpotModelsTests` con round-trip Codable de `Spot` (con y sin `distance_m`), de `SpotCategory` y de `SpotRegion`.
  - Observable: `SpotModelsTests` en verde y los tres tipos compilan en el target de la app con conformidades `Codable`/`Sendable`.
  - _Requirements: 4.2, 6.2_

## 2. Core: repositorio, dobles y feature de descubrimiento
- [ ] 2.1 Declarar el contrato `SpotRepository` y su error tipado
  - Definir en `App/Services/Spots/SpotRepository.swift` el protocolo `SpotRepository: Sendable` (listSpots(region:), nearbySpots(from:radiusKilometers:), spot(id:), favoriteSpotIDs(), favoriteSpots(), setFavorite(spotID:isFavorite:)) y `SpotRepositoryError` (`backendUnavailable`, `queryFailed`, `authenticationRequired`), según el contrato del diseño.
  - Garantizar que un doble mínimo del test target puede conformar el protocolo sin importar Supabase.
  - Observable: el protocolo y el error compilan y un double mínimo conforma `SpotRepository` en el test target (sin dependencias externas).
  - Nota: esta tarea no es (P) porque establece el contrato que compilan los tres actores siguientes (2.2, 2.3, 2.4).
  - _Requirements: 6.1, 6.4_
  - _Boundary: Services/Spots (SpotRepository)_

- [ ] 2.2 (P) Implementar `SupabaseSpotRepository` sobre los seams de la base
  - _Depends: 2.1_
  - Implementar el actor `SupabaseSpotRepository: SpotRepository` en `App/Services/Spots/SupabaseSpotRepository.swift` consumiendo solo `SupabaseDatabaseAccess` (select para listado por región con filtros de caja y para `spot(id:)`; rpc para `nearby_spots`, `my_favorite_spot_ids`, `my_favorite_spots`, `add_spot_favorite`, `remove_spot_favorite`) y `SupabaseAuthProviding` (currentUser para el gate de `setFavorite`, que lanza `authenticationRequired` sin sesión); traducir fallos del seam a `SpotRepositoryError`.
  - Mapear los nombres snake_case (`distance_m`, `spot_id`) con rows `Decodable`/`Sendable` privados del fichero.
  - Añadir `SupabaseSpotRepositoryTests` con `SupabaseBaseFake`: listado por región decodifica `[Spot]`, `nearbySpots` ordena y rellena `distanceMeters`, `spot(id:)` devuelve objeto/nil, favoritos con sesión (rpc correcta) y `authenticationRequired` sin sesión.
  - Observable: la suite de `SupabaseSpotRepositoryTests` en verde sobre el fake de la base, sin red real.
  - _Requirements: 1.1, 1.2, 3.1, 3.2, 5.1, 5.2, 5.3, 5.6, 6.1, 6.3, 6.4_
  - _Boundary: Services/Spots (SupabaseSpotRepository)_

- [ ] 2.3 (P) Doble del repositorio para el test target
  - _Depends: 2.1_
  - Implementar `SpotRepositoryFake` en `BetterFishingTests/` conformando `SpotRepository` con éxito/fallo programables (spots sembrados por región, cercanos ordenables, ids de favoritos, errores forzables) y registro de llamadas (regiones, coordenadas, radios, ids, toggles) para aserciones.
  - Añadir un test del propio double que verifica la programación de éxito/fallo y el registro.
  - Observable: el fake compila en el test target y su test verifica los dos modos sin contactar red.
  - _Requirements: 6.1_
  - _Boundary: BetterFishingTests (SpotRepositoryFake)_

- [ ] 2.4 (P) Detalle del spot con favoritos y gate de sesión
  - _Depends: 2.1, 2.3_
  - Implementar `SpotDetailViewModel` (`@MainActor`) que recibe `SpotRepository` y `SupabaseAuthProviding`: carga el estado de favorito desde `favoriteSpotIDs()` y `currentUser()`, `toggleFavorite()` llama a `setFavorite` con sesión o activa el aviso «inicia sesión» sin sesión (sin navegar al flujo de cuenta), y suscribe `stateChanges()` (`.signedIn`/`.signedOut`) para refrescar `isFavorite`.
  - Implementar `SpotDetailView` mostrando nombre, categoría, resumen y coordenadas del spot, con el control de favorito y los estados de aviso (sesión requerida) y de error del toggle.
  - Añadir `SpotDetailViewModelTests` con `SpotRepositoryFake` y un doble de `SupabaseAuthProviding`: isFavorite inicial, toggle con/sin sesión, refresco en cambio de sesión y errores del repositorio.
  - Observable: `SpotDetailViewModelTests` en verde y la vista compila mostrando los datos y el aviso de sesión.
  - _Requirements: 4.1, 4.2, 4.3, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - _Boundary: Features/SpotDiscovery (detalle: SpotDetailViewModel, SpotDetailView)_

- [ ] 2.5 Mapa de spots con anotaciones, región y «cerca de mí»
  - _Depends: 2.4_ (SpotMapView navega a `SpotDetailView` mediante la factory inyectada)
  - Implementar `SpotMapViewModel` (`@MainActor`) con `SpotRepository?` opcional y `DeviceLocationProviding`: estado de carga/error reintentable/no disponible, región bindeada con debounce → `listSpots(region:)`, `showNearby()` pide permiso+ubicación y llama `nearbySpots` mostrando distancia o el aviso correspondiente (permiso denegado / sin ubicación / sin spots en el radio), y publica `selectedSpot`.
  - Implementar `SpotMapView` con `Map` de SwiftUI (anotaciones de `spots`, conversión `SpotRegion`↔`MKCoordinateRegion` aislada en la vista), barras de estado (carga/error/no disponible), botón «cerca de mí» y un `NavigationStack` con `.navigationDestination` que presenta `SpotDetailView` creado por una factory inyectada `(Spot) -> SpotDetailView`.
  - Añadir `SpotMapViewModelTests` con `SpotRepositoryFake` y un doble de localización: región→listado, cerca-de-mí con/sin ubicación y sin spots, degradación con repositorio nil.
  - Observable: `SpotMapViewModelTests` en verde, la vista compila mostrando anotaciones y el flujo cerca-de-mí navega al detalle con la factory.
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 3.1, 3.2, 3.3, 3.4, 4.1_
  - _Boundary: Features/SpotDiscovery (mapa: SpotMapViewModel, SpotMapView)_

## 3. Integration: composición, degradación y pestaña de mapa
- [ ] 3.1 Conectar el repositorio de spots al composition root
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