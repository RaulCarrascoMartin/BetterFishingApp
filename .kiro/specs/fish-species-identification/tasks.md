# Implementation Plan

## 1. Foundation: esqueleto de app, configuración e infraestructura de pruebas
- [x] 1.1 Crear el proyecto iOS BetterFishing (SwiftUI, iOS 17+)
  - Crear el workspace/scheme del target `BetterFishing` y las carpetas feature-first según `structure.md`: `App/Features/FishScanner`, `App/Services/FishID`, `App/Core/Image`, `App/Models`, `App/Resources`.
  - Añadir una vista raíz placeholder (`BetterFishingApp`) que muestre una pantalla vacía navegable.
  - Observable: `xcodebuild -scheme BetterFishing build` compila el target con la vista raíz sin errores.
  - _Requirements: —_

- [x] 1.2 Configurar credenciales de Fishial y permiso de cámara
  - Añadir `NSCameraUsageDescription` al Info.plist del target con una justificación de uso de la cámara.
  - Preparar `.xcconfig` de entorno (Debug/Release) para `FISHIAL_CLIENT_ID` y `FISHIAL_CLIENT_SECRET`, con valores vacíos por defecto y excluidos del repositorio.
  - Observable: el build pasa, la clave de uso de cámara está presente en el Info.plist empaquetado y las credenciales no quedan en código fuente ni en git.
  - _Requirements: 1.5_

- [x] 1.3 Infraestructura de tests y doubles de red
  - Añadir el test target del app, un helper de URLSession mockeable compartido y utilidades de tests (directorios temporales de FileManager para pruebas de persistencia).
  - Observable: `xcodebuild test` ejecuta un test de humo que pasa y el helper de URLSession mockeable compila dentro del test target.
  - _Requirements: —_

## 2. Modelos de dominio y transporte
- [x] 2.1 (P) Crear el modelo de dominio `Species`
  - Definir `Species` como Codable/Identifiable/Hashable con `id`, `commonName`, `scientificName`, `localizedName` (opcional, nil por defecto) y `referenceImageURL` opcional.
  - Añadir test de codificación/igualdad.
  - Observable: test de `Species` en verde; el tipo compila y se usa como identidad canónica.
  - _Requirements: 2.2_
  - _Boundary: Models/Species_

- [x] 2.2 (P) Crear los DTOs de Fishial
  - Definir `FishialTokenResponse` (token_type, access_token) y `FishialRecognitionResponse` (ok, queryToken, objects, definitions) con sus subtipos `FishialObject`, `FishialSpeciesCandidate` y `FishialSpeciesDefinition`.
  - Decodificación JSON snake_case (`convertFromSnakeCase`); incluir casos: respuesta válida, `objects` vacío y definiciones incompletas.
  - Observable: tests de decodificación cubren los tres casos y pasan.
  - _Requirements: 2.2, 3.1_
  - _Boundary: Models/Fishial_

- [x] 2.3 Crear los tipos de resultado de identificación
  - Definir `IdentificationResult` (species, certainty, confidence), el enum `IdentificationConfidence` (reliable/low) y `IdentificationOutcome` (identified/noMatch), todos `Sendable`.
  - Observable: los tipos compilan y un test confirma la construcción de `identified` y `noMatch`.
  - _Requirements: 2.2, 3.1, 3.2_
  - _Boundary: Models/Fishial_

- [x] 2.4 Crear el modelo provisional `CatchDraft`
  - Definir `CatchDraft` (id, species: Species, photoPath, createdAt, status) y `CatchDraftStatus` (draft), ambos Codable/Sendable.
  - Observable: test en verde de codificación/decodificación del borrador completo con species embebida.
  - _Requirements: 4.1, 4.2_
  - _Boundary: Models/CatchDraft_

