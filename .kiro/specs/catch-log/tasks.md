# Implementation Plan

## 1. Foundation: modelos, contratos y localización
- [x] 1.1 Crear el modelo definitivo `Catch` y `LocationCoordinate2D`
  - Definir `Catch` (id, species: Species, photoPath, date, location opcional, notes, createdAt) y `LocationCoordinate2D` (latitude, longitude) como Codable/Sendable/Identifiable.
  - Asegurar que `CatchDraft` provisional queda intacto para la migración de borradores existentes.
  - Observable: test en verde de round-trip Codable de una captura completa con especie, fecha, ubicación y notas.
  - _Requirements: 3.1_
  - _Boundary: Models_

- [x] 1.2 Declarar el protocolo `CatchRepository`
  - Definir el contrato CRUD: `saveCatch(species:photoData:date:location:notes:)` → `Catch`, `listCatches()` → `[Catch]`, `getCatch(id:)` → `Catch?`, `updateCatch(id:date:location:notes:)` y `deleteCatch(id:)`.
  - Añadir un fake de `CatchRepository` en el test target (éxito/fallo programables) consumible por los ViewModels.
  - Observable: el protocolo compila en el target del app y el fake compila en el test target, sin acoplar a la implementación concreta.
  - _Requirements: 1.1, 2.1, 3.1, 4.1_
  - _Boundary: Services/CatchLog/CatchRepository_

- [x] 1.3 Implementar el proveedor de ubicación del dispositivo
  - Encapsular CoreLocation detrás de un protocolo con `requestPermissionIfNeeded()` y `currentLocation() → LocationCoordinate2D?`.
  - Solicitar el permiso solo si aún no se ha decidido; obtener la coordenada actual con un timeout corto; devolver nil si el permiso está denegado o la ubicación no está disponible.
  - Observable: test en verde con un double del proveedor: permiso concedido devuelve coordenadas, permiso denegado devuelve nil, y el permiso no se vuelve a solicitar una vez decidido.
  - _Requirements: 1.2, 1.3, 1.4_
  - _Boundary: Core/Location/DeviceLocationProvider_

## 2. Core: repositorio local, guardado desde el escáner y migración
- [x] 2.1 Implementar el repositorio local de capturas
  - Persistir en `Application Support/Catches/` el JPEG (`<uuid>.jpg`) y el JSON de metadatos `Catch` (`<uuid>.json`) con escritura atómica.
  - Implementar save/list/get/update/delete; listar ordenado de más reciente a más antigua; borrar ambos ficheros asociados.
  - Observable: test de integración con directorio temporal confirma guardar → listar → obtener → actualizar → borrar y que la foto y los metadatos se releen iguales entre sesiones.
  - _Requirements: 1.1, 1.7, 2.1, 2.3, 3.1, 3.4, 4.2_
  - _Boundary: Services/CatchLog/LocalFileCatchRepository_

- [x] 2.2 Guardar desde el escáner directamente en el registro
  - _Depends: 1.3, 2.1_
  - Hacer que el repositorio real implemente el seam `CatchSaving`: `saveDraft(species:photoData:)` convierte al guardado del registro con la fecha actual, solicitando el permiso de ubicación en ese momento y registrando la coordenada si está concedida; guarda sin ubicación si el permiso está denegado o la ubicación no está disponible.
  - Observación: el fallo de escritura se propaga como `CatchSaveError` para que el escáner conserve la especie en pantalla y ofrezca reintento.
  - Observable: test de integración verifica que guardar desde el escáner crea la captura en el registro con la especie y la foto correctas, con y sin ubicación, y propaga el error ante fallo de escritura.
  - _Requirements: 1.1, 1.2, 1.3, 1.4_
  - _Boundary: Services/CatchLog/LocalFileCatchRepository_

- [x] 2.3 Migrar los borradores provisionales al registro
  - _Depends: 2.1_
  - Leer los borradores de `Application Support/ProvisionalDrafts/` (JSON `CatchDraft` + JPEG), convertirlos en capturas del registro conservando la especie, la foto y la fecha, y escribir un marker `.migrated` en el directorio.
  - Omitir borradores corruptos o con datos incompletos sin impedir el arranque; no re-migrar los borradores ya migrados en sesiones posteriores.
  - Observable: test de integración con directorio temporal confirma que los borradores se convierten una única vez, que los corruptos se omiten y que un segundo `migrateIfNeeded()` no duplica capturas.
  - _Requirements: 5.1, 5.2, 5.3_
  - _Boundary: Services/CatchLog/ProvisionalDraftsMigrator_

