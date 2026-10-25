# AgroFusion para Flutter

Este proyecto prepara la aplicación móvil de trazabilidad agrícola para la
migración desde React Native. Esta etapa incluye el arranque de Flutter y una
pantalla inicial; la conexión con Laravel y la sesión se incorporan en los
siguientes bloques de la issue #3.

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

## Ubicar el código

Los archivos de este bloque se distribuyen así:

- `lib/main.dart`: punto de entrada.
- `lib/app.dart`: configuración de `MaterialApp` y tema.
- `lib/screens/home/home_screen.dart`: pantalla inicial.
- `test/app_test.dart`: comprobación de arranque.
- `android/`, `ios/` y `web/`: configuración de cada plataforma.
- [Análisis de React Native](docs/analisis-migracion-flutter.md): flujos,
  contrato del backend y decisiones para continuar la migración.
