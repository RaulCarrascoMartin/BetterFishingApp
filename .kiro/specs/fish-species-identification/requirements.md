# Requirements Document

## Introduction
Los pescadores capturan peces que no reconocen y no tienen forma inmediata de saber qué especie es. Actualmente necesitan recurrir a guías físicas, libros o búsquedas manuales en foros, un proceso lento y poco fiable, especialmente para pescadores sin experiencia. Debería poder identificarse la especie al instante usando la cámara del móvil, mediante un sistema de reconocimiento visual por IA que responda qué especie se ha capturado sin depender de guías ni búsquedas manuales.

## Boundary Context
- **In scope**: fotografía del pez desde cámara o galería; identificación de la especie; avisos cuando no hay resultado fiable; guardado de la captura identificada con la especie pre-rellena; estados de carga y tiempo de respuesta en segundos.
- **Out of scope**: información asociada a la especie (características, normativa, talla mínima, temporada) — corresponde a la capability de información de especie; el registro completo de capturas (historial, edición, sincronización) — corresponde a la capability de registro de capturas; detección de múltiples especies en una misma foto.
- **Adjacent expectations**: la capability de registro de capturas se encarga de la persistencia y el historial; esta spec solo exige que el guardado iniciado desde la identificación arrastre la especie identificada. La capability de información de especie se encargará de los datos regulatorios y descriptivos.

## Requirements

### Requirement 1: Captura y selección de imagen
**Objective:** Como pescador, quiero aportar una foto del pez, desde la cámara o desde el carrete, para poder identificar la especie.

#### Acceptance Criteria
1. When the user inicia un escaneo de pez, the App shall ofrecer capturar una foto con la cámara o seleccionar una imagen de la galería.
2. When the user captura una foto con la cámara, the App shall usar esa imagen para la identificación.
3. When the user selecciona una imagen de la galería, the App shall usar la imagen seleccionada para la identificación.
4. If the user cancela la captura o la selección de imagen, the App shall volver al estado anterior sin iniciar una identificación.
5. If la App no dispone de permiso para usar la cámara o la galería, the App shall informar al usuario de cómo habilitarlo.

### Requirement 2: Identificación de la especie
**Objective:** Como pescador, quiero identificar la especie del pez a partir de la foto para saber qué he capturado.

#### Acceptance Criteria
1. When la imagen está lista para identificar, the App shall iniciar la identificación de la especie.
2. When la identificación produce una especie con confianza suficiente, the App shall mostrar el nombre de la especie identificada.
3. The App shall presentar una única especie como resultado de cada imagen.

### Requirement 3: Resultados no fiables y errores
**Objective:** Como pescador, quiero saber con claridad cuándo la identificación no es fiable para decidir reintentar con otra foto.

#### Acceptance Criteria
1. If la identificación no produce ninguna coincidencia, the App shall mostrar un aviso de que no se ha podido identificar la especie.
2. If la identificación devuelve una especie con confianza baja, the App shall avisar de que el resultado puede no ser fiable.
3. When no hay un resultado fiable, the App shall ofrecer al usuario reintentar con otra foto.
4. If se produce un error durante la identificación, the App shall mostrar un mensaje de error y permitir reintentar.

### Requirement 4: Guardado de la captura identificada
**Objective:** Como pescador, quiero guardar la captura identificada para llevarla a mi registro de capturas.

#### Acceptance Criteria
1. When la identificación ha mostrado una especie y el usuario solicita guardar la captura, the App shall pre-rellenar el registro de captura con la especie identificada.
2. If el guardado de la captura falla, the App shall informar al usuario del fallo y permitirle reintentarlo.

### Requirement 5: Tiempo de respuesta y estados de carga
**Objective:** Como pescador, quiero saber que la identificación está en proceso y recibir el resultado sin esperas largas.

#### Acceptance Criteria
1. When la identificación está en curso, the App shall mostrar un estado de carga visible al usuario.
2. The App shall presentar el resultado de la identificación, o el aviso de no-coincidencia, en cuestión de segundos desde que se inicia.
3. While el resultado no está disponible, the App shall permitir al usuario cancelar la identificación y volver al estado anterior.