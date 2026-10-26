# Análisis de perfil y permisos para Flutter

Este documento orienta al equipo que adapta Laravel para la issue #2,
**[EDT 1.1] Adaptar API Laravel de perfil y permisos para Flutter**. Registra
el comportamiento existente y los cambios necesarios para reutilizarlo desde
la aplicación móvil. Esta primera etapa corresponde únicamente a la revisión.

## Identificar la implementación existente

Los componentes que intervienen en el perfil y la autorización son:

| Componente | Fuente | Comportamiento observado |
| --- | --- | --- |
| Perfil web | [`UserProfileController`](../app/Http/Controllers/Web/UserProfileController.php) | Muestra el perfil y actualiza al usuario de la sesión. Contiene la validación y la lógica de edición. |
| Rutas web | [`routes/web.php`](../routes/web.php) | Expone `GET /perfil` y `PUT /perfil` dentro del grupo `auth` y `cuenta.aprobada`. |
| Perfil API | [`AuthController::me`](../app/Http/Controllers/Api/AuthController.php) | Devuelve directamente el usuario autenticado con sus roles. |
| Rutas API | [`routes/api.php`](../routes/api.php) | Protege `GET /api/me` con `auth:sanctum`. No registra una ruta para editar el perfil propio. |
| Usuario | [`Usuario`](../app/Models/Usuario.php) | Usa la clave `usuarioid`, Sanctum y el trait `HasRoles` de Spatie. Oculta `passwordhash` al serializar. |
| Fotos | [`UsuarioAvatar`](../app/Support/UsuarioAvatar.php) | Resuelve la imagen visible, guarda archivos en el disco `public` y elimina la foto almacenada anterior. |
| Permisos | [`permission_matrix.php`](../config/permission_matrix.php), [`RolePermissionSeeder`](../database/seeders/RolePermissionSeeder.php) | Define los permisos por módulo y los asigna a los roles con guard `web`. |
| Autorización por acción | [`ActionPermissionMiddleware`](../app/Http/Middleware/ActionPermissionMiddleware.php) | Consulta `$user->can(...)` y contempla condiciones adicionales de acceso por módulo. El administrador no tiene bypass general. |
| Estado de cuenta | [`CuentaEstado`](../app/Support/CuentaEstado.php) | Determina si una cuenta activa y aprobada puede acceder. |

## Conservar las reglas del perfil

El nombre editable de esta issue es `nombreusuario`, el identificador visible
con `@` en el perfil. No se refiere al campo personal `nombre`.

Las reglas que aplica el controlador web son:

- El nombre de usuario admite letras ASCII, números, puntos, guiones y
  guiones bajos, con un máximo de 100 caracteres.
- El nombre debe ser único en `usuario.nombreusuario`, excluyendo al propio
  usuario mediante su clave `usuarioid`.
- Cuando el usuario cambia el valor, `nombreusuario_editado` pasa a `true`.
  Después no se vuelve a modificar el nombre mediante el perfil.
- Enviar el mismo nombre no consume el cambio disponible.
- La foto se recibe como archivo `imagen`, con validación de imagen,
  extensiones JPEG, JPG, PNG, WEBP o GIF y un máximo de 2048 KB.
- El perfil propio permite actualizar la foto sin introducir una restricción
  de un solo cambio de fotografía.
- El controlador actualiza `fechamodificacion` manualmente.

El formulario está en
[`profile/show.blade.php`](../resources/views/profile/show.blade.php).
Los permisos administrativos de usuarios y roles no son un requisito del
formulario para editar el perfil propio. La matriz no define un permiso
específico de edición del perfil; la adaptación debe conservar esa regla.

## Identificar lo que falta en la API

`GET /api/me` no agrega una lista explícita de permisos. Spatie ya proporciona
`getAllPermissions()`, que reúne permisos directos y permisos recibidos de los
roles. Se debe reutilizar ese cálculo y exponer los nombres sin duplicados.
Los controles adicionales de cada operación siguen correspondiendo al backend.

La respuesta necesita indicar también si el usuario conserva su cambio de
nombre. Los roles por sí solos no expresan esa restricción.

El campo `imagenurl` puede contener una ruta relativa, una referencia heredada
o un valor vacío. La web utiliza `UsuarioAvatar::resolve()` para presentar una
foto utilizable o un placeholder SVG. El contrato móvil debe especificar cómo
representa la imagen disponible y la ausencia de una fotografía.

El middleware
[`EnsureCuentaAprobada`](../app/Http/Middleware/EnsureCuentaAprobada.php)
utiliza sesión web, cierre de sesión y redirecciones. Para las peticiones
Bearer se debe reutilizar la regla de `CuentaEstado` y responder JSON, sin
introducir dependencia de una sesión web.
Esa regla considera aprobado el estado heredado `null` cuando la cuenta
está activa.

La documentación anterior de permisos contiene una descripción del
administrador con acceso a todo. La matriz, su sincronizador y el middleware
inspeccionados aplican listas de permisos concretas; el contrato de Flutter
debe describir el comportamiento del código.

## Reutilizar la lógica de edición

La adaptación debe compartir la validación y actualización del perfil entre
los controladores web y API. Los controladores mantienen la respuesta que
corresponde a cada interfaz: redirección web o JSON para el cliente móvil.

La API debe obtener al usuario desde la autenticación. Los campos editables
se limitan a `nombreusuario` e `imagen`; identidad, roles, permisos y estado
de cuenta permanecen sujetos a sus operaciones administrativas existentes.

La protección de acceso y la validación se implementan junto con el endpoint
de escritura. Las pruebas deben cubrir credenciales ausentes o inválidas,
cuentas no autorizadas, el segundo cambio de nombre, nombres duplicados,
archivos inválidos y campos protegidos.

## Registrar la comprobación inicial

Se ejecutó la prueba existente de perfil con SQLite en memoria:

```powershell
php artisan test --without-tty --filter=test_usuario_solo_puede_editar_foto_y_nombre_usuario_una_vez
```

Resultado: **1 prueba aprobada, 7 aserciones**. La prueba confirma el primer
cambio de nombre y que un segundo envío no modifica el nombre en la web. Aunque su
nombre menciona la foto, no carga un archivo; la carga de imágenes necesita
cobertura específica en las siguientes etapas.

## Dividir la implementación en avances revisables

La propuesta de bloques y casillas de la issue es:

| Bloque | Resultado para revisar y registrar en un commit | Casilla |
| --- | --- | --- |
| 1 | Análisis del comportamiento y las reglas existentes. | Revisar la implementación actual. |
| 2 | Consulta del perfil y permisos efectivos, con pruebas del endpoint. | Verificar la consulta de usuario y permisos. |
| 3 | Edición del perfil reutilizada por web y API, con validación y restricciones de acceso. | Adaptar nombre y foto; validar datos y acceso. |
| 4 | Contrato de respuestas y campos necesarios para Flutter. | Comprobar respuestas y documentar campos. |
| 5 | Comprobación final de casos autorizados, denegados y regresiones web. | Ejecutar pruebas y verificar accesos. |

El bloque 3 agrupa dos casillas porque la escritura necesita su validación y
autorización en el mismo cambio. Las pruebas acompañan a cada funcionalidad;
la comprobación final completa la evidencia de los criterios de aceptación.
