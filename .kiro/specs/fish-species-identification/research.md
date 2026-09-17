# Research & Design Decisions

## Summary
- **Feature**: fish-species-identification
- **Discovery Scope**: New Feature (greenfield — sin código previo)
- **Key Findings**:
  - Fishial.ai expone API REST pública v2 de identificación de peces por imagen (865 especies, clasificador V10), con autenticación JWT de 10 min y envío de imagen como cuerpo binario raw (no multipart).
  - iOS 17+ ofrece patrones nativos sin dependencias externas: cámara AVFoundation + `UIViewRepresentable`, `PhotosPicker` (sin permiso), networking `URLSession` + async/await y ViewModels `@Observable`.
  - El guardado de capturas es seam de borde: la persistencia real pertenece a la capability de Registro de capturas; aquí solo se define el protocolo `CatchSaving` para entregar la especie pre-rellena.

## Research Log

### API Fishial.ai (proveedor de identificación)
- **Context**: El steering referencia Fishial.ai como API de identificación de especies; había que verificar contrato, autenticación y límites antes de diseñar el cliente.
- **Sources Consultated**: https://docs.fishial.ai/api (api_reference, getting_started, api_tutorial, example_scripts, specieslist), https://github.com/fishial/devapi, https://fishial.ai, https://portal.fishial.ai
- **Findings**:
  - Base URL `https://api-recognition.fishial.ai`; endpoints `POST /v2/auth` y `POST /v2/recognize`; feedback opcional `POST /v2/feedback` con `queryToken`.
  - Auth: `client_id` + `client_secret` → JWT Bearer con TTL 600 s; token vencido devuelve HTTP 401 `auth_token_expired`.
  - Reconocimiento: imagen como body binario raw con `Content-Type: image/jpeg|png|webp|gif|heic|heif|avif|tiff|svg+xml|octet-stream`. Máx. 20 MB (413), mín. 32×32 px (422 `image_dimensions`). Headers opcionales como `Fishial-Location-Lat-Lon`.
  - Respuesta JSON: `{ ok, queryToken, objects: [{ bbox, shape, species: [{ id, certainty }] }], definitions: { UUID: { commonName, scientificName, imageUrl } } }`. Sin coincidencia = HTTP 200 con `objects: []` (no es error). `certainty` 0.0–1.0 (>0.80 alta, <0.30 baja).
  - `commonName` llega en inglés; `scientificName` en latín.
  - Errores: JSON `{ ok:false, error, message }`; 401 auth, 413 tamaño, 415 formato, 422 dimensiones, `credits_insufficient`. Algunos 4xx/5xx del edge pueden devolver HTML/plain text.
  - Pricing: plan gratuito para testing + suscripción por créditos; tarifas y rate limits no públicos.
- **Implications**: Cliente con caché y refresh de token; preparación de imagen (resize + JPEG) para mantenerse muy por debajo de 20 MB; decodificado tolerante a respuestas no JSON; umbral de confianza propio para decidir "fiable / baja / sin coincidencia".
- **Alternatives rejected**: iNaturalist (no devuelve bboxes ni está orientada a pesca), Google Vision (no clasifica especie), AWS Rekognition/Nyckel (requieren entrenamiento o cobertura menor), Fishbrain (sin API pública). Rejected también la adopción del fallback Core ML offline (fuera de alcance de esta spec).

### iOS 17: cámara, galería, permisos y networking
- **Context**: Validar los patrones nativos SwiftUI para el flujo cámara/galería e integración HTTP.
- **Sources Consultated**: Documentación Apple (AVCaptureDevice, PhotosPicker, @Observable/observation), WWDC23 (10107, 10149), guías de community (createwithswift, avanderlee, swiftcrafted).
- **Findings**:
  - Cámara: no hay vista declarativa; patrón estándar AVFoundation (`AVCaptureSession` + `AVCapturePhotoOutput`) expuesto con `UIViewRepresentable`, gestionado por un `@Observable` `@MainActor` CameraManager; sesión en DispatchQueue serial; `videoRotationAngle` en iOS 17; detener `stopRunning()` en `onDisappear`.
  - Galería: `PhotosPicker` (SwiftUI, iOS 16+) no requiere permiso de librería; cargar datos con `loadTransferable(type: Data.self)`.
  - Permisos: `NSCameraUsageDescription` obligatorio; solicitar en el momento de uso; si está denegado, guiar a Settings (`UIApplication.openSettingsURLString`).
  - Networking: `URLSession` + async/await es suficiente; no se necesita Alamofire. Para subidas pesadas, `upload(for:fromFile:)`.
  - ViewModels: `@Observable` macro (iOS 17), tracking por propiedad; ownership con `@State`.
  - Preparación de imagen: resize primero (máx. 1280 px) con `UIGraphicsImageRenderer`, luego `jpegData(compressionQuality: 0.7)`.
