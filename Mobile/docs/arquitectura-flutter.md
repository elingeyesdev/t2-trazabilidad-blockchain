# Arquitectura base de Flutter

Este documento explica al equipo de desarrollo cómo incorporar funcionalidades
a `Mobile/` usando la base de la issue #3. El flujo de referencia es la
comprobación pública de conexión con Laravel. Incluye los flujos de
autenticación de la issue #4 y la consulta del perfil de la issue #5.

## Seguir el flujo de una petición

La comprobación pública de conexión sigue este flujo:

```text
HomeScreen -> ruta /connection -> ConnectionScreen
                                      |
                               ApiHealthService
                                      |
                                  ApiClient
                                      |
                      API_BASE_URL + test-api
                                      |
                            ApiHealth.fromJson
```

`main.dart` inicializa Flutter y monta `AgroFusionApp`. La aplicación comparte
`SessionStorage` entre el cliente HTTP y el servicio de autenticación, crea
un solo `ApiClient` y libera su cliente y controlador cuando se desmonta.
Los tests pueden inyectar un cliente y almacenamiento propios; quien inyecta
el cliente debe cerrarlo.

El login sigue este flujo:

```text
LoginScreen -> AuthController -> AuthService -> POST /api/login
                                    |
                           SessionStorage.saveToken
                                    |
                               GET /api/me
                                    |
                           AuthUser -> HomeScreen
```

`AuthService` interpreta las respuestas de Laravel y valida el token y el
perfil. El usuario se confirma mediante `me` y debe coincidir con la identidad
devuelta por login. Si falla esa confirmación, el servicio limpia el token
recién guardado. `AuthController` comunica carga, error y usuario confirmado
mediante `ChangeNotifier`, sin añadir dependencias de gestión de estado.

La ruta raíz presenta `LoginScreen` mientras no exista un usuario confirmado.
El formulario conserva los campos ante errores, muestra los mensajes de
validación de Laravel y bloquea envíos duplicados. El acceso a la comprobación
pública de conexión se conserva desde login e inicio.
Al iniciar, `AgroFusionApp` ejecuta `AuthController.restoreSession`. Si no hay
token, presenta el login; si existe, `AuthService` consulta `GET /api/me` con
ese Bearer y valida el perfil antes de establecer al usuario. El servicio
comprueba además que el token guardado siga siendo el de la petición.

`AgroFusionApp` observa el ciclo de vida de Flutter y revalida una sesión
autenticada al volver al primer plano. `_sessionGate` presenta carga,
recuperación de errores o limpieza pendiente antes del contenido de cada ruta.
Las rutas protegidas usan `requiresAuthentication: true`, como el inicio,
para presentar login cuando no existe un usuario verificado.

Los fallos transitorios de restauración conservan el token y bloquean las
pantallas hasta reintentar o cerrar sesión. Un `401` o `403` de `me` limpia
las credenciales rechazadas; si falla el borrado, la aplicación mantiene la
recuperación del almacenamiento como requisito para continuar.

El registro usa la ruta `/register` y el mismo `AuthController` y `ApiClient`:

```text
LoginScreen -> RegisterScreen -> AuthController.register
                                         |
                                 AuthService.register
                                         |
                                 POST /api/register
                                         |
                                RegistrationResult
                                         |
                          Confirmación de cuenta pendiente
```

`RegistrationResult` representa el mensaje y correo de una solicitud pendiente;
es distinto de `AuthUser`. El servicio rechaza una respuesta que incluya un
token o no confirme el estado pendiente y no escribe en `SessionStorage`.
El controlador tampoco establece un usuario autenticado al registrar.

El formulario envía únicamente los campos de la API. Comprueba que estén
completos y que coincidan las contraseñas; los errores de validación de Laravel
se muestran por campo. Mientras envía, bloquea envíos duplicados y la salida
de esa ruta. Una confirmación válida limpia las contraseñas del formulario;
al volver al login, pasa el correo mediante el resultado de navegación.

