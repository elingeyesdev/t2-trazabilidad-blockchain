# Análisis de React Native para la base Flutter

Este documento orienta al equipo que prepara Flutter en `Mobile/` para la
issue #3, **[EDT 1.2] Preparar arquitectura Flutter y conexión con API Laravel**.
Describe los flujos existentes y las decisiones para migrarlos por etapas.
La creación de este documento no implica que la base Flutter esté implementada.

## Delimitar el trabajo de la issue #3

La base debe incluir un proyecto Flutter ejecutable, organización del código,
configuración de la API, cliente HTTP compartido, almacenamiento seguro del
token, navegación inicial y componentes de carga y error. La comprobación de
conectividad utiliza el endpoint público `GET /api/test-api`.

La migración de las pantallas y del flujo de autenticación corresponde a la
issue #4 (EDT 1.3). El perfil y la navegación por permisos corresponden a la
issue #5 (EDT 1.4). Los módulos operativos se incorporan progresivamente.

El código React Native permanece en `Web/agrofusion-mobile/` como referencia
durante la migración. Laravel permanece en `Web/`.

## Identificar los componentes existentes

Las rutas de la tabla parten de `Web/agrofusion-mobile/`:

| Componente | Ubicación | Responsabilidad |
| --- | --- | --- |
| Entrada de la aplicación | `App.js` | Monta el proveedor de sesión y selecciona navegación pública o autenticada; muestra carga durante el arranque. |
| Sesión | `src/context/AuthContext.js` | Recupera credenciales, consulta el usuario, inicia y cierra sesión y actualiza el perfil en memoria. |
| Cliente HTTP | `src/api/client.js` | Centraliza Axios, JSON, timeout de 30 segundos, encabezado Bearer y eliminación de credenciales ante un 401. Agrupa llamadas por módulo. |
| Entorno y conexión | `src/config/api.js`, `src/api/apiResolver.js` | Define servidores, comprueba `/test-api` y resuelve alternativas de conexión. |
| Navegación pública | `src/navigation/AuthNavigator.js` | Registra login, registro y presentación de la plataforma. |
| Navegación autenticada | `src/navigation/MainNavigator.js` | Registra dashboard, perfil y pantallas operativas. |
| Menús y roles | `src/constants/roles.js`, `src/constants/roleFeatures.js` | Define etiquetas y opciones de navegación según el rol. |
| Peticiones y mensajes | `src/hooks/useApi.js`, `src/utils/apiHelpers.js` | Maneja carga y error y normaliza respuestas de listas, elementos y errores. |
| Componentes compartidos | `src/components/` | Reúne controles de formulario, tarjetas, indicadores de estado, mapas y estados de carga y vacío. |

Las dependencias declaradas en
[`package.json`](../../Web/agrofusion-mobile/package.json) incluyen Expo,
React Navigation, Axios, AsyncStorage, mapas, ubicación, selector de imágenes
y `expo-secure-store`. Sin embargo, el flujo de sesión inspeccionado utiliza
**AsyncStorage**, no `expo-secure-store`, para guardar `auth_token` y `user_data`.

## Seguir el flujo de sesión

El comportamiento está definido en
[`App.js`](../../Web/agrofusion-mobile/App.js),
[`AuthContext.js`](../../Web/agrofusion-mobile/src/context/AuthContext.js) y
[`client.js`](../../Web/agrofusion-mobile/src/api/client.js):

1. Al arrancar, la aplicación muestra un indicador de carga y resuelve la API.
2. Recupera `auth_token` y `user_data` de AsyncStorage.
3. Si existen credenciales reales, consulta `GET /api/me` con el token Bearer.
4. Si la consulta funciona, conserva el usuario y presenta la navegación
   autenticada. El flujo existente elimina las credenciales si la consulta falla.
5. El login envía correo y contraseña a `POST /api/login`, guarda el token y el
   usuario recibidos y actualiza el contexto.
6. El cierre de sesión intenta `POST /api/logout` y elimina la sesión local
   aunque la petición falle.

También existe un flujo de demostración con tokens `demo-*`. El archivo
[`designMode.js`](../../Web/agrofusion-mobile/src/constants/designMode.js)
establece `USE_MOCK_DATA = false`. Los datos de demostración no deben usarse
como evidencia de comunicación real con Laravel.

## Conservar el contrato de Laravel

Las fuentes del contrato son
[`routes/api.php`](../../Web/routes/api.php) y
[`AuthController.php`](../../Web/app/Http/Controllers/Api/AuthController.php).
La URL base del cliente debe incluir `/api`:

