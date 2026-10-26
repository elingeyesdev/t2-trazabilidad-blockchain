# AgroFusion para Flutter

Este proyecto prepara la aplicación móvil de trazabilidad agrícola para el
equipo que migra AgroFusion desde React Native. Incluye navegación inicial,
cliente HTTP compartido, almacenamiento seguro del token, comprobación de
conexión, inicio de sesión, registro pendiente de aprobación, cierre y
restauración de sesión con Laravel y consulta del perfil autenticado.
Incluye edición del nombre de usuario y fotografía, y navegación según los
permisos efectivos recibidos de Laravel, con consultas de solo lectura.

## Iniciar sesión

Si no hay una sesión guardada, ingresa el correo y la contraseña de una cuenta activa
y aprobada en Laravel. Flutter envía `POST /api/login` sin credenciales previas,
guarda el token y confirma el perfil con `GET /api/me` antes de mostrar el inicio.
Si falla esta confirmación, limpia el token recién guardado y mantiene el login.

El formulario conserva la contraseña tal como la escribes, permite mostrarla
y bloquea envíos duplicados durante la carga. Los errores de Laravel aparecen
en el formulario; las cuentas pendientes o inactivas permanecen sin acceso.
La acción **Comprobar conexión** está disponible desde la pantalla de login.

Consulta el
[análisis de autenticación](docs/analisis-autenticacion-flutter.md) para revisar
el contrato y la división de actividades.

Para repetir login, registro pendiente, cierre y restauración con una base
aislada, consulta la
[verificación de autenticación con Laravel](docs/verificacion-autenticacion-laravel.md).

## Restaurar y verificar la sesión

Al abrir la aplicación, Flutter lee el token guardado y consulta `GET /api/me`
antes de mostrar el inicio. Sin token, presenta el login sin realizar esa
consulta. Al volver al primer plano, también revalida una sesión autenticada
para comprobar que la cuenta siga autorizada.

Cada consulta sustituye el perfil completo, los roles, las capacidades de
edición y los permisos efectivos. No combina permisos anteriores con los
recibidos. El menú incorpora los permisos concedidos y retira los revocados;
si estás en un módulo que dejó de estar autorizado, presenta acceso denegado.
Las consultas de un módulo abierto se renuevan después de verificar la sesión
y sus respuestas anteriores no vuelven a mostrar registros.

Para una sesión ya conocida, la revalidación también exige el mismo
identificador de cuenta, incluso al reintentar después de un fallo. Una
respuesta de otra cuenta bloquea el acceso hasta recuperar el perfil correcto
o cerrar la sesión. Esta identidad se mantiene solo en memoria: el
almacenamiento conserva exclusivamente el token y no guarda copias de roles,
permisos o datos de perfil como prueba de autorización.

Mientras verifica, muestra **Verificando sesión...**. Si falla la conexión,
el servidor o el acceso al almacenamiento, bloquea las pantallas y ofrece
**Reintentar** o **Cerrar sesión**. Los fallos de red conservan el token para
volver a verificarlo; no se utilizan datos guardados como prueba de acceso.

Un token rechazado o una cuenta pendiente o inactiva vuelven al login después
de limpiar sus credenciales. Si falla esa limpieza, el acceso permanece
bloqueado hasta resolver el almacenamiento mediante el reintento.

Un `401` de una petición autenticada también retira al usuario en memoria.
Un `403` de permisos de otro módulo y los errores de comunicación de ese
módulo conservan la sesión verificada. Las respuestas antiguas no invalidan
una sesión nueva que haya reemplazado el token.

## Solicitar una cuenta

Desde el login, selecciona **Crear cuenta**. Completa nombre, apellido, correo,
nombre de usuario, contraseña y confirmación. El teléfono es opcional.
La API asigna el rol `agricultor`; el formulario utiliza ese contrato y no
ofrece un selector de roles que el servidor ignore.

Flutter envía `POST /api/register` sin Bearer y presenta los errores de Laravel
junto a los campos. La comprobación local de campos obligatorios y coincidencia
de contraseñas orienta la entrada; Laravel aplica sus reglas de validación.

Una respuesta válida contiene una cuenta `pendiente` y ningún token. La
pantalla muestra **Solicitud enviada** y el mensaje del servidor. El registro
no autentica al usuario ni guarda credenciales de sesión. Al volver al login,
conserva el correo de la solicitud y limpia la contraseña.