El cierre de sesión parte de `HomeScreen` y utiliza `AuthController.logout`.
El controlador retira inmediatamente al usuario de la vista y presenta
`AppLoading` mientras `AuthService` intenta revocar el token y limpiar el
almacenamiento. El servicio devuelve `LogoutResult`, con los estados
`remoteClosed` y `localCleared`, para distinguir el resultado del servidor
del borrado local.

Si se limpió la sesión local, la ruta raíz muestra login con un mensaje del
resultado. Si el borrado falló, presenta `AppErrorState` y permite reintentar
el cierre; mientras tanto bloquea login y registro. Un error de red no se
presenta como confirmación de revocación remota. Un `401` de logout se trata
como una sesión que ya no es válida en el servidor.

`AuthService.logout` captura el token que se va a revocar y lo pasa a
`ApiClient` mediante `bearerToken`. La limpieza se ejecuta en `finally` y
compara el token guardado antes de borrarlo. Así, una petición anterior no
borra las credenciales que otro login haya reemplazado. Las peticiones con
`authenticated: false` ignoran un Bearer explícito y siguen siendo públicas.

`ConnectionScreen` mantiene la petición en un `FutureBuilder`. La carga usa
`AppLoading`; un error usa `AppErrorState` y su acción de reintento. El servicio
interpreta el resultado con `ApiHealth`, de modo que una respuesta distinta
de `{"ok": true}` no se muestra como una conexión disponible.

## Consultar y compartir el perfil

`HomeScreen` abre `/profile`, registrada con `requiresAuthentication: true`.
`ProfileScreen` solicita `AuthController.refreshProfile` al abrirse y mediante
la acción **Actualizar perfil**. Mientras consulta, oculta el contenido anterior
y deshabilita el reenvío. Reutiliza `AuthService.restoreSession` para obtener
el perfil con el token actual, verificar que no haya cambiado la sesión y
aplicar la limpieza existente si Laravel rechaza el acceso.

`AuthUser` conserva los campos del perfil, fechas, nombres de todos los roles,
permisos efectivos y capacidades de edición. Valida los tipos de los campos
recibidos, conserva CI/NIT como texto y no deriva permisos desde los roles.
Las listas obtenidas del JSON no permiten mutaciones posteriores.

La actualización sustituye el usuario compartido y notifica también al inicio.
Se rechaza una respuesta con el identificador de otra cuenta. Los fallos de
verificación reutilizan la recuperación global de sesión antes de permitir
mostrar el perfil. Una respuesta posterior al desmontaje del controlador no
actualiza al usuario.

La fotografía se representa desde `avatar_url`, sin usar el Bearer para su
descarga. El componente admite HTTP/HTTPS e imágenes raster embebidas y
presenta un icono si la URI o la imagen no son utilizables. No conserva copias
del perfil en el almacenamiento de sesión.

## Actualizar el perfil

`ProfileEditForm` usa las capacidades de `AuthUser` para ofrecer el cambio de
nombre y fotografía. `AuthController.updateProfile` bloquea operaciones
simultáneas, comprueba las capacidades disponibles y comunica el resultado.
`AuthService.updateProfile` envía únicamente nombre y/o foto, vincula la
petición al token utilizado y rechaza una respuesta de otra cuenta o sesión.
La respuesta completa sustituye el usuario compartido y sus capacidades.

`ProfilePhoto` conserva una copia de los bytes seleccionados, con límite de
2 MB, extensión permitida y nombre normalizado para el envío. El cliente no
envía rutas locales. Estas comprobaciones no sustituyen la validación de
imagen y autorización de Laravel.

El selector oficial `file_selector` entrega un `XFile`; el formulario usa
`length` y `readAsBytes` sin importar `dart:io`. La operación de selección
evita que la reanudación desde el diálogo del sistema descarte el formulario.
Después vuelve a consultar el perfil y conserva el borrador mientras verifica.