## 3. Core: detalle, edición y borrado de una captura
- [x] 3.1 (P) Modelar el flujo de detalle, edición y borrado
  - _Depends: 2.1_
  - Gestionar el modo vista/edición de una captura: editar fecha, ubicación y notas; cancelar la edición descartando cambios; confirmar y persistir los cambios; borrar con confirmación y traducir fallos a estados accionables.
  - Observable: tests del ViewModel verifican que editar guarda los cambios y el detalle se refleja, que cancelar no modifica la captura, que borrar elimina la captura y que un fallo de borrado conserva la captura e informa.
  - _Requirements: 3.2, 3.4, 3.5, 4.1, 4.2, 4.3_
  - _Boundary: Features/CatchLog/CatchDetailViewModel_

- [x] 3.2 Construir la vista de detalle y edición
  - _Depends: 3.1_
  - Mostrar la especie (nombre común y científico), la foto, la fecha/hora, la ubicación y las notas; modo edición con campos para fecha, ubicación y notas; especie y foto de solo lectura; borrado con diálogo de confirmación.
  - Observable: cada estado del ViewModel (vista, edición, confirmación de borrado, fallo) se renderiza en la UI; se verifica en UI test.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3_
  - _Boundary: Features/CatchLog/CatchDetailView_

## 4. Core: historial de capturas
- [x] 4.1 (P) Modelar el listado de capturas
  - _Depends: 2.1_
  - Cargar el listado del repositorio ordenado de más reciente a más antigua; exponer un estado vacío; refrescar el listado cuando llega una captura nueva o editada para reflejar el cambio sin reiniciar la app.
  - Observable: tests del ViewModel verifican el orden del listado, el estado vacío y que el listado se actualiza en vivo tras guardar o editar.
  - _Requirements: 1.7, 2.1, 2.3, 2.5_
  - _Boundary: Features/CatchLog/CatchLogViewModel_

- [x] 4.2 Construir la vista de historial
  - _Depends: 4.1, 3.2_
  - Listado con filas que muestran la foto (thumbnail), la especie y la fecha; estado vacío que invita a guardar la primera captura desde el escáner; navegación a la vista de detalle al seleccionar una captura.
  - Observable: un UI test verifica el listado con capturas, el estado vacío cuando no hay capturas y que seleccionar una captura navega al detalle.
  - _Requirements: 1.7, 2.1, 2.2, 2.4, 2.5_
  - _Boundary: Features/CatchLog/CatchLogView_

## 5. Integration: composition root y navegación
- [x] 5.1 Inyectar el repositorio real y sustituir el guardado provisional
  - Construir el repositorio local en el composition root e inyectarlo como `any CatchSaving` (escáner) y como `any CatchRepository` (registro); ejecutar la migración de borradores al arranque de forma asíncrona sin bloquear la UI.
  - Eliminar `LocalDraftCatchSaver` y sus tests obsoletos en el mismo cambio atómico (el repositorio real pasa a cumplir el rol); conservar `CatchDraft` únicamente para la migración.
  - Observable: `xcodebuild build` compila sin referencias al saver provisional; los borradores previos de `ProvisionalDrafts/` existen como capturas del registro al arrancar; el escáner guarda directamente en el registro real.
  - _Requirements: 1.1, 5.1_
  - _Boundary: Composition Root, Services/CatchLog, Services/FishID/LocalDraftCatchSaver_

- [x] 5.2 Convertir la navegación principal en tabs
  - Sustituir el `NavigationStack` raíz único por un `TabView` con dos tabs: Identificar y Capturas.
  - Observable: ambas features son accesibles desde la navegación principal y el estado de cada tab se conserva al alternar entre ellas.
  - _Requirements: 6.1, 6.2_
  - _Boundary: RootView_

## 6. Validation: E2E
- [x] 6.1 E2E guardado desde el escáner → aparece en el historial
  - Identificar con double → guardar → la captura aparece en el tab de capturas; verificar también el caso de fallo de guardado con reintento.
  - Observable: UI tests en verde.
  - _Requirements: 1.1, 1.5, 1.6, 1.7, 2.1_
  - _Boundary: Features/FishScanner, Features/CatchLog_

- [x] 6.2 E2E listado → detalle → edición
  - Navegar del listado a una captura, editar fecha/notas, guardar y verificar que el listado lo refleja; cancelar una edición y verificar que no cambia.
  - Observable: UI tests en verde.
  - _Requirements: 2.1, 2.4, 2.5, 3.1, 3.2, 3.4, 3.5_
  - _Boundary: Features/CatchLog_

- [x] 6.3 E2E borrado con confirmación
  - Solicitar borrar una captura, confirmar en el diálogo y verificar que desaparece del historial; verificar que un fallo de borrado conserva la captura.
  - Observable: UI tests en verde.
  - _Requirements: 4.1, 4.2, 4.3_
  - _Boundary: Features/CatchLog_

