# Brief: catch-log

## Problem
El pescador identifica la especie desde el escáner y guarda la captura, pero el guardado actual es un borrador provisional (`LocalDraftCatchSaver` escribiendo en `Application Support/ProvisionalDrafts/`) sin historial: no hay forma de ver las capturas guardadas, editarlas ni borrarlas. El usuario necesita un registro personal de capturas que preserve la especie identificada y dé contexto (fecha, ubicación, notas) a lo largo del tiempo.

## Current State
- `fish-species-identification` ya está validada: el escáner entrega `species` + foto comprimida vía el seam `CatchSaving` (`saveDraft(species:photoData:)`).
- La implementación provisional `LocalDraftCatchSaver` persiste un `CatchDraft` JSON (`<uuid>.json`) + JPEG (`<uuid>.jpg`) en `Application Support/ProvisionalDrafts/`.
- `Species`, `CatchDraft` y los DTOs de Fishial viven en `App/Models`; la app arranca en `RootView` con el escáner como única pantalla (sin navegación a historial).

## Desired Outcome
- Un registro de capturas local con historial: listado, detalle, edición y borrado de capturas (especie, foto, fecha/hora, ubicación opcional, notas breves).
- El guardado iniciado desde el escáner escribe directamente en el registro real (el seam `CatchSaving` lo implementa el repositorio del registro), ya sin borrador provisional.
- Los `ProvisionalDrafts/` existentes se adoptan como capturas del registro (migración única al arrancar).
- El registro queda detrás de un protocolo (`CatchRepository`) reemplazable por backend en el futuro, sin tocar la UI.

## Approach
Persistencia local JSON en `Application Support/Catches/` detrás de un protocolo `CatchRepository` (save/get/list/update/delete), coherente con el `LocalDraftCatchSaver` existente y sin librerías nuevas. `CatchSaving` pasa a estar implementado por el repositorio real; `LocalDraftCatchSaver` se elimina. `RootView` pasa a un `TabView` (Identificar | Capturas). Migración única de `ProvisionalDrafts` al primer arranque.

## Scope
- **In**: modelo `Catch` definitivo; repositorio local (CRUD); UI historial + detalle + edición + borrado; migración de drafts; navegación por tabs; integración del seam `CatchSaving` con el registro real.
- **Out**: sincronización/backend (Supabase); multi-usuario; mapa de spots; información regulatoria por especie; reprocesar identificación de una foto guardada.

## Boundary Candidates
- `Catch` (modelo definitivo) en `App/Models` — depreca el provisional `CatchDraft`.
- `CatchRepository` (protocolo) + `LocalFileCatchRepository` (impl JSON) en `App/Services/CatchLog`.
- `CatchLogView`, `CatchDetailView` (detalle/edición), `CatchLogViewModel` en `App/Features/CatchLog`.
- Migrador `ProvisionalDraftsMigrator` (arranque -> adopta drafts).
- Composition root: `TabView` con las dos features e inyección del repositorio real como `CatchSaving`.

## Out of Boundary
- Sincronización a nube y cuenta de usuario (capability "Cuenta personal").
- Decisión de almacenamiento definitivo en Supabase (el protocolo lo permite; la impl backend es trabajo futuro).
- Datos de especie (normativa, talla mínima, temporada).

## Upstream / Downstream
- **Upstream**: `fish-species-identification` (apporta `Species`, seams `CatchSaving`/`FishIdentifying`, imagen comprimida). Cambiar el proveedor de `CatchSaving` y la dirección de dependencias dispara el Revalidation Trigger del design de esa spec.
- **Downstream**: "Cuenta personal" (sincronización de capturas) consumirá `CatchRepository`; "Información de especie" usará `Species`.

## Existing Spec Touchpoints
- **Extends**: ninguno (spec nueva). Toca el seam `CatchSaving` definido por `fish-species-identification`.
- **Adjacent**: `fish-species-identification` (revalidar 4.1/4.2/8.1/9.4 tras integrar el registro real); `LocalDraftCatchSaver` (a eliminar).

## Constraints
- iOS 17+, SwiftUI, Xcode 27 (Swift 6), XCTest, sin librerías de terceros nuevas.
- Credenciales y configuración de entorno sin cambios.
- Los tests E2E existentes del escáner (dobles DEBUG por launch-arguments) deben seguir pasando.