Un administrador debe aprobar la cuenta antes de que pueda iniciar sesión.
Si intentas acceder mientras está pendiente, el login muestra el mensaje
de Laravel y mantiene bloqueado el inicio autenticado.

## Consultar el perfil

Después de iniciar sesión, selecciona **Mi perfil**. La pantalla consulta
`GET /api/me` con el token de la sesión y muestra nombre completo, nombre de
usuario, correo, teléfono, CI/NIT, todos los roles y las fechas disponibles.
Las fechas se presentan en la zona local; los datos opcionales vacíos aparecen
como **Sin registrar** y una cuenta sin roles muestra **Sin roles asignados**.

El avatar usa `avatar_url`, con soporte para imágenes HTTP/HTTPS y referencias
heredadas de imágenes PNG, JPEG, WEBP o GIF embebidas. Si no hay una foto o
no se puede cargar, muestra un icono de sustitución. No adjunta el token de
sesión a las descargas de imágenes.

Selecciona **Actualizar perfil** para recuperar los cambios del servidor.
La consulta actualiza también el usuario que muestra el inicio y evita
peticiones duplicadas durante la carga. El modelo conserva los permisos
efectivos y las capacidades de edición recibidas; un rol por sí solo no
genera permisos locales.

La ruta `/profile` requiere una sesión verificada. Si `me` rechaza el token
o la cuenta, vuelve al login y limpia sus credenciales. Si no puede verificar
la sesión por un error de conexión, servidor, formato o almacenamiento,
presenta la recuperación de sesión con reintento antes de mostrar datos.

## Editar el nombre de usuario y la fotografía

Desde **Mi perfil**, selecciona **Editar perfil**. Las capacidades devueltas
por Laravel determinan qué campos puedes cambiar. El nombre de usuario
admite un solo cambio; después, el formulario mantiene disponible la
fotografía si el servidor lo permite. Nombre personal, apellido, correo,
roles y permisos se consultan sin enviarlos en esta actualización.

Usa **Seleccionar foto** para abrir el selector de archivos del sistema.
El formulario admite JPG/JPEG, PNG, WEBP y GIF de hasta 2 MB. Las
comprobaciones locales orientan la selección; Laravel valida el contenido,
la unicidad del nombre y la autorización en cada petición.

