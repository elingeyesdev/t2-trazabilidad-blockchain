# Análisis de perfil y navegación por permisos para Flutter

Este documento orienta al equipo que implementa la issue #5,
**[EDT 1.4] Migrar perfil y navegación por permisos a Flutter**.
Permite identificar los flujos de React Native, el contrato de Laravel y
los bloques de implementación. Corresponde a la primera actividad de análisis;
no acredita que las pantallas o los cambios de esta issue estén implementados.

## Identificar las fuentes

Las fuentes del perfil y la navegación son:

| Fuente | Comportamiento observado |
| --- | --- |
| [Perfil de React Native](../../Web/agrofusion-mobile/src/screens/profile/ProfileScreen.js) | Presenta datos de `useAuth`, el primer rol, un avatar decorativo, fechas y cierre de sesión. No contiene edición de nombre de usuario ni carga de fotografía. |
| [Contexto de autenticación](../../Web/agrofusion-mobile/src/context/AuthContext.js) | Recupera el perfil con `authApi.me`, guarda `user_data` y expone `refreshUser`. La actualización captura errores sin informar del resultado a la pantalla. |
| [Entrada de React Native](../../Web/agrofusion-mobile/App.js) | Selecciona `MainNavigator` o `AuthNavigator` según el usuario del contexto. |
| [Navegación principal](../../Web/agrofusion-mobile/src/navigation/MainNavigator.js) | Registra las pantallas operativas y el perfil sin filtrar cada ruta por permisos. |
| [Dashboard](../../Web/agrofusion-mobile/src/screens/dashboard/DashboardScreen.js) | Construye accesos por grupos de roles o por la configuración del trabajador. Incluye el acceso al perfil. |
| [Grupos de roles](../../Web/agrofusion-mobile/src/constants/roles.js) y [menús de trabajadores](../../Web/agrofusion-mobile/src/constants/roleFeatures.js) | Determinan las opciones a partir de nombres de roles. La lista `permissions` de la configuración del trabajador no filtra los elementos de `config.menu`. |
| [DrawerContent](../../Web/agrofusion-mobile/src/navigation/DrawerContent.js) | Define otro menú por roles, pero no está conectado al navegador que monta `App.js`. No representa por sí solo la navegación ejecutada. |
| [Contrato de perfil](../../Web/docs/api-perfil-flutter.md) | Documenta consulta, edición, capacidades, fotografía y errores de la API adaptada en la EDT 1.1. |

El modo de demostración está desactivado en
[designMode.js](../../Web/agrofusion-mobile/src/constants/designMode.js).
Los usuarios simulados de las vistas de diseño no sustituyen la comprobación
con los permisos devueltos por Laravel.

## Conservar y adaptar el perfil

El perfil React Native presenta nombre y apellido, correo, teléfono, CI/NIT,
rol, fecha de registro y último acceso. El avatar es un icono fijo. El enlace
**Conoce AgroFusion** abre una presentación; esa presentación no interviene
en la consulta, edición o autorización del perfil.

La edición solicitada en esta issue se apoya en el servicio de perfil de
Laravel compartido con la web. Debe distinguir el nombre personal `nombre`,
que se consulta, del identificador editable `nombreusuario`.

### Consultar GET /api/me

La respuesta aparece en la raíz del JSON, sin envoltorio `data` o `user`.
Los campos necesarios para Flutter se agrupan así:

| Grupo | Campos y uso |
| --- | --- |
| Identidad | `usuarioid`, `nombre`, `apellido`, `email`, `nombreusuario`, `telefono` y `ci_nit`. Presentar ausencias opcionales con un texto de sustitución; conservar CI/NIT como texto. |
| Fechas | `fecharegistro`, `fechamodificacion` y `ultimologin`, que pueden estar vacías. Interpretar fechas válidas y presentarlas en la zona local. |
| Cuenta | `activo` y `estado_cuenta`. Mantener la validación de cuenta activa y aprobada de la EDT 1.3, incluido el estado heredado `null`. |
| Fotografía | `avatar_url` para presentación; `imagenurl` es la referencia almacenada. Contemplar una foto ausente o que no pueda cargarse. |
| Roles | `roles`, lista de objetos con `id` y `name`. Mostrar todos los roles disponibles; no usar solo el primero para autorizar. |
| Permisos efectivos | `permissions`, lista de nombres que une permisos directos y heredados de los roles. Puede estar vacía. |
| Edición propia | `profile_capabilities.update_username`, `profile_capabilities.update_photo` y `nombreusuario_editado`. Controlan la edición del perfil propio. |

