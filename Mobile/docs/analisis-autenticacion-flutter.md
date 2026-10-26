# Análisis de autenticación para Flutter

Este documento orienta al equipo que migra el acceso de AgroFusion en la
issue #4, **[EDT 1.3] Migrar autenticación de React Native a Flutter**.
Registra los flujos existentes, el contrato de Laravel y los bloques de
implementación. Corresponde a la primera actividad de análisis de la issue.

## Identificar las fuentes del flujo existente

Las fuentes que intervienen en la autenticación son:

| Componente | Fuente | Comportamiento observado |
| --- | --- | --- |
| Entrada React Native | [App.js](../../Web/agrofusion-mobile/App.js) | Muestra carga al restaurar la sesión; elige navegación pública o autenticada según el usuario en memoria. |
| Estado de sesión | [AuthContext.js](../../Web/agrofusion-mobile/src/context/AuthContext.js) | Implementa login, registro, restauración, actualización del usuario y logout. Guarda `auth_token` y `user_data` en AsyncStorage. |
| Login | [LoginScreen.js](../../Web/agrofusion-mobile/src/screens/auth/LoginScreen.js) | Envía correo y contraseña; permite mostrar la contraseña, bloquea envíos durante la carga y presenta errores. |
| Registro | [RegisterScreen.js](../../Web/agrofusion-mobile/src/screens/auth/RegisterScreen.js) | Captura datos personales, confirmación de contraseña y rol deseado; presenta un mensaje de solicitud enviada. |
| Navegación pública | [AuthNavigator.js](../../Web/agrofusion-mobile/src/navigation/AuthNavigator.js) | Registra login, registro y presentación de la plataforma. |
| Peticiones | [client.js](../../Web/agrofusion-mobile/src/api/client.js) | Envía JSON, agrega Bearer desde AsyncStorage y elimina credenciales ante un 401. Las cuatro llamadas de autenticación utilizan el mismo cliente. |
| Backend | [AuthController API](../../Web/app/Http/Controllers/Api/AuthController.php) y [rutas API](../../Web/routes/api.php) | Valida credenciales, registra cuentas pendientes, emite y revoca tokens de Sanctum. |
| Estado de cuenta | [CuentaEstado](../../Web/app/Support/CuentaEstado.php) | Autoriza una cuenta activa y aprobada; acepta el estado heredado `null` como aprobado. |

El modo de demostración está desactivado en
[designMode.js](../../Web/agrofusion-mobile/src/constants/designMode.js).
Los tokens `demo-*` pertenecen a las vistas de diseño; la migración de acceso
debe comprobarse con la autenticación real de Laravel.

## Seguir los flujos de React Native

### Inicio de sesión

La pantalla comprueba campos vacíos, recorta el correo y envía `email` y
`password` a `POST /api/login`. El contexto guarda el token y el usuario
recibidos en AsyncStorage y actualiza la navegación. Los errores se presentan
mediante el normalizador de mensajes del cliente.

### Registro pendiente de aprobación

El formulario compara las contraseñas y envía sus campos a `POST /api/register`
sin transformarlos en `authApi.register`. Después de una respuesta exitosa,
presenta el aviso de revisión administrativa y vuelve a la pantalla anterior.
El registro no inicia sesión.

Hay una incompatibilidad entre este formulario y el endpoint existente:

- Laravel exige `nombreusuario`; React Native no lo captura ni lo envía.
- React Native envía `ci_nit`, `rol_deseado` y `carta_motivacion`, pero este
  endpoint no procesa esos campos. El registro web tiene un contrato distinto.
- La API asigna el rol `agricultor` y el estado `pendiente` desde el servidor.
  El selector de roles de React Native no modifica esa asignación.
- La etiqueta de contraseña indica ocho caracteres; la regla de este
  endpoint es `min:6`.

La pantalla Flutter debe solicitar los campos que procesa la API, incluido
`nombreusuario`, y presentar los errores de Laravel. Debe conservar la
asignación de rol del servidor y el proceso de aprobación. Copiar el formulario
sin adaptar su envío reproduciría el error de registro.

### Restauración de sesión

Al arrancar, React Native recupera token y usuario de AsyncStorage. Si ambos
existen, consulta `GET /api/me` y reemplaza el usuario guardado por la respuesta
del servidor. Si falla la consulta, elimina las credenciales, incluso si el
fallo es de conexión. La aplicación mantiene el indicador de carga durante
este proceso.

### Cierre de sesión

El contexto intenta `POST /api/logout` con el token real. Después elimina
token y usuario locales aunque la petición falle, y vuelve a la navegación
pública. El servidor revoca el token utilizado cuando recibe y procesa
correctamente el logout.

## Conservar el contrato de Laravel

Las rutas relativas parten de una URL base que incluye `/api`. Envía
`Accept: application/json` para recibir mensajes y errores por campo.

| Método y ruta | Entrada | Respuesta y regla |
| --- | --- | --- |
| `POST /api/login` | `email`, `password`. | `200` con `{user, token}`. Credenciales incorrectas: `401`; cuenta pendiente o inactiva: `403`. |
| `POST /api/register` | `nombre`, `apellido`, `email`, `nombreusuario`, `password`; `telefono` opcional. | `201` con `{message, user}`, cuenta pendiente y sin token. Los errores de validación producen `422`. |
| `GET /api/me` | Token Bearer. | `200` con el perfil en la raíz, roles, permisos efectivos y capacidades. Token no válido: `401`; cuenta no autorizada: `403`. |
| `POST /api/logout` | Token Bearer. | `200` con `message`; elimina el token de acceso utilizado. |