La selección funciona con el plugin oficial
[`file_selector`](https://pub.dev/packages/file_selector), usando bytes
compatibles con web. Cancelar el selector conserva el borrador.
**Quitar selección** retira solo la foto elegida del formulario; no elimina
la fotografía guardada en Laravel. Al regresar del selector, la aplicación
vuelve a verificar el perfil sin descartar el nombre que estás escribiendo.

**Guardar cambios** envía solo los campos modificados. Para cambiar el nombre
utiliza `PATCH /api/me` con JSON; si hay una fotografía, envía `POST /api/me`
multipart con `_method=PATCH` y el archivo `imagen`. La confirmación sustituye
el perfil y las capacidades en memoria y presenta **Perfil actualizado
correctamente.** Se bloquean los envíos duplicados y la salida durante el
guardado o la selección.

Los errores `422` aparecen junto al campo y conservan el borrador. Ante un
`403`, la aplicación consulta otra vez el perfil para actualizar las
capacidades y comprobar la autorización de la cuenta. Un `401` retira la
sesión mediante el cliente compartido.

Si falla la comunicación durante una escritura, el resultado puede ser
incierto. El formulario ofrece **Consultar perfil** y bloquea otro guardado
hasta completar esa consulta, incluso si cierras y vuelves a abrir la edición.
La aplicación no repite automáticamente una actualización.

## Navegar según tus permisos

El inicio muestra **Mi perfil** y los módulos de consulta habilitados por
`permissions` de `GET /api/me`. Tener un rol llamado `admin` no habilita todos
los destinos. Los permisos directos también habilitan sus opciones, aunque
la cuenta no tenga roles. Sin permisos de módulos, puedes consultar tu perfil
y comprobar la conexión.

Las opciones disponibles y sus permisos son:

| Opción | Permiso efectivo |
| --- | --- |
| Lotes, Actividades y Cosechas | `lotes.view` |
| Almacenes e Insumos | `inventario.view` |
| Movimientos de almacén | `almacen.movimientos.view` |
| Certificaciones | `certificaciones.view` |
| Pedidos | `pedidos.view` |
| Incidentes | `incidentes.view` |
| Rutas | `rutas_multi.view` |
| Asignaciones | `asignaciones.view` |
| Documentos de entrega | `documentos.view` |
| Usuarios | `usuarios.admin` |

Selecciona una opción para consultar registros reales de Laravel. La pantalla
muestra los campos resumidos del módulo, permite **Actualizar lista** y ofrece
**Anterior** y **Siguiente** cuando el servidor pagina el resultado. Una lista
sin registros presenta **No hay registros disponibles.** Estos destinos
cubren la consulta: no incluyen creación, edición, eliminación ni descargas
de documentos. Los demás flujos de negocio de React Native requieren su
propia migración.

El acceso directo a una ruta `/modules/...` también comprueba el permiso
antes de enviar la consulta. Un `403` de Laravel presenta **Acceso no
autorizado** y permite **Volver al inicio**; conserva la sesión. Un `401`
reutiliza la retirada de sesión. Los errores de consulta ofrecen **Reintentar**.
Si una actualización del perfil retira un permiso, el menú oculta su opción
y la ruta abierta deja de mostrar los registros.

Laravel vuelve a comprobar autorización y acceso a los datos en cada petición.
Ocultar una opción en Flutter no sustituye esas comprobaciones ni los filtros
de pertenencia o ámbito de los controladores. Las excepciones contextuales
del servidor no generan permisos adicionales en el menú.

## Cerrar sesión

Desde el inicio autenticado, selecciona **Cerrar sesión** en la barra superior.
La aplicación oculta el usuario mientras procesa `POST /api/logout`, elimina
el token de esa sesión y vuelve al login. El botón de volver no recupera el
inicio autenticado. Un `401` de logout indica que el token ya no autoriza el
acceso y permite completar el cierre local.

Si falla la comunicación con Laravel, se limpia la sesión del dispositivo y
el login informa que no se pudo confirmar el cierre en el servidor. Si falla
el borrado del almacenamiento, la aplicación mantiene el acceso bloqueado
y ofrece **Reintentar** hasta poder eliminar las credenciales locales.

El cierre actúa sobre la sesión utilizada: conserva las otras sesiones de
Laravel y evita borrar un token distinto si otro login reemplazó el anterior
durante la petición.

## Preparar el entorno

Usa Flutter estable 3.44.5, que incluye Dart 3.12.2, para reproducir este bloque.
El proyecto incluye soporte para Android, iOS y web. Android e iOS conservan
el identificador `com.agrofusion.mobile` de la aplicación React Native.

Para ejecutar la versión web en Windows, necesitas Microsoft Edge o Google
Chrome. Para compilar Android, necesitas el SDK de Android. La compilación
de iOS requiere macOS y Xcode.

## Instalar las dependencias

Desde la raíz del repositorio, entra al proyecto:

```powershell
cd Mobile
```

Descarga las dependencias declaradas en `pubspec.yaml`:

```powershell
flutter pub get
```

Si actualizas una instalación anterior a la incorporación del selector de
fotografías, detén la aplicación y regenera los archivos derivados desde
`Mobile/` antes de volver a ejecutar o compilar:

```powershell
flutter clean
flutter pub get
```

Esto evita reutilizar un registro de plugins generado sin `file_selector`.

Incluye `pubspec.lock` en los commits para que el equipo utilice las mismas
versiones de dependencias. Los archivos generados, las cachés y la
configuración local del SDK se excluyen mediante `.gitignore`.

## Ejecutar la aplicación

Consulta los dispositivos disponibles:

```powershell
flutter devices
```

Para abrir la aplicación en Microsoft Edge, ejecuta:

```powershell
flutter run -d edge
```

Si utilizas Google Chrome, ejecuta:

```powershell
flutter run -d chrome
```

La pantalla debe mostrar **AgroFusion** y **Trazabilidad agrícola**. Pulsa `q`
en la terminal para detener la ejecución.

## Verificar el proyecto

Desde `Mobile/`, comprueba el formato, el análisis estático y el arranque:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

La prueba ejecuta el punto de entrada y verifica que aparece la pantalla
inicial sin errores. Para comprobar también la compilación web, ejecuta:

```powershell
flutter build web
```

El resultado se genera en `build/web/`, una carpeta excluida de Git.

Las pruebas de servicios y navegación utilizan respuestas simuladas y el
almacenamiento de prueba del paquete. Comprueban el comportamiento del código;
no verifican la conexión con Laravel real ni el cifrado en un dispositivo.

## Configurar la API

Define `API_BASE_URL` al ejecutar o compilar Flutter. La URL incluye el prefijo
`/api` y se normaliza con una barra final. El valor de desarrollo por defecto
es `http://127.0.0.1:8000/api`.

Para ejecutar en Edge contra Laravel en el mismo equipo, usa:

```powershell
flutter run -d edge --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

Para el emulador oficial de Android, usa la dirección del equipo anfitrión:

```powershell
flutter run -d ID_DISPOSITIVO --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Sustituye `ID_DISPOSITIVO` por el identificador que muestra `flutter devices`.
En un teléfono físico, utiliza la IP local del equipo que ejecuta Laravel y
comprueba que el teléfono puede acceder a su puerto. `localhost` dentro del
teléfono identifica al propio teléfono.

`--dart-define` configura la aplicación al compilar; cambia el valor y vuelve
a ejecutarla cuando cambies de servidor. No guardes contraseñas ni tokens en
esa configuración. El cliente usa únicamente el servidor configurado y no
cambia automáticamente entre desarrollo y producción.

En Android se permite HTTP en la variante `debug` para trabajar con Laravel
local. Usa HTTPS para producción y para probar iOS sin agregar excepciones
de transporte.

## Comprobar la conexión

Con Laravel disponible en la URL configurada, sigue estos pasos:

1. Abre **Comprobar conexión** desde la pantalla inicial.
2. Espera mientras se muestra **Comprobando conexión...**.
3. Confirma que aparece **Conexión disponible**. El servicio exige una
   respuesta JSON con `ok` booleano igual a `true` desde `GET /api/test-api`.
4. Detén el servidor y vuelve a abrir la pantalla para comprobar el error.
5. Inicia el servidor y pulsa **Reintentar** para recuperar la conexión.
6. Usa el botón de volver para regresar al inicio.

La comprobación es pública: no lee ni envía un token. Si Laravel no está
ejecutándose, el estado de error es el resultado esperado. En web, Laravel
también debe permitir el origen de Flutter mediante CORS.

Para preparar un backend aislado y repetir la prueba completa, consulta
[Verificar la conexión con Laravel](docs/verificacion-conexion-laravel.md).

## Preparar la sesión

`SessionStorage` utiliza
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage)
para leer, guardar y eliminar exclusivamente la clave del token de AgroFusion.
No almacena contraseñas. El servicio de autenticación guarda el token real
recibido de Laravel y confirma el perfil antes de dar acceso.