[PerfilUsuarioResource](../../Web/app/Http/Resources/PerfilUsuarioResource.php)
construye esta respuesta. Las capacidades del perfil propio no requieren
permisos de administración de otros usuarios.

### Actualizar el nombre y la fotografía

La API admite `PATCH /api/me` y `PUT /api/me` con actualización parcial y
devuelve el perfil completo con el mismo formato de la consulta.

Las reglas de edición comprobadas son:

- `nombreusuario` admite letras ASCII, números, puntos, guiones y guiones
  bajos, con hasta 100 caracteres y unicidad comprobada por Laravel.
- El primer cambio a un valor diferente consume la edición del nombre.
  Enviar el mismo valor no la consume. Un cambio posterior diferente devuelve
  `403`; la fotografía sigue siendo editable si se omite el nombre.
- `imagen` es un archivo JPEG/JPG, PNG, WEBP o GIF de hasta 2048 KB.
  Para subirlo, enviar un formulario `POST /api/me` con `_method=PATCH` y
  el archivo `imagen`; el cliente debe generar el delimitador multipart.
- Debe existir al menos un campo editable. `imagen: null` no elimina la foto.
  La API no expone una operación para borrarla.
- No enviar `usuarioid`, roles, permisos, estado de cuenta, correo o los
  nombres personales al actualizar el perfil: son campos protegidos.
- No aplicar cambios locales como si estuvieran guardados antes de recibir
  una respuesta válida. Sustituir el perfil en memoria por la respuesta del
  servidor, incluidas sus capacidades y permisos.

La validación y autorización pertenecen a
[ActualizarPerfilRequest](../../Web/app/Http/Requests/ActualizarPerfilRequest.php).
[PerfilUsuarioService](../../Web/app/Services/PerfilUsuarioService.php)
mantiene la transacción y conserva la foto anterior si falla el guardado.
Flutter debe reutilizar esas reglas del servidor y presentar sus errores.

`avatar_url` puede contener una URL HTTP/HTTPS o una referencia heredada
`data:image/...`. No adjuntar el token Bearer al descargar una foto de otro
origen. Las fotos locales requieren que el servidor exponga el disco `public`
y produzca una URL alcanzable desde el dispositivo.

## Sustituir la navegación por roles

Los menús de React Native identifican grupos agrícolas, planta, logística,
comercialización y administración mediante roles. Una cuenta con un permiso
directo o con varios roles puede tener capacidades distintas a esos grupos.
Flutter debe resolver la visibilidad a partir de `permissions` de `me`.

El nombre `admin` no concede un acceso general implícito. El
[middleware de acciones](../../Web/app/Http/Middleware/ActionPermissionMiddleware.php)
consulta la [matriz de permisos](../../Web/config/permission_matrix.php) y
mantiene restricciones adicionales de operación y pertenencia de los datos.

Estos ejemplos relacionan destinos con permisos comprobados en las
[rutas API](../../Web/routes/api.php):

| Destino o consulta | Permiso exigido por la ruta |
| --- | --- |
| Perfil propio | Cuenta autenticada, activa y aprobada; capacidades específicas para editar. |
| Lotes, actividades, producciones y climas | `lotes.view` para sus consultas. |
| Almacenes e insumos | `inventario.view`. |
| Movimientos de almacén | `almacen.movimientos.view`. |
| Certificaciones | `certificaciones.view`. |
| Pedidos | `pedidos.view`. |
| Incidentes | `incidentes.view`. |
| Rutas múltiples | `rutas_multi.view`. |
| Asignaciones múltiples | `asignaciones.view`. |
| Documentos de entrega | `documentos.view`, con controles adicionales del backend. |
| Usuarios, roles y asignaciones de roles | `usuarios.admin`, también para las consultas de estas rutas API. |