El registro también admite `imagenurl` e `informacionadicional` opcionales.
La migración de autenticación utilizará los datos necesarios para crear la
solicitud; la edición de fotografía y perfil corresponde a la issue #5.

El campo `user` de login no sustituye el contrato de `GET /api/me`.
Utiliza la consulta autenticada para recuperar el perfil y sus permisos.
El formato completo está en el
[contrato de perfil para Flutter](../../Web/docs/api-perfil-flutter.md).

## Reutilizar la base Flutter

La base de EDT 1.2 ya proporciona los siguientes componentes:

| Componente | Uso en la migración |
| --- | --- |
| [ApiClient](../lib/services/api_client.dart) | Centraliza URL, JSON, Bearer, timeout y errores. Login y registro usan `authenticated: false`; `me` y logout usan autenticación. |
| [SessionStorage](../lib/services/session_storage.dart) | Guarda únicamente el token mediante `flutter_secure_storage`; se reutiliza para inicio, restauración y cierre de sesión. |
| [ApiException](../lib/models/api_exception.dart) | Entrega estado HTTP, mensaje y errores de validación por campo. |
| [AppLoading](../lib/widgets/app_loading.dart) y [AppErrorState](../lib/widgets/app_error_state.dart) | Presentan carga, error y reintento. |
| [AgroFusionApp](../lib/app.dart) y [AppRoutes](../lib/navigation/app_routes.dart) | Son los puntos para incorporar la selección de navegación según el estado de autenticación. |

El cliente ya limpia el token ante un `401` de una petición autenticada y lo
conserva ante errores de red o `403`. El controlador de autenticación debe
coordinar esa respuesta con el usuario en memoria y la navegación.

La implementación debe seguir estas decisiones:

- Compartir un servicio de autenticación y un estado observable de Flutter
  entre las pantallas; mantener las peticiones fuera de los widgets.
- Guardar el token mediante `SessionStorage` y recuperar el perfil desde
  Laravel. No guardar la contraseña ni usar los datos locales como prueba
  suficiente de una sesión autorizada.
- Presentar login y registro como operaciones públicas; un `201` de registro
  informa de una solicitud pendiente y no habilita las pantallas protegidas.
- Mostrar los mensajes de `403` del login y bloquear el acceso. En la
  restauración, un `401` o `403` de `me` impide recuperar la sesión.
- Distinguir un fallo de red de credenciales no válidas. Durante la
  restauración, conservar el token ante fallos de conexión, bloquear la zona
  protegida y permitir reintentar la comprobación.
- Limpiar la sesión local al cerrar sesión y comunicar si un fallo de red
  impide confirmar la revocación en el servidor.
- Mantener la validación de negocio y los permisos en Laravel; utilizar la
  validación de campos del cliente para orientar al usuario y presentar
  los errores `422` recibidos del servidor.

La navegación específica por permisos y la pantalla de perfil se incorporan
en la issue #5. Este bloque prepara el acceso autenticado que las necesita.

## Registrar la comprobación del registro

Se contrastaron tres casos mediante solicitudes al kernel HTTP de Laravel,
con datos ficticios, entorno `testing`, SQLite `:memory:` y el rol de prueba
`agricultor` preparado:

| Caso | Resultado observado |
| --- | --- |
| Enviar los campos del formulario React Native sin `nombreusuario`. | `422`, con `errors.nombreusuario`: `El campo nombreusuario es obligatorio.` |
| Agregar `nombreusuario` a ese envío. | `201`, estado `pendiente`, rol `agricultor` y ausencia de token. |
| Intentar login con la cuenta pendiente y su contraseña correcta. | `403`: `Tu cuenta está pendiente de aprobación por un administrador.` No se emite ningún token. |

Las tres comprobaciones coincidieron con el controlador inspeccionado.
La prueba existente
[ApiPerfilFlujoTest](../../Web/tests/Feature/ApiPerfilFlujoTest.php) también
cubre login autorizado, consulta autenticada y revocación mediante logout.

## Dividir la migración en commits revisables

Los bloques propuestos acompañan cada funcionalidad con sus pruebas:

| Bloque | Resultado del commit | Casilla de la issue |
| --- | --- | --- |
| 1 | Análisis de flujos, incompatibilidades y contrato existente. | Analizar inicio de sesión, registro y cierre de sesión. |
| 2 | Login Flutter integrado con Laravel y base del estado de sesión. | Migrar inicio de sesión. |
| 3 | Registro adaptado a la API y tratamiento de solicitud pendiente. | Migrar registro; manejar cuentas pendientes y mensajes. |
| 4 | Logout remoto y eliminación de credenciales locales. | Integrar cierre de sesión. |
| 5 | Restauración, protección de navegación y tratamiento de errores de comunicación. | Gestionar estados de autenticación y errores. |
| 6 | Verificación completa de login, registro, logout y accesos autorizados y denegados. | Ejecutar pruebas y verificar restricciones de acceso. |

El bloque 3 reúne dos casillas porque la respuesta exitosa del registro es
precisamente una cuenta pendiente. Las pruebas se incorporan con cada cambio;
el último bloque registra la comprobación del flujo completo.
