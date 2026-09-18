# Research Log: catch-log

## Discovery Scope
Análisis de extensión: integrar un registro de capturas local reemplazando el guardado provisional existente. Se evaluaron patrones de persistencia, manejo de ubicación, migración y navegación por tabs.

## Investigations

### 1. Persistencia local (build vs. adopt)
- **Evaluación**: CoreData, SwiftData, y persistencia basada en archivos (JSON + JPEG en directorio).
- **Decisión**: Persistencia basada en archivos (JSON + JPEG). Razón: la spec anterior ya estableció el patrón con `LocalDraftCatchSaver` (escritura de ficheros JSON + JPEG en `Application Support/`); no hay necesidad de un ORM ni de un schema de Base de Datos para un registro personal local con campos simples. SwiftData estaría disponible en iOS 17+ pero añadiría complejidad innecesaria y un acoplamiento mayor al framework.
- **Fuentes**: Código existente de `LocalDraftCatchSaver` (patrón confirmado); steering `tech.md` (sin librerías nuevas).

### 2. Manejo de ubicación (build vs. adopt)
- **Evaluación**: CoreLocation directo vs. wrapper de terceros.
- **Decisión**: CoreLocation directo encapsulado en `DeviceLocationProvider` detrás de un protocolo. Razón: permiso de ubicación una sola vez (al guardar), sin necesidad de tracking continuo. Un wrapper de terceros sería peso innecesario; CoreLocation es un framework del sistema ampliamente estable.
- **Constraints**: iOS 17+, `CLLocationManager` con `async/await` (APIs de iOS 17).

### 3. Navegación por tabs (build vs. adopt)
- **Evaluación**: `TabView` nativo de SwiftUI.
- **Decisión**: `TabView` nativo. Conserva el estado de cada tab por defecto en iOS 17+, cumpliendo el requisito 6.2. No hay necesidad de un sistema de navegación personalizado.

### 4. Migración de borradores
- **Evaluación**: Migración en el arranque (antes de la UI) vs. migración lazy (al acceder al registro).
- **Decisión**: Migración en el arranque de forma asíncrona, sin bloquear la UI. Marker `.migrated` en `ProvisionalDrafts/` para no re-migrar. Borradores originales se conservan (no se borran).
- **Razón**: Simple, seguro, y alineado con el patrón de "primera ejecución" típico en iOS.

### 5. Separación de Concerns: CatchRepository vs. CatchSaving
- **Evaluación**: ¿Un solo tipo que implementa ambos, o separar?
- **Decisión**: `LocalFileCatchRepository` implementa tanto `CatchRepository` (CRUD completo) como `CatchSaving` (conformidad por extensión). El composition root inyecta la misma instancia como los dos protocolos. Razón: evita duplicar la lógica de persistencia; el seam `CatchSaving` es simplemente un caso simplificado del repositorio.

### 6. Carga de datos en listado vs. detalle
- **Evaluación**: ¿Cargar la foto completa en el listado, o solo metadatos?
- **Decisión**: Listado carga solo metadatos (species, date, notes); la foto se carga en el detalle. Razón: rendimiento y memoria; las fotos pueden ser grandes. El listado muestra un thumbnail (se puede optimizar cargando la foto reducida en una segunda fase).

## Design Decisions
- Persistencia JSON + JPEG en `Application Support/Catches/` detrás de `CatchRepository` (reemplazable por backend).
- `LocalFileCatchRepository` implementa `CatchSaving` (conformidad por extensión, sin duplicar lógica).
- `DeviceLocationProvider` detrás de protocolo `DeviceLocationProviding` para testeo con doubles.
- Migración con marker y conservación de borradores originales.
- `TabView` nativo con conservación de estado por tab.
- `LocationCoordinate2D` como struct Codable simple, no dependiente de CoreLocation en el modelo.

## Risks Identified
- **Riesgo**: Número elevado de capturas (> 1000) podría degradar el rendimiento del listado.
  - **Mitigación**: Carga de metadatos únicamente en el listado; posibilidad futura de paginación o base de datos si es necesario.
- **Riesgo**: Borradores con Species incompleta podrían fallar la decodificación durante la migración.
  - **Mitigación**: `ProvisionalDraftsMigrator` captura errores de decodificación y omite borradores corruptos (req 5.2).
- **Riesgo**: El usuario puede tener permiso de ubicación denegado permanentemente.
  - **Mitigación**: La captura se guarda sin ubicación; el usuario puede editar la ubicación manualmente en el detalle.
