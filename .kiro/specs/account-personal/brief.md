# Brief: account-personal

## Problem
Hoy el registro de capturas y (próximamente) los favoritos de spots viven solo en el dispositivo. El pescador que cambia de móvil o reinstala pierde todo su historial y sus spots guardados; además la app no tiene noción de quién es el usuario. Falta una cuenta personal con perfil, favoritos persistentes y sincronización del registro de capturas, para que el historial acompañe al usuario entre dispositivos y quede asociado a su cuenta.

## Current State
- `catch-log` validada GO: `CatchRepository`/`CatchSaving` (protocolos) + `LocalFileCatchRepository` persistencia local CRUD; `Catch` modelo definitivo; migración única de borradores.
- `fish-species-identification` validada GO: provee seam `FishIdentifying`/`CatchSaving`.
- `supabase-foundation` (espec base, próxima) aportará `SupabaseAuthProviding`/`SupabaseDatabaseAccess`/`SupabaseStoring`; `spot-discovery` (próxima) aporta el `SpotRepository` con favoritos por cuenta.
- La sync del registro no existe: `Catch` solo persiste en `Application Support/Catches/`.

## Desired Outcome
- **Cuenta personal**: registro/inicio de sesión, perfil (nombre, avatar), cierre de sesión.
- **Favoritos**: gestionar favoritos de spots asociados a la cuenta consumiendo el seam `SpotRepository` de spot-discovery (dueño de la tabla `spot_favorites` y las RPC de favoritos), visibles en el mapa.
- **Sync del registro**: subir las capturas locales al Supabase por cuenta y traerlas al reinstalar/cambiar de dispositivo (merge por `Catch.id` sin duplicar), preservando el seam `CatchRepository` existente (la sync es una ruta adicional, no reemplaza la persistencia local).

## Approach
Autenticación vía `supabase-foundation` (Auth), perfil en `profiles` (Supabase), favoritos gestionados por el seam `SpotRepository` de spot-discovery (tabla `spot_favorites`, RPC `my_favorite_*`/`add_spot_favorite`/`remove_spot_favorite`, RLS por `auth.uid()`) que account-personal consume vía `SpotRepositorySpotPresenting`, y sync del registro como servicio `CatchSyncService` que lee/escribe `catches` en Supabase. La cuenta personal consume `SpotRepository` (de spot-discovery) para favoritos sin acoplarla a la geometría y sin crear tabla/RPC propias. No se cambia la dirección de dependencias: features → servicios → core, seams tras protocolos.

## Scope
- **In**: auth (signUp/signIn/signOut/session), perfil + avatar (storage), favoritos de spots CRUD, y sync del registro de capturas (push local→Supabase y pull Supabase→local con merge idempotente por `Catch.id`).
- **Out**: cuenta de pago, moderación de spots, datos regulatorios por especie, subida de spots por usuarios (de spot-discovery), sincronización en tiempo real del mapa de spots.

## Boundary Candidates
- `Features/Account/AccountView` + `AccountViewModel` (perfil/auth UI) — protocolo `AccountSessionManaging`.
- `Services/CatchLog/CatchSyncService` (+ seam `CatchSynchronizing`) — sync idempotente del registro.
- `Services/Account/SpotRepositorySpotPresenting` (+ seam `FavoritesPresenting`) — favoritos por cuenta consumiendo `SpotRepository` de spot-discovery; no crea tabla/RPC propias.
- `Services/Account/ProfileRepository` (+ seam `ProfileManaging`).

## Out of Boundary
- Subida/moderación de spots; sync en tiempo real del mapa; datos regulatorios de especie; pago.

## Upstream / Downstream
- **Upstream**: `supabase-foundation` (auth/storage/db), `catch-log` (seam `CatchRepository`/`Catch` a sincronizar), `spot-discovery` (`SpotRepository` + favs).
- **Downstream**: ninguna por ahora; futuras features regulatorias podrían cruzar a perfil.

## Existing Spec Touchpoints
- **Adjacent**: `catch-log` (la sync extiende el seam `CatchRepository` sin reemplazarlo), `spot-discovery` (favoritos por cuenta), `supabase-foundation` (auth base consumida).
- **No modifica** el contrato de `CatchSaving` del escáner ni el CRUD local.

## Constraints
- iOS 17+, Swift, SwiftUI, XCTest; seams tras protocolos (inyección por doubles en tests); solo Supabase SDK; el registro local sigue siendo la fuente de verdad local con la sync como ruta adicional idempotente.
