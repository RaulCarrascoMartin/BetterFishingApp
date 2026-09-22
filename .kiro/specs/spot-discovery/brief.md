# Brief: spot-discovery

## Problem
El pescador no tiene ninguna forma de descubrir buenos sitios donde pescar: hoy solo puede identificar especies y llevar su registro de capturas. Necesita ver en un mapa spots curados (con su ubicación e info básica) y poder guardar sus favoritos, para planear la salida de pesca cerca de su ubicación.

## Current State
- No existe ninguna visualización de mapa ni spots en la app (`BetterFishing.kiro` solo tiene scanner + catch-log, ambos validados GO).
- No hay cliente Supabase todavía; la capa base `supabase-foundation` aún no está construida (spec en roadmap, antes que esta).
- `CoreLocation`/MapKit y las ubicaciones del dispositivo están sin usar salvo `DeviceLocationProvider` (pertenece a catch-log; el permiso de ubicación se decide en el guardado del escáner).

## Desired Outcome
- Un mapa (MapKit) con spots curados (geometría PostGIS + semilla) mostrados como anotaciones; integración de la ubicación del usuario para mostrar "spots cerca de mí".
- Acceso anónimo al mapa (sin login); favoritos requieren cuenta (auth de `supabase-foundation`).
- `SpotRepository` tras un protocolo (seam) consumible/inyectable, coherente con el patrón de repositorios de las features previas.
- Toda la lectura de spots y favoritos pasa por Supabase (PostGIS/Postgres), sin persistencia local duplicada para el descubrimiento.

## Approach
Consumir `supabase-foundation` para las llamadas a Supabase; geometry via PostGIS; semilla curada de spots en v1 (sin subida comunitaria). MapKit para el renderizado; CoreLocation para ubicación del usuario. Favoritos ligados a la cuenta (auth).

## Scope
- **In**: mapa con spots curados (semilla PostGIS), anotaciones, spots cerca de mí (ordenados por distancia, postgis), seleccionar spot → detalle básico; favoritos con cuenta; seam `SpotRepository` + implementación Supabase.
- **Out**: subida/moderación de spots por usuarios, rating, cuenta de pago, datos regulatorios de especie, sync del registro de capturas (pertenece a account-personal).

## Boundary Candidates
- `SpotRepository` (protocolo CRUD/geográfico) + `SupabaseSpotRepository` → `App/Services/Spots/`
- `SpotMapView` / `SpotDetailView` + ViewModels → `App/Features/SpotDiscovery/`
- Modelos `Spot`, `SpotCategory` → `App/Models/`

## Out of Boundary
- Subida de spots por usuarios, moderación y rating (fuera de v1).
- Sync del registro de capturas (es de account-personal).
- Información regulatoria por especie.

## Upstream / Downstream
- **Upstream**: `supabase-foundation` (auth + cliente Supabase + storage).
- **Downstream**: `account-personal` (favoritos del spot también disfrutados desde la cuenta; la cuenta consume el mismo `SpotRepository`).

## Existing Spec Touchpoints
- **Adjacent**: `catch-log` (aporta el patrón `CatchRepository`/seams y el `DeviceLocationProvider` para la ubicación; la navegación `RootView`/TabView se extiende añadiendo el tab de mapa). Ningún seam de catch-log cambia.
- **Adjacent**: `fish-species-identification` (aporta el modelo `Species`/seam `FishIdentifying`; sin cambios).

## Constraints
- iOS 17+, SwiftUI, MapKit + CoreLocation, protocolos `Sendable`/`@MainActor` coherentes con las features previas, destino por protocolo/dobles en tests, sin librerías de terceros nuevas fuera del Supabase SDK (ya en fundación).