Los errores de validación conservan los datos introducidos. Un `403` de
escritura provoca una consulta de perfil, conservando el mensaje si la cuenta
sigue autorizada. Un resultado de escritura incierto marca el controlador
como pendiente de consulta y bloquea otras escrituras hasta verificarlo;
cerrar el formulario no elimina esa condición. Los `401` durante el guardado
reutilizan la invalidación global, incluido el bloqueo si falla la limpieza.

## Reutilizar el cliente HTTP

`ApiClient.request` recibe el método, la ruta relativa, los parámetros de
consulta y un cuerpo JSON opcional, o `fields` y `files` para multipart. No
combina un cuerpo JSON con un formulario multipart. Usa el paquete
[`http`](https://pub.dev/packages/http) con una conexión compartida y timeout
de 30 segundos. No sigue redirecciones ni reintenta automáticamente peticiones
que podrían modificar datos.

El multipart utiliza `AbortableMultipartRequest`; comparte el destino validado,
Bearer, timeout, cancelación, interpretación de errores y expiración de sesión
del JSON. El paquete genera el delimitador y `Content-Type` del formulario.

Las rutas se escriben sin `/` inicial y los parámetros se pasan mediante
`queryParameters`. `ApiConfig` rechaza URLs de destino externas y rutas que
salen del prefijo configurado, evitando enviar un token a otro servidor.

El comportamiento de sesión y errores es:

| Situación | Resultado |
| --- | --- |
| Petición autenticada, valor por defecto | Lee el token de `SessionStorage` y agrega Bearer si existe. |
| Petición con `authenticated: false` | No lee ni envía credenciales; sirve para login, registro y comprobación pública. |
| `401` de una petición que envió el token | Elimina ese token si sigue siendo el guardado y devuelve `ApiException`. |
| `401` público | Devuelve el error sin borrar una sesión existente. |
| `403` o `422` | Conserva el token y entrega el estado HTTP y los errores de validación disponibles. |
| Fallo de red, timeout o error del servidor | Conserva el token y muestra un mensaje controlado. |
| `204` o cuerpo exitoso vacío | Devuelve `null`. |
| JSON inválido en una respuesta exitosa | Devuelve un error controlado de formato. |

El almacenamiento nativo se configura mediante `flutter_secure_storage`.
El cliente no registra tokens ni contraseñas. `ApiClient.sessionExpired`
notifica un `401` autenticado que no corresponde a un token reemplazado.
El evento indica si pudo limpiar las credenciales. `AuthController` retira
al usuario en memoria y presenta login o recuperación de limpieza, según
ese resultado. Las operaciones de acceso tratan sus propios errores; el
aviso global se aplica a la sesión que ya está autenticada.

El controlador cancela la suscripción al desmontarse y `ApiClient.close`
cierra el flujo de eventos. Los errores públicos de login o registro y los
`403` de permisos de otros módulos no disparan una expiración global.

## Incorporar una funcionalidad

Para migrar una pantalla, sigue estos pasos:

1. Verifica su contrato en las rutas y controladores de Laravel.
2. Agrega a `lib/models/` los modelos que necesites para interpretar sus
   respuestas. Valida los campos recibidos antes de utilizarlos en la pantalla.
3. Crea el servicio del módulo en `lib/services/` y recibe el `ApiClient`
   compartido por constructor. Mantén las llamadas HTTP fuera de la pantalla.
4. Agrega la pantalla dentro de `lib/screens/` y reutiliza los estados de
   carga y error cuando correspondan.
5. Declara el nombre en `AppRoutes` y registra el constructor de la pantalla
   en las rutas de `AgroFusionApp`, mediante `_sessionGate`. Si necesita un
   usuario verificado, establece `requiresAuthentication: true`.
6. Prueba las respuestas del servicio y la navegación antes de registrar
   la funcionalidad como terminada.

Las pruebas automatizadas usan `MockClient` y el almacenamiento simulado del
paquete. Para verificar integración real, ejecuta la pantalla contra Laravel
según el [README](../README.md) y documenta la URL y el resultado observado.
La [verificación de autenticación](verificacion-autenticacion-laravel.md)
incluye un entorno aislado, los casos ejecutados y sus capturas.
