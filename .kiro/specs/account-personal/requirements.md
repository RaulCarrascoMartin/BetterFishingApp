# Requirements Document

## Introduction
El pescador que cambia de móvil o reinstala la app pierde hoy su historial de capturas y, próximamente, sus spots favoritos; además la app no tiene noción de quién es el usuario. Hoy las capturas viven solo de forma local (registro CRUD mediante el seam `CatchRepository`/`CatchSaving` de catch-log, en `Application Support/Catches/`), no existe auth ni perfil, los favoritos de spots aún no existen y no hay forma de asociar el historial a una cuenta. Esta feature aporta una cuenta personal sobre la capa base de Supabase (`supabase-foundation`): registro/inicio/cierre de sesión con sesión persistente, perfil con nombre y avatar (storage), favoritos de spots por cuenta visibles en el mapa (consumiendo `SpotRepository` de spot-discovery sin acoplarse a su geometría) y sincronización del registro de capturas (subida local→cuenta, descarga cuenta→local y merge idempotente por `Catch.id`), preservando `CatchRepository` como la persistencia local que la sync complementa sin reemplazar.

## Boundary Context
- **In scope**: registro de cuenta (signUp), inicio de sesión (signIn), cierre de sesión (signOut); sesión persistente y restaurada al arrancar y estado de sesión observable y notificado; perfil del usuario autenticado con nombre editable y avatar subido a storage y recuperable en otros dispositivos; favoritos de spots asociados a la cuenta y visibles en el mapa; sincronización del registro de capturas (push local→cuenta, pull cuenta→local, merge idempotente por identificador de captura); acceso a la cuenta desde la navegación principal de la app.
- **Out of scope**: cuenta de pago; moderación ni rating de spots; subida de spots por usuarios (de spot-discovery); datos regulatorios por especie (talla/normativa); sincronización en tiempo real del mapa de spots; migración de datos de favoritos/capturas preexistentes desde otros formatos.
- **Adjacent expectations**: consume `supabase-foundation` (seams `SupabaseAuthProviding`, `SupabaseStoring`, `SupabaseDatabaseAccess`) sin modificar su contrato; preserva intacto el seam `CatchRepository`/`CatchSaving` de catch-log — la sync es una ruta adicional sobre el mismo registro local, que sigue siendo la fuente de verdad local; consume `SpotRepository` de spot-discovery para favoritos sin acoplarse a su geometría; no cambia los seams de `fish-species-identification`.

## Requirements

### Requirement 1: Registro e inicio de sesión de la cuenta
**Objective:** Como pescador, quiero crear mi cuenta e iniciar sesión con email y contraseña, para que mis favoritos y mi registro de capturas queden asociados a mí y me acompañen entre dispositivos.

#### Acceptance Criteria
1. When el usuario solicita registrarse con un email y una contraseña, the Account shall crear la cuenta y quedar autenticado con una sesión activa.
2. When el usuario inicia sesión con un email y una contraseña válidos de una cuenta existente, the Account shall establecer una sesión activa para ese usuario.
3. If las credenciales de inicio de sesión son incorrectas, then the Account shall informar del error tipado y no iniciar sesión.
4. If el registro falla (email ya registrado, contraseña no válida, red, configuración), then the Account shall informar del motivo distinguiéndolo y permanecer sin sesión activa.
5. While el registro o el inicio de sesión están en curso, the Account shall exponer un estado de carga e impedir envíos duplicados.
6. When el registro o el inicio de sesión tienen éxito, the Account shall reflejar la sesión activa en la interfaz de la app.

### Requirement 2: Sesión activa, restauración y cierre de sesión
**Objective:** Como pescador, quiero que la app recuerde mi sesión entre usos y poder cerrarla, para no volver a introducir mis credenciales cada vez y para desconectar mi cuenta cuando quiera.

#### Acceptance Criteria
1. When la app arranca con una sesión previamente iniciada, the Account shall restaurar dicha sesión sin volver a pedir credenciales.
2. While hay una sesión activa, the Account shall exponer el usuario actual y el estado autenticado para que la app lo consume.
3. When la sesión activa expira, the Account shall renovarla mediante el token de refresco y conservar al usuario autenticado.
4. When el usuario cierra la sesión, the Account shall terminar la sesión local y dejar de exponer los datos personales asociados a la cuenta.
5. When la sesión cambia (iniciada, restaurada, renovada, cerrada, expirada), the Account shall exponer la sesión aplicable después del cambio y notificarlo a la app.
6. If el cierre de sesión falla, then the Account shall informar del fallo y mantener al usuario autenticado.

### Requirement 3: Perfil personal con nombre y avatar
**Objective:** Como pescador autenticado, quiero tener un perfil con mi nombre y un avatar, para que mi cuenta sea reconocible y mi perfil me acompañe en cualquier dispositivo.

