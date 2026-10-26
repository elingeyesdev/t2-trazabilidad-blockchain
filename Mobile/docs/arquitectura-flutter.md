# Arquitectura base de Flutter

Este documento explica al equipo de desarrollo cómo incorporar funcionalidades
a `Mobile/` usando la base de la issue #3. El flujo de referencia es la
comprobación pública de conexión con Laravel. Incluye login y registro de
la issue #4; la navegación por permisos corresponde a la issue #5.

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
La restauración al arrancar y el cierre de sesión corresponden a los siguientes
bloques de la issue #4.

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

`ConnectionScreen` mantiene la petición en un `FutureBuilder`. La carga usa
`AppLoading`; un error usa `AppErrorState` y su acción de reintento. El servicio
interpreta el resultado con `ApiHealth`, de modo que una respuesta distinta
de `{"ok": true}` no se muestra como una conexión disponible.

## Reutilizar el cliente HTTP

`ApiClient.request` recibe el método, la ruta relativa, los parámetros de
consulta y un cuerpo JSON opcional. Usa el paquete
[`http`](https://pub.dev/packages/http) con una conexión compartida y timeout
de 30 segundos. No sigue redirecciones ni reintenta automáticamente peticiones
que podrían modificar datos.

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
El cliente no registra tokens ni contraseñas. El controlador de autenticación
de la issue #4 debe coordinar el usuario en memoria y la navegación cuando
una petición indique que la sesión dejó de ser válida.

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
   en las rutas de `AgroFusionApp`.
6. Prueba las respuestas del servicio y la navegación antes de registrar
   la funcionalidad como terminada.

Las pruebas automatizadas usan `MockClient` y el almacenamiento simulado del
paquete. Para verificar integración real, ejecuta la pantalla contra Laravel
según el [README](../README.md) y documenta la URL y el resultado observado.
