# Requirements Document

## Introduction
El equipo de desarrollo necesita una capa de datos compartida sobre Supabase (Auth, Postgres+PostGIS y Storage) para que las features `spot-discovery` y `account-personal` consuman backend sin duplicar cliente ni credenciales. Hoy no existe ninguna capa de datos compartida: `fish-species-identification` y `catch-log` están implementadas y validadas con persistencia local y seams propios (`CatchSaving`, `CatchRepository`, `FishIdentifying`), no hay cliente de red compartido ni auth, y las credenciales viven sueltas en xcconfig sin infraestructura de Supabase. Esta feature aporta un cliente Supabase base inyectable tras protocolos (`SupabaseAuthProviding`, `SupabaseStoring`, `SupabaseDatabaseAccess`), con una instancia compartida creada en el composition root, auth funcional (signUp/signIn/signOut/session) y storage base (upload/download), testeados con doubles, modelos `Codable` comunes y configuración centralizada. Es la capa sobre la que viven `spot-discovery` y `account-personal`, sin acoplar la capa base a ninguna feature concreta.

## Boundary Context
- **In scope**: cliente Supabase base como único punto de acceso de la app a Supabase; seams `SupabaseAuthProviding`, `SupabaseStoring` y `SupabaseDatabaseAccess`; auth funcional (registro, inicio de sesión, cierre de sesión, consulta de sesión/usuario); storage base (subir y descargar objetos); modelos comunes `Codable` de sesión y usuario; lectura de URL del proyecto y anon key desde la configuración de build (xcconfig gitignored); fake de los protocolos en el test target.
- **Out of scope**: esquema de base de datos concreto (DDL SQL, PostGIS, tablas de spots/capturas) que definen las specs consumidoras; pantallas o flujo de login/perfil (spec `account-personal`); descubrimiento de spots o mapa (spec `spot-discovery`); sincronización del registro de capturas (spec `account-personal`); migración de datos.
- **Adjacent expectations**: `account-personal` consumirá el seam de auth y conectará el registro a Supabase sin cambiar el seam `CatchRepository`/`CatchSaving` de `catch-log`; `spot-discovery` consumirá el seam `SupabaseStoring` y `SupabaseDatabaseAccess`; los seams base no deben filtrar el modelo de usuario de Supabase fuera de su boundary; los seams de las specs existentes (`CatchSaving`, `CatchRepository`, `FishIdentifying`) no cambian con esta capa.

## Requirements

### Requirement 1: Cliente Supabase base compartido tras protocolos
**Objective:** Como equipo de desarrollo, quiero que la app disponga de un único cliente de Supabase accesible tras protocolos, para que las features consumidoras se integren sin conocer la implementación ni duplicar la configuración.

#### Acceptance Criteria
1. When la app construye sus servicios base, the App shall crear una única instancia del cliente de Supabase y exponerla a las features tras los protocolos `SupabaseAuthProviding`, `SupabaseStoring` y `SupabaseDatabaseAccess`.
2. When una feature consumidora solicita auth, storage o base de datos, the App shall entregarle únicamente los protocolos correspondientes, sin exponerle tipos internos del cliente de Supabase.
3. The base layer shall constituir el único punto de acceso de la app a Supabase para auth, base de datos y storage.
4. The base layer shall no acoplarse a ninguna feature concreta de la app ni a sus modelos.

### Requirement 2: Configuración centralizada de credenciales
**Objective:** Como equipo de desarrollo, quiero que la URL del proyecto y la anon key se configuren fuera del código fuente, para no filtrar credenciales en el repositorio ni en la implementación.

#### Acceptance Criteria
1. When la app arranca, the App shall leer la URL del proyecto de Supabase y la anon key desde la configuración de build (xcconfig) y construir el cliente con esos valores.
2. If la URL del proyecto o la anon key no están configuradas o son inválidas, then the App shall no iniciar el cliente y registrar un error de configuración claro.
3. The App shall no contener en el código fuente la URL del proyecto ni la anon key en claro.
4. The repository shall no versionar los ficheros de configuración con credenciales reales; las plantillas versionadas shall no contener valores secreto.