#### Acceptance Criteria
1. When hay una sesión activa, the Account shall exponer el perfil del usuario (identificador, nombre y avatar) asociado a su cuenta.
2. When el usuario edita su nombre, the Account shall guardar el cambio en la cuenta y exponer el nombre actualizado.
3. When el usuario aporta una imagen de avatar, the Account shall subirla al storage de su cuenta y exponer el avatar actualizado.
4. When el usuario autenticado inicia sesión o reabre la app en cualquier dispositivo, the Account shall recuperar su perfil (nombre y avatar) desde la cuenta.
5. If el perfil asociado aún no tiene nombre o avatar definidos, then the Account shall exponer un nombre por defecto y ningún avatar.
6. If el guardado del nombre o la subida del avatar fallan, then the Account shall informar del fallo y conservar el valor anterior visible.

### Requirement 4: Favoritos de spots asociados a la cuenta
**Objective:** Como pescador autenticado, quiero guardar spots como favoritos en mi cuenta y verlos destacados en el mapa, para volver a mis sitios de pesca preferidos desde cualquier dispositivo.

#### Acceptance Criteria
1. When un spot está visible en el mapa y hay una sesión activa, the Account shall permitir marcarlo como favorito asociado a la cuenta.
2. When el usuario marca un spot como favorito, the Account shall persistir el favorito en la cuenta a través del seam `SpotRepository` de spot-discovery y exponerlo como favorito activo.
3. When el usuario desmarca un spot favorito, the Account shall eliminar el favorito de la cuenta a través del seam `SpotRepository` de spot-discovery y dejar de exponerlo como favorito.
4. When hay una sesión activa, the App shall destacar en el mapa los spots que son favoritos de la cuenta.
5. When el usuario autenticado reabre la app o inicia sesión en otro dispositivo, the Account shall recuperar sus favoritos desde la cuenta consumiendo el seam `SpotRepository` de spot-discovery.
6. While no hay sesión activa, the App shall no ofrecer marcar favoritos y comunicar que se requiere iniciar sesión.
7. If el guardado o la eliminación de un favorito falla, then the Account shall informar del fallo y conservar el estado previo del favorito.
8. The Account shall gestionar los favoritos consumiendo el seam `SpotRepository` de spot-discovery y sincronizándolos desde Supabase, sin depender de la geometría de los mismos.
9. The Account shall no definir tablas, RPC ni protocolos propios de favoritos: la persistencia y su autoría pertenecen a `spot-discovery` (`spot_favorites` + RPC de favoritos), que account-personal únicamente consume.

### Requirement 5: Sincronización del registro de capturas con la cuenta
**Objective:** Como pescador autenticado, quiero que mi registro de capturas se sincronice con mi cuenta, para que mi historial me acompañe entre dispositivos sin duplicarse ni perderse.

#### Acceptance Criteria
1. When hay una sesión activa y existen capturas locales sin sincronizar, the Account shall subirlas a la cuenta asociándolas al usuario.
2. When hay capturas en la cuenta que no existen en el registro local (reinstalación u otro dispositivo), the Account shall descargarlas al registro local.
3. When una captura se sincroniza y ya existe en el destino con el mismo identificador, the Account shall no duplicarla, integrando ambos lados de forma idempotente por `Catch.id`.
4. When una misma captura existe en local y en la cuenta con el mismo identificador pero contenidos distintos, the Account shall conservar la variante identificada como más reciente.
5. If el push o el pull falla por red o por servidor, then the Account shall conservar intacto el registro local, no perder las capturas ya sincronizadas y permitir reintentar la sincronización.
6. Where la sincronización está activa, the Account shall preservar el registro local como fuente de verdad local, tratando la sincronización como una ruta adicional que no reemplaza la persistencia local.
7. When el usuario borra una captura localmente y había una copia en la cuenta, the Account shall no volver a descargarla en una sincronización posterior.
8. When una sincronización completa termina con éxito, the Account shall reflejar en la cuenta todas las capturas del registro local y en el registro local todas las capturas de la cuenta que no estén borradas localmente, para las sincronizaciones realizadas.

### Requirement 6: Acceso a la cuenta desde la navegación principal
**Objective:** Como pescador, quiero acceder a mi cuenta desde la navegación principal de la app, para gestionar perfil, favoritos y la sincronización del registro en un solo lugar.

#### Acceptance Criteria
1. The App shall ofrecer acceso a la cuenta desde la navegación principal.
2. While no hay sesión activa, the App shall mostrar en la vista de cuenta una pantalla que invite a registrarse o iniciar sesión.
3. While hay una sesión activa, the App shall mostrar en la vista de cuenta el perfil (nombre y avatar), el acceso a los favoritos y un control para iniciar la sincronización del registro.
4. When el usuario solicita sincronizar desde la vista de cuenta, the App shall ejecutar la sincronización del registro con la cuenta y exponer el resultado (éxito o fallo) al usuario.
5. When el usuario cierra sesión desde la vista de cuenta, the App shall dejar de mostrar los datos personales y volver a la pantalla de registro o inicio de sesión.