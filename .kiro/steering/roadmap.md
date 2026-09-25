# Roadmap

## Overview

App nativa iOS (Swift/SwiftUI, iOS 17+) cliente-servidor sobre **Supabase** (Postgres + PostGIS, Auth, Storage) e identificación de especies vía **Fishial.ai**. Ya entregadas y validadas: `fish-species-identification` (escáner + identificación de especies), `catch-log` (registro de capturas local CRUD + migración de borradores), `supabase-foundation` (capa base de Supabase tras protocolos), `spot-discovery` (mapa de spots con favoritos) y `account-personal` (cuenta, perfil, favoritos y sync). El roadmap no tiene specs pendientes.

## Approach Decision

- **Elegido**: Supabase como capa de datos/auth compartida tras protocolos, creada como spec base (`supabase-foundation`) consumida por el resto de features; mapa de spots con geometría PostGIS (semilla curada PostGIS en v1); favoritos y sync asociados a cuenta de usuario.
- **Por qué**: evita duplicar un cliente de Supabase en cada feature y establece un único seam de auth/storage; las consultas geográficas ("spots cerca de mí") requieren PostGIS.
- **Alternativas descartadas**: Supabase por feature (duplicación y seams inconsistentes), mapa comunitario desde v1 (moderación/rating fuera de alcance inicial), todo tras login (rompe el valor anónimo del mapa).

## Scope

- **In**: capa base de Supabase (auth, storage, cliente), descubrimiento de spots en mapa (semilla curada), favoritos y sincronización de capturas con cuenta personal.
- **Out**: moderación ni rating de spots, cuenta de pago, subida de spots por usuarios, datos regulatorios de especie (talla/normativa, pendiente de fuente).

## Constraints

- Supabase SDK Swift para auth/db/storage; MapKit + CoreLocation para mapa y ubicación; PostGIS/Postgres para geometría; iOS 17+; Supabase es una dependencia outbound compartida (espec base).
- El seam `CatchRepository`/`CatchSaving` de catch-log no cambia: la sync añade una ruta hacia Supabase sin reemplazar la persistencia local.

## Boundary Strategy

- **Por qué este split**: separar la infraestructura de cliente/back esta espec base permite que spots y cuenta la consuman sin acoplar; favors/sync dependen de auth pero no de la implementación de spots al revés.
- **Shared seams a vigilar**: `SupabaseAuthProviding`/`SupabaseStoring` (base) son consumidos por cuenta y spots; no deben filtrar el modelo de usuario fuera del boundary base. `CatchRepository` sigue siendo el seam de sincronización de capturas.

## Specs (dependency order)

- [x] supabase-foundation -- cliente Supabase (auth/storage/db) tras protocolos compartidos, seam base. Dependencies: none
- [x] spot-discovery -- mapa de spots en MapKit con geometría PostGIS (semilla curada), spots cerca de mí, favoritos con cuenta. Dependencies: supabase-foundation
- [x] account-personal -- cuenta de usuario, perfil, favoritos y sync del registro de capturas con Supabase. Dependencies: supabase-foundation, catch-log, spot-discovery
