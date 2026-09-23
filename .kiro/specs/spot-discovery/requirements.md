# Requirements Document

## Introduction
El pescador no tiene ninguna forma de descubrir buenos sitios donde pescar: hoy la app solo le permite identificar especies y registrar capturas localmente (features «fish-species-identification» y «catch-log», ambas validadas GO). No existe mapa ni spots, la capa base «supabase-foundation» aún no está construida (precedente en el roadmap) y las capacidades de ubicación del dispositivo no alimentan todavía ningún flujo de descubrimiento. Esta feature entrega un mapa de spots curados visibles sin necesidad de cuenta, la capacidad de ver los spots más cercanos a la ubicación del usuario ordenados por distancia, el detalle básico de cada spot al seleccionarlo, y favoritos asociados a la cuenta. Todo el acceso a spots y favoritos pasa por una capa de datos remota consumida tras un repositorio de spots inyectable, de modo que la futura feature de cuenta pueda reutilizar los favoritos y que los tests puedan sustituir el repositorio por dobles.

## Boundary Context
- **In scope**: mapa con spots curados (semilla curada) mostrados como anotaciones, accesible sin sesión; «spots cerca de mí» ordenados por distancia desde la ubicación del usuario; selección de un spot con detalle básico; favoritos asociados a la cuenta (requieren autenticación; sin flujo de login propio); repositorio de spots tras un protocolo inyectable y sustituible por dobles; modelos comunes de spot y categoría; pestaña «Mapa» en la navegación raíz de la app.
- **Out of scope**: subida de spots por los usuarios, moderación, rating y cuenta de pago; datos regulatorios de especie (talla/normativa) asociados a spots; flujo de login, registro o perfil (spec «account-personal»); sincronización del registro de capturas (spec «account-personal»); persistencia local de spots o favoritos en el dispositivo; cambio de los seams existentes del registro de capturas ni de la identificación de especies.
- **Adjacent expectations**: la feature consume la capa base «supabase-foundation» (acceso a base de datos y autenticación) sin exponer los tipos internos de la plataforma de autenticación; si la capa base no está disponible (sin credenciales de servicio configuradas), el mapa degrada de forma clara sin romper el arranque de la app; la ubicación del dispositivo se obtiene reutilizando la capacidad compartida de localización existente; la feature «account-personal» reutilizará el mismo repositorio de spots para los favoritos.

## Requirements

### Requirement 1: Mapa de spots curados con anotaciones
**Objective:** Como pescador, quiero ver en un mapa los spots curados disponibles sin necesidad de cuenta, para descubrir dónde puedo pescar y planear mi salida.

#### Acceptance Criteria
1. When la aplicación muestra la pestaña de mapa, la aplicación shall cargar y mostrar como anotaciones en el mapa los spots curados disponibles para la región visible.
2. When el usuario desplaza o agranda el mapa, la aplicación shall actualizar las anotaciones para reflejar la región visible actual.
3. While la aplicación está cargando los spots, la aplicación shall mostrar un indicador de carga.
4. If la carga de spots falla, then la aplicación shall mostrar un estado de error que permita reintentar, en lugar de un mapa roto o sin datos.
5. The visualización del mapa shall funcionar sin exigir sesión de usuario ni permiso de ubicación.

### Requirement 2: Degradación sin capa de datos disponible
**Objective:** Como equipo de desarrollo, quiero que el mapa degrade de forma elegante cuando no hay acceso a la capa de datos, para que la app siga funcionando en entornos sin configuración.

#### Acceptance Criteria
1. When la aplicación arranca sin capa de datos disponible, la aplicación shall mostrar en la pestaña de mapa un estado claro de «no disponible» en lugar de bloquear el resto de la app.
2. If la carga de spots vuelve a estar disponible y el usuario vuelve a la pestaña de mapa, then la aplicación shall recuperar el funcionamiento normal del mapa.

### Requirement 3: Spots cerca de mí con distancia
**Objective:** Como pescador, quiero ver los spots de pesca cercanos a mi ubicación ordenados por distancia, para elegir el sitio más próximo al que ir.

#### Acceptance Criteria
1. When el usuario solicita los spots cercanos, la aplicación shall obtener la ubicación del dispositivo y mostrar los spots dentro del radio de búsqueda solicitado ordenados por distancia creciente.
2. When la aplicación muestra un spot cercano, la aplicación shall indicar la distancia de ese spot respecto a la ubicación del usuario.
3. If el permiso de ubicación está denegado o la ubicación del dispositivo no está disponible, then la aplicación shall mostrar un aviso claro del motivo y mantener el mapa utilizable.
4. If no hay spots dentro del radio solicitado, then la aplicación shall indicar al usuario que no hay spots cercanos.

### Requirement 4: Selección de un spot y detalle básico
**Objective:** Como pescador, quiero seleccionar un spot del mapa y ver su información básica, para decidir si merece la pena acercarme.

#### Acceptance Criteria
1. When el usuario selecciona una anotación del mapa, la aplicación shall mostrar el detalle del spot seleccionado.
2. The detalle del spot shall incluir, al menos, el nombre, la categoría, un resumen descriptivo y las coordenadas.
3. The acceso al detalle de un spot shall no exigir autenticación.

### Requirement 5: Favoritos asociados a la cuenta
**Objective:** Como pescador con cuenta, quiero marcar y consultar mis spots favoritos asociados a mi cuenta, para planear futuras salidas desde cualquier dispositivo.

#### Acceptance Criteria
1. When un usuario autenticado marca un spot como favorito, la aplicación shall guardar el favorito asociado a su cuenta.
2. When un usuario autenticado desmarca un spot de sus favoritos, la aplicación shall eliminar el favorito de su cuenta.
3. When un usuario autenticado ve un spot, la aplicación shall indicar si ese spot ya está entre sus favoritos.
4. While no hay un usuario autenticado, la aplicación shall no permitir marcar favoritos e indicará de forma clara que se requiere iniciar sesión, sin mostrar el flujo de cuenta.
5. When cambia el estado de la sesión del usuario, la aplicación shall actualizar el estado de favoritos según la cuenta activa.
6. The favoritos shall persistir asociados a la cuenta en el backend y no depender de un único dispositivo.

### Requirement 6: Repositorio de spots inyectable y modelos comunes
**Objective:** Como equipo de desarrollo, quiero que el acceso a spots y favoritos quede tras un repositorio inyectable con modelos comunes, para testear con dobles y permitir que la futura feature de cuenta reutilice los favoritos.

#### Acceptance Criteria
1. The acceso de la aplicación a los spots y a los favoritos shall estar expuesto tras un repositorio sustituible por un doble en los tests.
2. The modelos de spot y de categoría shall ser serializables y compartidos entre la app, los tests y los datos remotos, centralizando el mapeo de los datos de spots.
3. When la aplicación necesita comprobar la sesión para los favoritos, la aplicación shall consultar el estado de autenticación de la capa base sin exponer los tipos internos de la plataforma de autenticación.
4. The datos de spots y favoritos shall leerse y escribirse a través del servicio remoto de datos, sin persistencia local duplicada en el dispositivo para el descubrimiento.
5. The seams existentes del registro de capturas y de la identificación de especies shall no modificarse con esta feature.