En iOS se usa Keychain con acceso cuando el dispositivo está desbloqueado,
sin sincronizar el token con otros dispositivos. El proyecto incluye los
entitlements de Keychain para las tres configuraciones de compilación. En
Android se desactiva la copia de seguridad automática para evitar restaurar
credenciales sin su clave de cifrado.

El soporte web del paquete utiliza WebCrypto y está documentado como
experimental. Utiliza HTTPS o `localhost` para esa plataforma. La validación
de almacenamiento en Android e iOS requiere ejecutar en cada plataforma;
las pruebas con almacenamiento simulado no la reemplazan.

## Ubicar el código

Los archivos de este bloque se distribuyen así:

- `lib/main.dart`: punto de entrada.
- `lib/app.dart`: creación del cliente compartido, tema y registro de rutas.
- `lib/config/`: URL base y timeout.
- `lib/models/`: usuario autenticado, conectividad y errores de la API.
- `lib/controllers/`: estado observable de login, registro y cierre de sesión.
- `lib/services/`: HTTP, autenticación, conectividad y almacenamiento del token.
- `lib/navigation/`: nombres de rutas y catálogo de módulos con sus permisos.
- `lib/screens/auth/`: login, registro y confirmación de aprobación pendiente.
- `lib/screens/home/home_screen.dart`: inicio para el usuario autenticado.
- `lib/screens/connection/`: estados de la comprobación de conexión.
- `lib/screens/modules/`: consultas de módulos y acceso denegado.
- `lib/widgets/`: componentes compartidos de carga y error con reintento.
- `test/`: pruebas de arranque, configuración, HTTP, sesión y navegación.
- `android/`, `ios/` y `web/`: configuración de cada plataforma.
- [Arquitectura Flutter](docs/arquitectura-flutter.md): responsabilidades y
  pasos para incorporar pantallas y servicios.
- [Verificación con Laravel](docs/verificacion-conexion-laravel.md): preparación
  del servidor, prueba real, capturas y límites de la evidencia.
- [Análisis de React Native](docs/analisis-migracion-flutter.md): flujos,
  contrato del backend y decisiones para continuar la migración.
