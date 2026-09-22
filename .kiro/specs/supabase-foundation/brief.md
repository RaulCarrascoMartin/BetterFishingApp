# Brief: supabase-foundation

## Problem
El producto requiere backend (Supabase: auth, Postgres+PostGIS, storage) para spots, favoritos y sync del registro, pero hoy no existe ninguna capa de datos compartida: cada feature crea su propio saver/repositorio local y las credenciales viven sueltas en xcconfig. Sin una capa base, spots y cuenta acoplarían cada una su propio cliente Supabase, duplicando auth/storage y violando la dirección de dependencias de la arquitectura (un solo seam de red).

## Current State
- `fish-species-identification` y `catch-log` están implementadas y validadas (GO) con persistencia local y seams tras protocolos (`CatchSaving`, `CatchRepository`, `FishIdentifying`).
- No hay cliente de red compartido ni auth; `tech.md` declara Supabase (Postgres+PostGIS, Auth, Storage) como backend gestionado.
- Credenciales de Fishial en xcconfig (gitignored); no existe aún infra al cual apuntar para Supabase.

## Desired Outcome
- Un cliente Supabase base inyectable tras protocolos (`SupabaseAuthProviding`, `SupabaseDatabaseAccess`, `SupabaseStoring`) con una instancia compartida creada en el composition root.
- Auth (signUp/signIn/signOut/session) y storage (upload/download) funcionales, testeados con doubles; sin acoplar la capa base a ninguna feature concreta.
- Modelos `Codable` comunes y configuración centralizada (URL/anon key desde xcconfig), consumibles por spots y cuenta.

## Approach
Cliente Supabase Swift SDK único alojado en `App/Services/Supabase/` detrás de protocolos, exponiendo seams de auth y storage; el composition root construye la instancia real y la inyecta. Es la capa sobre la que viven spots-discovery y account-personal.

## Scope
- **In**: protocolos `SupabaseAuthProviding` / `SupabaseStoring` / `SupabaseDatabaseAccess`; cliente real `SupabaseClient` (URL + anon key desde xcconfig); tipos de sesión/usuario `Codable`; auth funcional y storage base; fake en test target.
- **Out**: por qué concreto (SQL DDL, PostGIS, tablas de spots/registro) — lo definen las specs consumidoras; pantallas de login (es de account-personal); sync del registro (según downstream); migración de datos.

## Boundary Candidates
- `Services/Supabase/SupabaseClientProvider`
- `Services/Supabase/SupabaseAuthService`
- `Services/Supabase/SupabaseStorageService`
- `Models/Supabase/` (Session, SupabaseUser)

## Out of Boundary
- Pantallas/flujo de login y perfil (account-personal).
- Esquema/DDL de tablas de spots o capturas (specs consumidoras).
- Descubrimiento de spots o mapa (spot-discovery).
- Sincronización del historial (account-personal).

## Upstream / Downstream
- **Upstream**: ninguna (spec base). Consume credenciales de xcconfig (patrón existente).
- **Downstream**: `spot-discovery` (reads de spots vía PostGIS), `account-personal` (auth de usuario, favoritos, sync del registro). Ambas dependen de esta capa base.

## Existing Spec Touchpoints
- **Adjacent**: `fish-species-identification` (seam `FishIdentifying`), `catch-log` (seam `CatchRepository`). La capa base no cambia sus protocolos, pero `account-personal` acabará conectando `CatchRepository` a Supabase.

## Constraints
- iOS 17+, SwiftUI, Swift 6, XCTest; sin librerías nuevas fuera del Supabase Swift SDK (ya planificado en tech.md).
- Credenciales fuera del repo (xcconfig gitignored); URL/anon key consumidas desde build settings, nunca hardcodeadas.