`usuarios.view` no basta para consultar `/api/usuarios`. Tampoco corresponde
inventar nombres como `actividades.view` cuando la ruta exige `lotes.view`.
La tabla describe controles de la API; no acredita que esos módulos estén
migrados a Flutter ni reemplaza las restricciones adicionales del servidor.

El catálogo de navegación debe asociar cada entrada con su destino Flutter
y el permiso de su operación. Registrar una pantalla, filtrar su acceso en
el menú y proteger la entrada directa deben utilizar el mismo criterio.
Una lista vacía no habilita módulos restringidos; el perfil propio permanece
disponible para una cuenta autorizada. No presentar una ruta vacía o un dato
de demostración como una funcionalidad migrada.

La issue cubre perfil y navegación por permisos. Registrar un destino no
supone migrar todos los formularios y operaciones de los módulos de negocio
incluidos en `MainNavigator`. Cada destino ofrecido debe tener un alcance
explícito y una pantalla funcional; las opciones de operaciones requieren
sus propios permisos, además del permiso de consulta del módulo.

## Reutilizar la sesión de Flutter

La base de la EDT 1.3 ya consulta `GET /api/me` después del login, al restaurar
una sesión y al volver al primer plano. Sin embargo,
[AuthUser](../lib/models/auth_user.dart) conserva solo identificador, nombre
y correo: descarta el resto del perfil, los roles y los permisos.

La implementación debe ampliar ese modelo y reutilizar
[AuthService](../lib/services/auth_service.dart),
[AuthController](../lib/controllers/auth_controller.dart) y
[ApiClient](../lib/services/api_client.dart). El envío multipart debe conservar
el control de origen, timeout, errores HTTP y expiración de sesión del cliente
compartido. El selector de foto debe funcionar en las plataformas declaradas
sin imponer `dart:io` a la versión web.

Al restaurar o actualizar el perfil, sustituir los datos y permisos de la
misma cuenta y notificar a las pantallas y al menú. No persistir permisos
como una autorización independiente del servidor. Una respuesta tardía de
una sesión anterior no debe actualizar al usuario de otra sesión ni devolver
acceso a un destino cuyo permiso ya fue retirado.

## Tratar los errores según su contexto

| Situación | Comportamiento esperado |
| --- | --- |
| Carga del perfil | Mostrar carga sin sustituirla por datos ficticios; ofrecer reintento si falla. |
| `401` autenticado | Reutilizar la retirada de sesión y la limpieza del token; impedir volver a una pantalla protegida. |
| `403` al editar o entrar a un módulo | Mostrar acceso denegado y permitir regresar. No interpretar todo `403` como token inválido. |
| `403` al verificar `me` | Aplicar la política existente para una cuenta pendiente o inactiva. |
| `422` | Asociar los errores con nombre, imagen o el formulario; conservar lo escrito para corregirlo. |
| Conexión, timeout o `5xx` | Mostrar un mensaje controlado y permitir reintentar la consulta. No repetir automáticamente una escritura de resultado incierto. |
| Error al cargar la foto | Presentar un avatar de sustitución sin romper el perfil o la navegación. |

## Implementar por bloques revisables

Los bloques corresponden a las siete actividades de la issue:

1. Registrar este análisis y el contrato observado.
2. Ampliar el modelo y migrar la pantalla de consulta del perfil con datos reales.
3. Incorporar edición del nombre y fotografía mediante la API existente.
4. Adaptar el menú y proteger sus destinos mediante permisos efectivos.
5. Verificar y completar la recuperación de perfil y permisos al restaurar sesión.
6. Integrar y comprobar recuperación de errores, denegación e invalidación de sesión.
7. Ejecutar la integración real con varias cuentas, documentar evidencias y comprobar regresiones.

Las comprobaciones deben incluir permisos directos y de varios roles,
cuentas sin permisos, `admin` sin el permiso concreto, retirada de permisos,
acceso directo a rutas, edición única del nombre, foto válida e inválida,
sesión revocada, fallos de conexión y respuestas tardías. Las pruebas de
Laravel deben confirmar que una petición manual sin autorización se rechaza
aunque el cliente oculte la opción.

Este primer bloque modifica únicamente documentación. Después de su commit,
continúa con la consulta del perfil y conserva la división por actividades
para revisar cada cambio y marcar su casilla con evidencia.
