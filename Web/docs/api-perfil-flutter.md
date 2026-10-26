# Contrato de perfil y permisos para Flutter

Esta referencia está dirigida al equipo que integra el perfil de AgroFusion
en Flutter. Describe cómo consultar al usuario autenticado, interpretar sus
permisos y actualizar su nombre de usuario y fotografía mediante la API Laravel.

## Preparar las solicitudes

Necesitas Laravel operativo, sus migraciones aplicadas y un token de Sanctum
emitido para una cuenta activa y aprobada. La migración de
`personal_access_tokens` forma parte de esta implementación.
Para servir las fotografías locales, el servidor debe exponer el disco
`public` mediante `public/storage`.

La URL base incluye `/api`. Si configuras Flutter con
`API_BASE_URL=http://127.0.0.1:8000/api`, usa `me` como ruta del cliente HTTP.
Para acceder desde un dispositivo o emulador, consulta la
[configuración de conexión de Flutter](../../Mobile/README.md#configurar-la-api).

Envía estas cabeceras en las solicitudes de perfil:

| Cabecera | Valor | Uso |
| --- | --- | --- |
| `Accept` | `application/json` | Solicita errores JSON, incluidos los de autenticación y validación. |
| `Authorization` | `Bearer TOKEN_DE_SESION` | Identifica al usuario mediante su token de Sanctum. |
| `Content-Type` | `application/json` | Se usa cuando el cuerpo contiene JSON. Para archivos, deja que el cliente genere `multipart/form-data` con su delimitador. |

Sustituye `TOKEN_DE_SESION` por el token recibido al iniciar sesión.
`POST /api/login` recibe `email` y `password`, y devuelve un objeto con las
claves `user` y `token`. Consulta después `GET /api/me` para obtener el contrato
de perfil y los permisos efectivos descritos en esta referencia.

## GET /api/me

Devuelve el perfil del usuario del token con estado **200 OK**. No recibe
parámetros de ruta ni necesita cuerpo o parámetros de consulta. Un
`usuarioid` enviado en la consulta no selecciona otro usuario.

El perfil aparece en la raíz del JSON, sin envoltorios `data` o `user`.
Este ejemplo usa datos ficticios; los identificadores y permisos dependen
de la cuenta:

```json
{
  "usuarioid": 1,
  "nombre": "Ana",
  "apellido": "Mamani",
  "email": "ana@example.test",
  "nombreusuario": "ana",
  "telefono": "70000000",
  "ci_nit": "123456",
  "imagenurl": null,
  "fecharegistro": "2026-10-25T16:00:00.000000Z",
  "fechamodificacion": "2026-10-25T16:00:00.000000Z",
  "ultimologin": null,
  "activo": true,
  "estado_cuenta": "aprobado",
  "nombreusuario_editado": false,
  "avatar_url": null,
  "roles": [{"id": 2, "name": "agricultor"}],
  "permissions": ["inventario.view", "lotes.view"],
  "profile_capabilities": {
    "update_username": true,
    "update_photo": true
  }
}
```

La respuesta contiene los siguientes campos:

| Campo | Tipo JSON | Significado para Flutter |
| --- | --- | --- |
| `usuarioid` | Entero | Clave del usuario autenticado. |
| `nombre` | Cadena | Nombre personal, de consulta en este endpoint. |
| `apellido` | Cadena | Apellido, de consulta en este endpoint. |
| `email` | Cadena | Correo, de consulta en este endpoint. |
| `nombreusuario` | Cadena | Identificador visible del perfil; se envía sin el prefijo `@`. |
| `telefono` | Cadena o `null` | Teléfono registrado. |
| `ci_nit` | Cadena o `null` | Identificación registrada. Consérvala como texto. |
| `imagenurl` | Cadena o `null` | Referencia almacenada de la foto; puede ser relativa o heredada. |
| `fecharegistro` | Cadena de fecha o `null` | Fecha de registro. |
| `fechamodificacion` | Cadena de fecha o `null` | Fecha de la última modificación del perfil. |
| `ultimologin` | Cadena de fecha o `null` | Último acceso registrado; puede estar vacío. |
| `activo` | Booleano | La consulta autorizada requiere una cuenta activa. |
| `estado_cuenta` | Cadena o `null` | `aprobado`, o `null` para una cuenta heredada considerada aprobada. |
| `nombreusuario_editado` | Booleano | Indica si ya se utilizó el cambio de nombre. |
| `avatar_url` | Cadena o `null` | Imagen resuelta para presentar en el cliente. Usa una imagen predeterminada cuando sea `null`. |
| `roles` | Lista de objetos | Cada objeto contiene `id` entero y `name` cadena. Puede ser `[]`. |
| `permissions` | Lista de cadenas | Permisos directos y heredados de roles, sin duplicados y ordenados por nombre. Puede ser `[]`. |
| `profile_capabilities` | Objeto | Contiene `update_username` y `update_photo`, ambos booleanos. |

Las fechas no vacías se serializan en formato ISO 8601 con zona UTC (`Z`).
Para mostrar la foto, utiliza `avatar_url`: una foto local disponible se
resuelve a una URL absoluta, por ejemplo
`http://127.0.0.1:8000/storage/avatars/usuario-1-UUID.png`.
Una referencia heredada también puede ser una URL externa o una URI
`data:image/...`; contempla ese formato al presentar la imagen.
Una foto ausente, un archivo local inexistente o la referencia Supabase
identificada como obsoleta se representan con `avatar_url: null`.

La respuesta excluye la contraseña, tokens, datos internos de la solicitud
de acceso y relaciones internas de roles. No devuelve un token renovado.

### Interpretar los permisos

Usa `permissions` para decidir qué opciones de módulos mostrar. Los roles
no sustituyen esta lista: el administrador también recibe permisos concretos
y no dispone de un acceso general implícito. Cada operación del backend
conserva sus controles de permisos y de pertenencia de los datos.

Usa `profile_capabilities.update_username` para habilitar el cambio de nombre;
es `true` mientras `nombreusuario_editado` sea `false`.
`profile_capabilities.update_photo` es `true` en el perfil autorizado.
Editar el perfil propio no requiere permisos de administración de usuarios.
El servidor comprueba las restricciones en cada escritura.

## PATCH /api/me y PUT /api/me

Actualiza el perfil del usuario autenticado y devuelve **200 OK** con el
perfil completo, usando el mismo formato de `GET /api/me`. Ambos verbos
admiten una actualización parcial: puedes enviar solo el nombre o solo la foto.

No recibe identificadores de usuario en la ruta ni necesita parámetros de
consulta. El cuerpo admite los siguientes campos:

| Campo | Tipo | Restricciones |
| --- | --- | --- |
| `nombreusuario` | Cadena | Opcional. Si se incluye, debe tener entre 1 y 100 caracteres, ser único y usar letras ASCII, números, puntos, guiones o guiones bajos. |
| `imagen` | Archivo | Opcional. Imagen JPEG/JPG, PNG, WEBP o GIF, de hasta 2048 KB. Se envía como archivo multipart. |
| `_method` | Cadena | Campo de transporte para enviar `PATCH` mediante un formulario `POST`, como se muestra en el ejemplo de fotografía. |

Envía al menos `nombreusuario` o un archivo `imagen`.
Enviar `imagen: null` no elimina la foto y, sin nombre ni archivo, devuelve
un error de validación. La API no expone una operación para borrar la foto.

El nombre editable es `nombreusuario`; los campos personales `nombre` y
`apellido` son de consulta. Cualquier otro campo enviado en esta operación,
incluidos `usuarioid`, `email`, `role`, `roles`, `permissions`, `activo`,
`estado_cuenta`, `nombreusuario_editado` o `imagenurl`, produce **422**.
No se aplica parcialmente un envío que falla la validación o la autorización.

El primer cambio a un valor diferente consume el cambio de nombre:
`nombreusuario_editado` pasa a `true` y
`profile_capabilities.update_username` pasa a `false`.
Enviar el mismo nombre no consume el cambio. Después, intentar otro nombre
devuelve **403**. Puedes seguir reemplazando la foto omitiendo `nombreusuario`.
Si envías un segundo nombre junto a una foto, se rechaza todo el envío.

Para cargar una foto desde Flutter, utiliza `POST /api/me` con cuerpo
`multipart/form-data`, campo `_method=PATCH` y archivo `imagen`.
Deja que la biblioteca HTTP genere el delimitador multipart.
El [cliente HTTP compartido](../../Mobile/lib/services/api_client.dart) permite
consultar el perfil y cambiar el nombre mediante JSON, y admite formularios
multipart con los mismos controles de sesión y errores.
[AuthService](../../Mobile/lib/services/auth_service.dart) integra ambos envíos
para la edición del perfil móvil.

La actualización reutiliza la validación y el servicio del perfil web.
Los archivos se guardan en el disco `public`. La foto anterior se elimina
después de guardar correctamente la sustitución; si falla el guardado de
la nueva imagen o la transacción, se conserva el perfil anterior.
Si solo se actualiza el nombre, se conserva la referencia de la fotografía
existente, incluidas las URLs externas.

## Respuestas de error

Con `Accept: application/json`, los errores de perfil usan estos estados:

| Estado | Situación | Acción del cliente |
| --- | --- | --- |
| `401 Unauthorized` | Falta el token o es inválido, está revocado o ha vencido. | Solicita que se inicie sesión otra vez. |
| `403 Forbidden` | La cuenta está inactiva o pendiente, o se intenta cambiar un nombre ya bloqueado. | Muestra el mensaje y actualiza el estado de la pantalla. |
| `422 Unprocessable Content` | Hay campos protegidos, nombre inválido o duplicado, archivo inválido, exceso de tamaño o falta de campos editables. | Asocia los mensajes de `errors` con los campos del formulario. |
| `5xx` | Falla el servidor o el almacenamiento. | Muestra un error de servicio y permite volver a consultar el perfil. |

Un token ausente produce esta respuesta:

```json
{
  "message": "Unauthenticated."
}
```

Un segundo cambio de nombre produce esta respuesta:

```json
{
  "message": "No tienes autorización para realizar este cambio de perfil."
}
```

Un cuerpo vacío produce esta respuesta de validación:

```json
{
  "message": "Envía un nombre de usuario o una imagen.",
  "errors": {
    "perfil": ["Envía un nombre de usuario o una imagen."]
  }
}
```

`errors` es un mapa de nombres de campo a listas de mensajes. Puede incluir
`nombreusuario`, `imagen`, `perfil` o la clave de un campo rechazado.
Decide por el estado HTTP y las claves de `errors`; el texto de `message`
puede resumir varios errores y no es un código de error estable.
Los límites globales de carga de PHP y del servidor HTTP también deben
permitir el tamaño de la imagen y el cuerpo multipart.

## Comprobar el contrato con PowerShell

Estos ejemplos requieren un servidor de desarrollo con una cuenta de prueba
activa y aprobada. El cambio de nombre consume su única edición si usas un
valor diferente. Los comandos de esta sección se ejecutan en PowerShell.

1. Configura la URL y las cabeceras de tu sesión:

   ```powershell
   $apiBaseUrl = 'http://127.0.0.1:8000/api'
   $token = 'TOKEN_DE_SESION'
   $headers = @{
       Accept = 'application/json'
       Authorization = "Bearer $token"
   }
   ```

   Sustituye `TOKEN_DE_SESION` por el token de tu cuenta de prueba y ajusta la
   URL al servidor que ejecutas.

2. Consulta el perfil:

   ```powershell
   Invoke-RestMethod -Uri "$apiBaseUrl/me" -Headers $headers
   ```

   Confirma que aparecen `usuarioid`, `permissions` y `profile_capabilities`
   en el objeto raíz.

3. Si `update_username` es `true`, envía el nombre que quieres conservar:

   ```powershell
   $body = @{ nombreusuario = 'ana.mamani' } | ConvertTo-Json
   Invoke-RestMethod -Uri "$apiBaseUrl/me" -Method Patch `
       -Headers $headers -ContentType 'application/json' -Body $body
   ```

   Sustituye `ana.mamani` por un nombre disponible. Si cambia el valor,
   confirma que `nombreusuario_editado` es `true` y `update_username` es `false`.

4. Envía una fotografía con `curl.exe`:

   ```powershell
   $foto = 'RUTA_FOTO'
   curl.exe --include --request POST "$apiBaseUrl/me" `
       --header 'Accept: application/json' `
       --header "Authorization: Bearer $token" `
       --form '_method=PATCH' --form "imagen=@$foto"
   ```

   Sustituye `RUTA_FOTO` por la ruta absoluta de una imagen válida, por
   ejemplo `C:/Fotos/perfil.png`. Confirma **200**, una referencia
   `imagenurl` y una `avatar_url` utilizable desde el dispositivo.

5. Consulta otra vez `GET /api/me` y confirma que mantiene el nombre y la foto
   guardados. Para repetir las comprobaciones sin consumir cambios de una
   cuenta real, utiliza las pruebas automatizadas con datos aislados.

## Fuentes del contrato

La implementación y sus comprobaciones están en los siguientes archivos:

- [Rutas API](../routes/api.php).
- [Consulta del usuario autenticado](../app/Http/Controllers/Api/AuthController.php).
- [Actualización API del perfil](../app/Http/Controllers/Api/PerfilUsuarioController.php).
- [Recurso JSON del perfil](../app/Http/Resources/PerfilUsuarioResource.php).
- [Validación y autorización del perfil](../app/Http/Requests/ActualizarPerfilRequest.php).
- [Servicio compartido de actualización](../app/Services/PerfilUsuarioService.php).
- [Resolución y almacenamiento de fotos](../app/Support/UsuarioAvatar.php).
- [Pruebas de consulta y permisos](../tests/Feature/ApiPerfilConsultaTest.php).
- [Pruebas de edición y acceso](../tests/Feature/ApiPerfilActualizacionTest.php).
- [Pruebas de compatibilidad web](../tests/Feature/PerfilWebActualizacionTest.php).
- [Análisis de las reglas existentes](analisis-api-perfil-flutter.md).
- [Resultados y reproducción de la verificación final](verificacion-api-perfil-flutter.md).