- [x] 6.4 E2E migración de borradores al primer arranque
  - Sembrar borradores en `ProvisionalDrafts/`, arrancar la app y verificar que aparecen como capturas del registro y que no se duplican en arranques posteriores.
  - Observable: UI/integration test en verde cubriendo la migración única.
  - _Requirements: 5.1, 5.2, 5.3_
  - _Boundary: Services/CatchLog/ProvisionalDraftsMigrator, Composition Root_

## Implementation Notes
- `CatchLogViewModel` (4.1) ordena de forma defensiva (`ordered(_:)`) los mismos criterios que el repositorio (date desc → createdAt desc → id) porque el fake de test devuelve el orden de un diccionario; el reviewer acepta el riesgo de deriva y lo registra. Tras un fallo de refresco, `catches` conserva datos obsoletos y `state == .loadFailed`: la vista (4.2) debe renderizar el estado de error ANTES que el `.loaded`/listado.
- Enmienda aprobada (OPTION A): el borrado con confirmación (Req 4.1, 4.2, 4.3; design.md:384) usa `.alert` en lugar de `.confirmationDialog`. Mismo título, mensaje y acciones (confirmar destructivo `detail.confirmDelete` / cancelar `detail.cancelDelete` con los mismos identificadores de accesibilidad). Razón: en los simuladores iOS 26/27 los taps sobre las acciones de un action-sheet no llegan a los gestos de SwiftUI, mientras que los alerts con botones con identificador de accesibilidad se han probado fiables en esta repo (suite de escáner). La semántica de confirmación previa al borrado se mantiene intacta para Req 4.1.
- La edición de ubicación en `CatchDetailView` (design.md:382) reserva el botón "Usar ubicación actual" sin implementar: la ubicación se edita únicamente mediante los campos manuales de latitud/longitud. `CatchDetailViewModel` no dispone de un seam de localización del dispositivo; el provider (Req 1.3) solo se usa en el guardado desde el escáner.
- El detalle renderizado en `.loaded` con `catchEntry == nil` se conserva: `loadedContainer` mantiene su guard (`speciesCommonName == nil` → `ContentUnavailableView`), ver nota previa sobre `cancel()`/`dismissError()`.
- En `CatchDetailViewModel` (3.1) `cancel()` o `dismissError()` desde un estado `loadFailed` dejan `.loaded` con `catchEntry == nil`; la vista (3.2) debe guardar el renderizado en `.loaded` para Req 3.1 (mostrar la foto) — el VM es seguro (accessors opcionales), pero la vista no debe asumir catch no-nil.
- Un fallo real de `saveCatch` a mitad de la migración (2.3) propaga el error y NO escribe el marker `.migrated`, por lo que un reintento posterior reconvertiría los válidos ya migrados → duplicados. Riesgo inherente al diseño aprobado; aceptado.
- El migrador (2.3) escribe el marker también si el directorio de borradores existe pero está vacío; design.md sugiere "directorio vacío → sin cambios", pero es inofensivo (hay `no-op` cuando el directorio no existe o el marker ya está).
- Los implementadores deben pegar el output real de la fase RED (fallo de compilación/test con la implementación ausente) en `RED_PHASE_OUTPUT`; el reviewer lo exige como evidencia y rechaza si falta (tarea 2.1). El patrón para regenerarlo: mover temporalmente el fichero de implementación, compilar los tests, restaurarlo.
- Xcode 27 trata un `baseConfigurationReference` ausente como ERROR de build: `Debug.xcconfig`/`Release.xcconfig` están gitignored, así que un checkout limpio debe copiarlos desde las plantillas `.example` (App/Resources) antes del primer build.
- `xcode-select` del sistema puede apuntar a CommandLineTools: usar `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` antepuesto a `xcodebuild` si no encuentra Xcode.
- Los tests de guardado existentes del escáner (`saveSucceeds`/`saveFails`) usan doubles vía launch-arguments; tras esta spec, la persistencia real con `LocalFileCatchRepository` queda cubierta por los tests de integración del repositorio (2.1, 2.2) y por los E2E (6.x).
- La ubicación se obtiene con doubles en los tests; en el simulador el permiso de ubicación se puede conceder/denegar por launch-arguments o fixture.
- Post-implementación (checklist de validación, no tarea): revalidar la spec adjunta `fish-species-identification` (4.1/4.2/8.1/9.4) tras el cambio de provider de `CatchSaving` y la eliminación de `LocalDraftCatchSaver`, confirmando que los UI tests de guardado siguen pasando con doubles y que el registro real queda verificado por los tests de integración de esta spec.