## 3. Servicio de identificación y seams
- [x] 3.1 Definir el protocolo `FishIdentifying`
  - Declarar `recognize(imageData: Data) async throws -> IdentificationOutcome` como único contrato del proveedor.
  - Añadir un fake de `FishIdentifying` en el test target (avanzado/fallo/noMatch programable).
  - Observable: el protocolo compila en el target del app y el fake compila en el test target, sin acoplar a FishialClient.
  - _Requirements: 2.1, 2.2, 3.1, 3.2, 3.4_
  - _Boundary: Services/FishID/FishIdentifying_

- [x] 3.2 (P) Crear `FishialTokenStore`
  - Caché del JWT con expiración (TTL 600 s, margen de 60 s) y renovación perezosa vía `POST /v2/auth` con `client_id`/`client_secret`.
  - Evitar auths duplicados en concurrencia (serialización de la renovación); loguear (os.Logger) cada renovación y sus fallos.
  - Observable: test en verde que verifica token vigente reutilizado, token vencido renovado y una sola llamada de auth bajo uso concurrente.
  - _Requirements: 3.4, 5.2_
  - _Boundary: Services/FishID/FishialTokenStore_

- [x] 3.3 Implementar `FishialClient` (conformante a `FishIdentifying`)
  - Centralizar la base URL `https://api-recognition.fishial.ai` y los endpoints `/v2/auth` y `/v2/recognize` en un punto de configuración único consumido por `FishialClient` y `FishialTokenStore`.
  - Llamar `POST /v2/recognize` con la imagen como body binario y `Content-Type: image/jpeg` + `Authorization: Bearer`; timeout de request 15 s.
  - Mapear `objects`/`definitions` a `Species` (primera candidata del mejor objeto → única especie; `localizedName` nil), clasificar confianza (>=0.55 fiable, 0.30..<0.55 baja) y `objects` vacío o certainty <0.30 → `noMatch`.
  - Reintento único ante HTTP 401 (renovar token y repetir); tolerar respuestas no JSON del edge mapeándolas a error genérico.
  - Loguear (os.Logger) resultados de recognize (fiable/baja/noMatch), timeouts y respuestas no JSON.
  - Observable: tests con URLSession mockeada cubren éxito 200, 401+renovación+reintento, 413/415/422 → error, y respuesta HTML/plain → error genérico sin crash.
  - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.4, 5.2_
  - _Boundary: Services/FishID/FishialClient_

- [x] 3.4 Definir el protocolo seam `CatchSaving`
  - Declarar `saveDraft(species: Species, photoData: Data) async throws` como único contrato del guardado.
  - Añadir un fake de `CatchSaving` (éxito y fallo programables) en el test target.
  - Observable: el protocolo compila, el fake compila en el test target y ambos son consumibles por el ViewModel.
  - _Requirements: 4.1, 4.2_
  - _Boundary: Services/FishID/CatchSaving_

## 4. Utilidad Core de imagen
- [x] 4.1 (P) Crear `ImageCompressor`
  - Resize manteniendo aspect ratio (máx 1280 px) con `UIGraphicsImageRenderer` y compresión `jpegData(0.7)`; garantizar salida JPEG inferior a 20 MB; error tipado si no se puede procesar.
  - Observable: test sobre una imagen de gran tamaño confirma dimensión <= 1280 px y tamaño de datos en rango seguro; el error de procesamiento se eleva sin crash.
  - _Requirements: 2.1_
  - _Boundary: Core/Image/ImageCompressor_

## 5. Cámara y galería
- [x] 5.1 (P) Crear `CameraManager`
  - Sesión `AVCaptureSession` + `AVCapturePhotoOutput`, configuración en cola serial y `startRunning/stopRunning` controlados; captura async que devuelve los datos de la foto.
  - Solicitar permiso en el momento de uso y exponer estado `cameraAccessDenied` para guiar a Ajustes.
  - Observable: tests de permisos (autorizado/denegado) y de captura devolviendo datos JPEG; `stopRunning()` se invoca con la sesión detenida.
  - _Requirements: 1.2, 1.5_
  - _Boundary: Features/FishScanner/CameraManager_

