# AgroFusion para Flutter

Este proyecto prepara la aplicación móvil de trazabilidad agrícola para el
equipo que migra AgroFusion desde React Native. Incluye navegación inicial,
cliente HTTP compartido, almacenamiento seguro del token, comprobación de
conexión, inicio de sesión, registro pendiente de aprobación y cierre de sesión
con Laravel. La restauración se incorpora en el bloque de estados de la issue
#4; el perfil y la navegación por permisos corresponden a la issue #5.

## Iniciar sesión

Al abrir la aplicación, ingresa el correo y la contraseña de una cuenta activa
y aprobada en Laravel. Flutter envía `POST /api/login` sin credenciales previas,
guarda el token y confirma el perfil con `GET /api/me` antes de mostrar el inicio.
Si falla esta confirmación, limpia el token recién guardado y mantiene el login.

El formulario conserva la contraseña tal como la escribes, permite mostrarla
y bloquea envíos duplicados durante la carga. Los errores de Laravel aparecen
en el formulario; las cuentas pendientes o inactivas permanecen sin acceso.
La acción **Comprobar conexión** está disponible desde la pantalla de login.

Este bloque inicia la sesión dentro de la ejecución abierta de la aplicación.
La restauración al volver a abrirla se incorpora en el bloque de estados de
autenticación. Consulta el
[análisis de autenticación](docs/analisis-autenticacion-flutter.md) para revisar
el contrato y la división de actividades.

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
No almacena contraseñas. La integración del login en la issue #4 debe guardar
el token real recibido de Laravel.

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
- `lib/navigation/`: nombres de rutas.
- `lib/screens/auth/`: login, registro y confirmación de aprobación pendiente.
- `lib/screens/home/home_screen.dart`: inicio para el usuario autenticado.
- `lib/screens/connection/`: estados de la comprobación de conexión.
- `lib/widgets/`: componentes compartidos de carga y error con reintento.
- `test/`: pruebas de arranque, configuración, HTTP, sesión y navegación.
- `android/`, `ios/` y `web/`: configuración de cada plataforma.
- [Arquitectura Flutter](docs/arquitectura-flutter.md): responsabilidades y
  pasos para incorporar pantallas y servicios.
- [Verificación con Laravel](docs/verificacion-conexion-laravel.md): preparación
  del servidor, prueba real, capturas y límites de la evidencia.
- [Análisis de React Native](docs/analisis-migracion-flutter.md): flujos,
  contrato del backend y decisiones para continuar la migración.