| Método y ruta | Acceso | Respuesta o comportamiento observado |
| --- | --- | --- |
| `GET /api/test-api` | Público | Devuelve `200` con `{"ok": true}`. Permite comprobar HTTP y JSON sin iniciar sesión. |
| `POST /api/login` | Público | Recibe `email` y `password`; devuelve `user` y `token`. Credenciales incorrectas producen `401`; una cuenta pendiente o inactiva produce `403`. |
| `POST /api/register` | Público | Valida datos personales y contraseña; crea una solicitud pendiente de aprobación y devuelve `201` con `message` y `user`, sin token. |
| `GET /api/me` | `auth:sanctum` | Devuelve directamente el objeto de usuario con `roles`, sin envoltorio `user`. |
| `POST /api/logout` | `auth:sanctum` | Elimina el token de acceso utilizado y devuelve un mensaje. |

El identificador del usuario es `usuarioid`. El perfil React Native consume,
entre otros campos, `nombre`, `apellido`, `email`, `telefono`, `ci_nit`,
`fecharegistro`, `ultimologin` y `roles[].name`.

El controlador de autenticación inspeccionado carga roles; no define un
contrato explícito de permisos efectivos para Flutter. Esa integración debe
coordinarse con la issue #2 (EDT 1.1) antes de implementar la issue #5.

Los permisos de los módulos se verifican en Laravel mediante `auth:sanctum`
y `action.permission`. Ocultar opciones del menú en Flutter no sustituye
esas comprobaciones del servidor.

## Agrupar los módulos para la migración progresiva

Los grupos proceden de las pantallas registradas en
[`MainNavigator.js`](../../Web/agrofusion-mobile/src/navigation/MainNavigator.js):

| Grupo | Pantallas y funcionalidades existentes |
| --- | --- |
| Acceso y cuenta | Login, registro, dashboard, perfil y presentación. |
| Campo | Lotes, actividades, tareas asignadas, evidencias, cosechas, certificaciones y clima. |
| Almacén | Almacenes, movimientos y traslados a planta. |
| Planta | Recepción, tareas, procesos, procesamiento, plantillas y máquinas. |
| Logística | Envíos, rutas, incidentes, documentos, vehículos y transportistas. |
| Comercial y administración | Pedidos, distribución, puntos de venta y usuarios. |

Cada grupo se migra conservando sus contratos y reglas del backend. No se
copian todas sus pantallas ni se agregan dependencias para mapas, cámara o
ubicación en la issue de preparación.

## Preparar una estructura Flutter sencilla

La estructura propuesta para la implementación es:

```text
Mobile/
  lib/
    main.dart
    app.dart
    config/       # URL base y configuración del entorno
    models/       # Objetos de respuesta que necesite cada etapa
    services/     # Cliente HTTP, almacenamiento seguro y acceso a la API
    navigation/   # Rutas de la aplicación
    screens/      # Pantallas organizadas por funcionalidad
    widgets/      # Componentes compartidos de carga y error
  test/           # Comprobaciones automatizadas de la base
  docs/
```

Las carpetas y clases se incorporan cuando tienen una responsabilidad
implementada. Las pantallas consumen servicios; la configuración de HTTP y
el acceso al token se comparten para evitar duplicación.

Las decisiones para la base son:

- Configurar una URL de API explícita por entorno. No copiar la IP privada
  ni el cambio automático entre producción y desarrollo de React Native.
- Preparar almacenamiento seguro para el token. No guardar contraseñas ni
  reproducir su almacenamiento en AsyncStorage.
- Centralizar encabezados JSON, token Bearer, timeout y errores HTTP y de red.
  Preparar la invalidación de sesión ante un 401 de una petición autenticada.
- Diferenciar un error de conectividad de una sesión rechazada. Una caída
  de red no demuestra que el token haya dejado de ser válido.
- Mantener la navegación inicial y los estados de carga y error reutilizables,
  sin adelantar el login ni las reglas de menú de las siguientes issues.

## Verificar la implementación por etapas

La evidencia de cierre de la issue #3 debe incluir:

1. Proyecto Flutter creado dentro de `Mobile/` y ejecución en un dispositivo
   o navegador de desarrollo identificado.
2. Análisis estático y pruebas de configuración, cliente HTTP, manejo del
   token y navegación inicial.
3. Comprobación desde Flutter contra Laravel con `GET /api/test-api` y
   validación de `{"ok": true}`. Una respuesta simulada en pruebas no
   reemplaza esta comprobación.
4. Comprobación del estado de error y de la acción de reintentar cuando
   Laravel no está disponible.
5. Documentación de arranque con la URL utilizada, los comandos ejecutados
   y cualquier validación que quede pendiente.

Este análisis completa únicamente la primera actividad de la issue. Las
demás casillas se marcan después de implementar y verificar su resultado.