- [x] 5.2 Crear `CameraView` (preview de cámara)
  - `UIViewRepresentable` con `layerClass` override que expone la sesión del `CameraManager` como preview.
  - Observable: la vista compila en el target, renderiza la preview en un preview de SwiftUI y expone la sesión del `CameraManager`; al desaparecer, la sesión se detiene.
  - _Requirements: 1.2_
  - _Boundary: Features/FishScanner/CameraView_

- [x] 5.3 (P) Crear `PhotoPickerView`
  - Wrapper de `PhotosPicker` (matching `.images`) que carga los datos con `loadTransferable(type: Data.self)` y entrega la imagen o notifica cancelación.
  - Observable: seleccionar una imagen de la galería entrega los datos a la vista; cancelar no inicia identificación (test unitario del callback).
  - _Requirements: 1.3, 1.4_
  - _Boundary: Features/FishScanner/PhotoPickerView_

## 6. ViewModel de orquestación
- [x] 6.1 Implementar la máquina de estados del escaneo en `FishScannerViewModel`
  - Estados `idle`, `imageReady`, `identifying`, `identified(IdentificationResult)`, `noMatch` y `failed(message)`; auto-inicio al quedar imagen lista; cancelación desde `identifying` vuelve a `idle`; `retryWithAnotherPhoto` vuelve a `idle`.
  - Preparar la imagen con `ImageCompressor` antes de llamar a `FishIdentifying`; aplicar estado de carga mientras se identifica.
  - Observable: tests de transiciones (imageReady→identifying→identified/noMatch/failed, cancelación en curso, retry) con un fake de `FishIdentifying` y del compresor.
  - _Requirements: 1.4, 2.1, 2.2, 3.1, 3.2, 3.3, 3.4, 5.1, 5.2, 5.3_
  - _Boundary: Features/FishScanner/FishScannerViewModel_

- [x] 6.2 Implementar el flujo de guardado de captura
  - Estados `saving/saved/saveFailed`; `saveCapturedCatch()` solo disponible con especie identificada, entrega species + foto comprimida a `CatchSaving` y traduce fallos a `saveFailed` con reintento.
  - Observable: test confirma que guardar con éxito pasa a `saved`, que un fallo pasa a `saveFailed` conservando la especie en pantalla, y que no se puede guardar sin identificación.
  - _Requirements: 4.1, 4.2_
  - _Boundary: Features/FishScanner/FishScannerViewModel_

## 7. Vista del escáner
- [x] 7.1 Construir `FishScannerView` y sus estados
  - Mostrar opciones cámara/galería en `idle`; estado de carga durante `identifying`; resultado con nombre de la especie; avisos de no-match y de confianza baja; botones de reintento y cancelación desde el procesamiento.
  - Guiar al usuario a Ajustes cuando el permiso de cámara está denegado (estado de 5.1).
  - Observable: cada estado del ViewModel se renderiza en la UI (verificable por render/hit-testing en previews y UI tests); cancelar la identificación vuelve al selector de fuente.
  - _Requirements: 1.1, 1.3, 1.4, 2.2, 3.3, 5.1, 5.3_
  - _Boundary: Features/FishScanner/FishScannerView_

- [x] 7.2 Añadir la confirmación de guardado y sus errores
  - Mostrar confirmación de guardar la captura con la especie pre-rellena; en `saveFailed` mostrar mensaje accionable con opción de reintentar; en `saved` confirmar el éxito y volver al inicio.
  - Observable: UI test de confirmación y de error/reintento de guardado con el estado del ViewModel.
  - _Requirements: 4.1, 4.2, 3.3_
  - _Boundary: Features/FishScanner/FishScannerView_

## 8. Guardado provisional e integración
- [x] 8.1 Implementar `LocalDraftCatchSaver` (provisional de `CatchSaving`)
  - Persistir en `Application Support/ProvisionalDrafts/` el JPEG (`<uuid>.jpg`) y el `CatchDraft` JSON (`<uuid>.json`) con la especie pre-rellena; escritura atómica (write + rename) y propagación de `CatchSaveError` ante fallo.
  - Observable: test de integración con FileManager (directorio temporal) confirma relectura del draft con la especie correcta y que un fallo de escritura propaga el error.
  - _Requirements: 4.1, 4.2_
  - _Boundary: Services/FishID/LocalDraftCatchSaver_

