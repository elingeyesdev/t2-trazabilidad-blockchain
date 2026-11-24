# Verificación de cierre MVP — AgroFusion Mobile (Flutter)

## 1. Alcance validado
- **Consulta pública de trazabilidad sin sesión (`EDT 6.5` y `EDT 6.6`):**
  - Acceso público desde `LoginScreen` y acceso rápido desde `HomeScreen`.
  - Escaneo de QR (`mobile_scanner`), ingreso manual de código (`TRZ-PDV-...`, `TRZ-...`) y extracción automática desde URLs públicas (`/trazabilidad/{codigo}`, `?codigo=...`).
  - Vista pública de consumidor (`TrazabilidadPublicaScreen`) con cabecera del producto, origen agrícola, punto de venta, respaldo real de certificaciones/blockchain, línea de tiempo agrupada por etapas expandibles, buscador local, visor de evidencias, mapa externo y enlace a versión web pública.
- **Cierre de módulos operativos (`EDT 6.7`):**
  - Detalle y resolución de incidencias (`IncidenteDetailScreen`) con nota obligatoria (`PATCH /api/incidentes/{id}/resolver`) restringida a roles operativos con `incidentes.resolve`.
  - Detalle de certificaciones (`CertificacionDetailScreen`) con respaldo blockchain y descarga de PDF, y detalle de documentos de entrega (`DocumentoDetailScreen`) con descarga y vista previa.
  - Visualización de `codigo_trazabilidad` y acceso directo a la trazabilidad pública desde `Insumos` y existencias de almacén PDV (`AlmacenDetailScreen`).
- **Integración multi-rol, resiliencia y responsividad (`EDT 6.8`):**
  - Cobertura automatizada de los 9 actores (`consumidor sin login`, `admin`, `jefe_agricultor`, `agricultor`, `jefe_planta`, `planta`, `transportista`, `mayorista`, `minorista`) en `test/mvp_multirol_integracion_test.dart`.
  - Verificación de expiración de sesión (`401`), reconexión tras fallo de red y renderizado sin `RenderFlex overflow` en pantallas pequeñas (`320×568`) con texto grande (`1.3×`) en `test/mvp_resiliencia_layout_test.dart`.

## 2. Comandos de verificación y compilación release

```powershell
cd Mobile

# Formato, análisis estático y suite completa de pruebas
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub

# Compilación Web (apuntando al backend configurado)
flutter build web --no-pub --dart-define=API_BASE_URL=https://TU-BACKEND/api

# Compilación APK release para Android
flutter build apk --release --no-pub --dart-define=API_BASE_URL=https://TU-BACKEND/api
```

El artefacto Android se genera en `Mobile/build/app/outputs/flutter-apk/app-release.apk`.
