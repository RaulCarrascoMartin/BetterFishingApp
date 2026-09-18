# Requirements Document

## Introduction
El pescador identifica la especie desde el escáner y quiere llevar un registro personal de sus capturas. Hoy el guardado desde la identificación es un borrador provisional y aislado (sin historial), de modo que no hay forma de consultar, corregir ni eliminar las capturas pasadas. Esta feature aporta un registro de capturas local con historial: las capturas guardadas desde el escáner pasan directamente a un registro consultable, con sus datos (especie, foto, fecha/hora, ubicación opcional y notas), edición de fecha/hora, ubicación y notas, y borrado con confirmación. Los borradores guardados por la versión anterior se adoptan al registro en la primera actualización.

## Boundary Context (Optional)
- **In scope**: guardado de la captura identificada directamente en el registro al confirmarlo desde el escáner; historial de capturas persistente entre sesiones; consulta de detalle; edición de fecha/hora, ubicación y notas; borrado con confirmación; registro de la ubicación del dispositivo en el momento del guardado (con permiso) y su corrección manual; acceso al registro desde la navegación principal de la app; migración única de los borradores de la versión anterior.
- **Out of scope**: sincronización con la nube ni cuenta de usuario (capability "Cuenta personal"); mapa de spots de pesca; información regulatoria/descriptiva de especies; re-identificar una foto guardada ni sustituir la foto de una captura; editar la especie o la foto de una captura existente.
- **Adjacent expectations**: el escáner (spec `fish-species-identification`) sigue entregando la especie identificada y la foto al guardar; esta feature sustituye al guardado provisional de la versión anterior y migra sus borradores; al cambiar el proveedor de guardado del escáner, la spec de identificación se revalidará.

## Requirements

### Requirement 1: Guardado de una captura desde la identificación
**Objective:** Como pescador, quiero guardar la captura identificada desde el escáner directamente en mi registro, para que quede en mi historial sin pasos extra.

#### Acceptance Criteria
1. When the user confirma el guardado desde el escáner con una especie identificada, the App shall almacenar la captura en el registro con la especie, la foto y la fecha/hora.
2. When el usuario guarda desde el escáner y no se ha decidido aún el permiso de ubicación, the App shall solicitar el permiso de ubicación en ese momento.
3. When es la primera captura con permiso de ubicación concedido, the App shall registrar la ubicación del dispositivo en el momento del guardado.
4. If el permiso de ubicación está denegado o la ubicación no está disponible, then the App shall guardar la captura sin ubicación.
5. If el guardado de la captura falla, then the App shall informar del fallo y permitir reintentar conservando la especie identificada en pantalla.
6. When el guardado tiene éxito, the App shall confirmar el éxito y permitir volver al inicio.
7. When una captura se ha guardado, the App shall mostrarla en el historial del registro.

### Requirement 2: Historial de capturas
**Objective:** Como pescador, quiero ver todas mis capturas en un listado, para revisar mi registro a lo largo del tiempo.

#### Acceptance Criteria
1. The App shall mostrar el listado de capturas ordenado de más reciente a más antigua.
2. When el registro no tiene capturas, the App shall mostrar un estado vacío e invitar a guardar la primera captura desde el escáner.
3. The App shall conservar las capturas del registro entre sesiones de uso.
4. When el usuario selecciona una captura del listado, the App shall mostrar su detalle.
5. When una captura se edita o se añade, the App shall reflejar el cambio en el listado sin reiniciar la app.

### Requirement 3: Detalle y edición de una captura
**Objective:** Como pescador, quiero consultar y corregir los datos de una captura, para que el registro refleje correctamente lo que capturé.

#### Acceptance Criteria
1. When el usuario abre una captura, the App shall mostrar la especie (nombre común y científico), la foto, la fecha/hora, la ubicación y las notas.
2. When el usuario edita una captura, the App shall permitirle modificar la fecha/hora, la ubicación y las notas.
3. The App shall impedir modificar la especie y la foto de una captura existente.
4. When el usuario confirma la edición, the App shall guardar los cambios y mostrarlos en el detalle y en el historial.
5. When el usuario cancela la edición, the App shall descartar los cambios sin modificar la captura.

### Requirement 4: Borrado de una captura
**Objective:** Como pescador, quiero eliminar una captura de mi registro, para que el historial conserve solo lo que quiero guardar.

#### Acceptance Criteria
1. When el usuario solicita borrar una captura, the App shall pedir confirmación antes de eliminarla.
2. When el usuario confirma el borrado, the App shall eliminar la captura y dejar de mostrarla en el historial.
3. If el borrado de la captura falla, then the App shall informar del fallo y conservar la captura en el registro.

### Requirement 5: Migración de borradores existentes
**Objective:** Como usuario que ya guardó capturas con la versión anterior, quiero conservarlas en el nuevo registro, para no perder mi historial anterior.

#### Acceptance Criteria
1. When la app arranca y existen borradores sin migrar de la versión anterior, the App shall convertirlos en capturas del registro conservando la especie, la foto y la fecha, una única vez.
2. Where un borrador sin migrar no puede recuperarse por datos incompletos, the App shall omitirlo sin impedir el arranque ni el uso del registro.
3. The App shall no volver a migrar los borradores ya migrados en sesiones posteriores.

### Requirement 6: Acceso al registro desde la app
**Objective:** Como pescador, quiero alternar entre identificar un pez y revisar mi registro, para que ambos usos estén al alcance en la navegación principal.

#### Acceptance Criteria
1. The App shall ofrecer acceso al escáner de identificación y al historial de capturas desde la navegación principal.
2. When el usuario cambia del escáner al historial y viceversa, the App shall conservar el estado de la pantalla de que procede.