- [x] 8.2 Integrar en el composition root de la app
  - Construir e inyectar `FishialClient` (credenciales de 1.2 y base URL de 3.3) como `FishIdentifying` y `LocalDraftCatchSaver` como `CatchSaving`; presentar `FishScannerView` con su ViewModel en la app.
  - Habilitar la inyección de doubles por launch-arguments para los UI tests (el composition root permite sustituir `FishIdentifying`/`CatchSaving` por fakes al arrancar la app de test).
  - Observable: un smoke test/`xcodebuild` confirma que el flujo completo compila y arranca; un UI test de humo con doubles vía launch-arguments pasa.
  - _Requirements: 1.1, 3.4, 4.1, 5.1_
  - _Boundary: Composition Root_

## 9. Validación E2E
- [x] 9.1 E2E cámara → identificado
  - Con permiso concedido (stub) y fake de `FishIdentifying`, capturar foto, ver estado de carga y resultado con el nombre de la especie.
  - Observable: UI test en verde cubriendo 1.2, 2.2 y 5.1.
  - _Requirements: 1.2, 2.2, 5.1_
  - _Boundary: Features/FishScanner_

- [x] 9.2 E2E galería → confianza baja
  - Seleccionar imagen de galería con fake que devuelve certainty baja y verificar que se muestra la especie con el aviso de fiabilidad.
  - Observable: UI test en verde cubriendo 1.3 y 3.2.
  - _Requirements: 1.3, 3.2_
  - _Boundary: Features/FishScanner_

- [x] 9.3 E2E sin coincidencia → reintento
  - Fake que devuelve `noMatch`; verificar aviso de no identificado y que el reintento vuelve al selector de fuente para una nueva imagen.
  - Observable: UI test en verde cubriendo 3.1 y 3.3.
  - _Requirements: 3.1, 3.3_
  - _Boundary: Features/FishScanner_

- [ ] 9.4 E2E guardado con éxito y con fallo
  - Con `CatchSaving` real (provisional) y con un fake que lanza error, verificar confirmación de guardado con especie pre-rellena y el mensaje de error con reintento respectivamente.
  - Observable: UI tests en verde cubriendo 4.1 y 4.2.
  - _Requirements: 4.1, 4.2_
  - _Boundary: Features/FishScanner, Services/FishID/LocalDraftCatchSaver_

## Implementation Notes
- Sin equipo de desarrollo configurado en el repo, el target deshabilita la firma de código (`CODE_SIGNING_ALLOWED=NO` en Debug/Release) para que `xcodebuild -scheme BetterFishing build` compile en un checkout limpio; para desplegar en dispositivo habrá que seleccionar un equipo y reactivar la firma.
- `xcode-select` del sistema apunta a CommandLineTools: usar `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` antepuesto a `xcodebuild` si `xcodebuild` no encuentra Xcode.
- El proyecto Xcode (BetterFishing.xcodeproj + scheme compartido) se creó a mano (sin XcodeGen); los grupos vacíos (Features/FishScanner, Services/FishID, Core/Image, Models) llevan `.gitkeep` y no se añaden al proyecto hasta tener código real.
- Xcode 27 trata un `baseConfigurationReference` ausente como ERROR de build: `Debug.xcconfig`/`Release.xcconfig` están gitignored, así que un checkout limpio debe copiarlos desde las plantillas `.example` (App/Resources) antes del primer build.
- Las credenciales `FISHIAL_CLIENT_ID`/`FISHIAL_CLIENT_SECRET` viven en Debug/Release.xcconfig (vacíos por defecto). Tasks 3.3/8.2 deberán consumirlas vía build settings (p. ej. inyectarlas en el Info.plist generado con `INFOPLIST_KEY_*` o leer de configuración), nunca desde código ni UserDefaults (design: Security).