- **Implications**: Diseño 100 % con APIs nativas; `ImageCompressor` en Core; VM `@Observable`; sin dependencias de terceros.

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| MVVM por feature (steering) | Views + un ViewModel `@Observable` por feature que orquesta Services | Alineado con steering, testable | — | Seleccionado |
| Repositorio intermedio | Capa extra entre VM y FishialClient | Más desacoplamiento | Complejidad innecesaria para un solo proveedor | Rechazado (síntesis: simplificación) |
| Embryo offline Core ML | Modelo local YOLO/DinoV2 vía coremltools | Sin coste por llamada | Mantenimiento, scope, decisión de proveedor sin cerrar | Diferido como no-goal |

## Design Decisions

### Decision: Adoptar Fishial.ai como proveedor de identificación
- **Context**: La app necesita identificar la especie a partir de una foto.
- **Alternatives Considered**:
  1. Fishial.ai — API SaaS especializada en peces, bboxes + candidatas + `certainty`. Seleccionada.
  2. iNaturalist — gratis, pero sin bboxes y orientado a biodiversidad.
  3. Modelo propio / Custom Labels — coste y entrenamiento; fuera de alcance.
- **Selected Approach**: Consumir `POST /v2/recognize` tras auth `POST /v2/auth`, detrás del protocolo `FishIdentifying`.
- **Rationale**: Única API pública madura y especializada en clasificar la especie exacta de pez, consistente con el steering.
- **Trade-offs**: Precio y rate limits no públicos; `commonName` en inglés; tolerancia de errores no JSON.
- **Follow-up**: Confirmar con el vendor el plan de pago y SLA antes de producción.

### Decision: Seam `CatchSaving` sin impl. de persistencia
- **Context**: Req 4 exige guardar la captura identificada con la especie pre-rellena, pero la persistencia pertenece a la capability de Registro de capturas.
- **Alternatives Considered**:
  1. Implementar aquí la persistencia completa — invade el borde de otra capability. Rechazado.
  2. Definir un protocolo y entregar el draft al flujo de capturas. Seleccionado.
- **Selected Approach**: `CatchSaving` es un protocolo inyectado; el composition root registra una implementación provisional que cumple los criterios de aceptación (draft con especie + foto). El Registro de capturas lo implementará de verdad.
- **Rationale**: Mantiene el borde limpio sin absorber trabajo ajeno.
- **Trade-offs**: Durante esta spec la persistencia real queda pendiente; riesgo bajo porque es seam explícito con revalidación.
- **Follow-up**: Revalidar el contrato cuando se genere la spec de Registro de capturas.

### Decision: Cámara AVFoundation + PhotosPicker, sin librerías externas
- **Context**: Need flujo de cámara y galería.
- **Alternatives Considered**: `UIImagePickerController` (UI fija) vs AVFoundation custom (seleccionado); Alamofire vs URLSession (seleccionado este último).
- **Selected Approach**: `CameraManager` `@Observable` con AVFoundation + `UIViewRepresentable`; `PhotosPicker` para galería; `URLSession.async/await` para red; `ImageCompressor` en Core.
- **Rationale**: APIs nativas, iOS 17+, sin dependencias nuevas; control total de la UI del escáner.
- **Trade-offs**: Más código de cámara que `UIImagePickerController`, a cambio de UX dedicada.
- **Follow-up**: Verificar permisos y comportamiento de `stopRunning()` en vistas efímeras.

## Risks & Mitigations
- Coste/rate limits de Fishial.ai opacos — Mitigación: plan gratuito en staging; confirmar suscripción antes de producción; protocolo `FishIdentifying` permite cambiar de proveedor.
- Respuestas de error no JSON en el edge (HTML/plain) — Mitigación: cliente tolerante que parsea texto y presenta error genérico.
- Identificación no fiable (objects vacío / certainty baja) — Mitigación: umbral propio de confianza (fiable ≥ 0.55; baja 0.30–0.55) y reencuadre del contrato de Req 3. Revalidar con vuelo real.
- Guardado de captura depende de capability inexistente — Mitigación: seam `CatchSaving` + implementación provisional; revalidación cuando exista Registro de capturas.

## References
- [Fishial.ai API reference](https://docs.fishial.ai/api/api_reference) — endpoint recognize y schema de respuesta
- [Fishial.ai Getting Started](https://docs.fishial.ai/api/getting_started) — auth y blunt de imagen
- [fishial/devapi](https://github.com/fishial/devapi) — clientes y ejemplos oficiales
- [Apple AVCaptureDevice.requestAccess](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:))
- [WWDC23: PhotosPicker & camera](https://developer.apple.com/videos/play/wwdc2023/10107/)
- [Apple: Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)