### Requirement 3: Auth funcional de la capa base
**Objective:** Como equipo de desarrollo, quiero que la capa base gestione registro, inicio de sesión, cierre de sesión y consulta de sesión/usuario, para que `account-personal` construya encima el flujo de cuenta.

#### Acceptance Criteria
1. When se solicita registrar un usuario con email y contraseña, the AuthService shall crear el usuario y devolver la sesión resultante.
2. When se solicita iniciar sesión con credenciales de un usuario existente, the AuthService shall establecer una sesión y exponerla como consultable.
3. When se solicita cerrar sesión, the AuthService shall terminar la sesión local y el usuario deja de estar autenticado.
4. When existe una sesión activa, the AuthService shall permitir consultar el usuario y la sesión actuales.
5. When la app vuelve a arrancar tras una sesión iniciada, the AuthService shall restaurar la sesión guardada sin volver a pedir credenciales.
6. If una operación de autenticación falla, then the AuthService shall propagar un error tipado que distinga el motivo (credenciales inválidas, red, configuración).
7. The AuthService shall notificar a la app los cambios de estado de la sesión (nueva sesión, sesión restaurada, sesión cerrada).

### Requirement 4: Storage base de la capa base
**Objective:** Como equipo de desarrollo, quiero que la capa base suba y descargue objetos en buckets, para que spots y registro almacenen y recuperen fotos sin duplicar lógica.

#### Acceptance Criteria
1. When se solicita subir un objeto a un bucket indicando una ruta, the StorageService shall subirlo y devolver la referencia/ruta del objeto almacenado.
2. When se solicita descargar el objeto de una ruta de un bucket, the StorageService shall devolver los datos del objeto.
3. If el objeto solicitado no existe o la operación de storage falla, then the StorageService shall propagar un error tipado que distinga el motivo.
4. The StorageService shall permitir operar sobre buckets y rutas arbitrarias, sin asumir nombres de cubo propios de ninguna feature.

### Requirement 5: Acceso a base de datos tras protocolo
**Objective:** Como equipo de desarrollo, quiero que la capa base exponga un seam de acceso a la base de datos, para que `spot-discovery` y `account-personal` lean y escriban sus datos sin conocer la implementación.

#### Acceptance Criteria
1. When una feature consumidora necesita leer o escribir datos, the App shall exponerle el acceso a la base de datos de Supabase tras el protocolo `SupabaseDatabaseAccess`.
2. The base layer shall no definir el esquema de las tablas (DDL, PostGIS, tablas de spots ni capturas); ese esquema lo definen las specs consumidoras.
3. The base layer shall mantener el seam de base de datos agnóstico respecto al contenido y la forma de los datos de las features.

### Requirement 6: Modelos comunes Codable y boundary de usuario
**Objective:** Como equipo de desarrollo, quiero que la capa base defina tipos comunes de sesión y usuario, para que el mapeo JSON esté centralizado y el modelo de Supabase no fluya fuera de su boundary.

#### Acceptance Criteria
1. The base layer shall exponer tipos `Codable` y `Sendable` para la sesión (`SupabaseSession`) y el usuario (`SupabaseUser`) con los campos esenciales (identificador, email, fecha de creación y, en la sesión, los tokens de acceso y de refresco).
2. The base layer shall no filtrar fuera de su boundary los tipos de usuario del SDK de Supabase; las features consumidoras reciben únicamente los tipos comunes definidos por la capa base.
3. Where una feature consumidora es `spot-discovery` o `account-personal`, the base layer shall proveer únicamente los seams base, sin comportamiento propio de esas features.

### Requirement 7: Testeabilidad de la capa base con doubles
**Objective:** Como equipo de desarrollo, quiero que los protocolos base sean sustituibles por fakes en los tests, para verificar auth y storage sin red real y de forma aislada.

#### Acceptance Criteria
1. The test target shall incluir un fake que implemente los protocolos base con éxito y fallo programables, consumible por los tests de las features aguas abajo.
2. When los tests ejecutan flujos de auth con el fake, the test suite shall verificar el comportamiento sin contactar con la red.
3. When los tests ejecutan flujos de storage con el fake, the test suite shall verificar subida, descarga y errores sin contactar con la red.
4. The base layer shall exponer los protocolos de forma que permitan la sustitución por el fake sin modificar el código de la app.