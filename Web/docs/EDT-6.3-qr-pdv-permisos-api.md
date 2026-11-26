# EDT 6.3 — Códigos PDV y permisos operativos API

## Hallazgos y alcance

La autenticación sigue siendo Sanctum; `Usuario` usa permisos Spatie del guard `web`. Las rutas aplican `ActionPermissionMiddleware` y la autorización de ámbito está en los helpers/servicios compartidos (no hay un directorio de Policies). No se cambiaron roles, permisos persistidos, guards ni operaciones ajenas.

Bloqueos demostrados por las pruebas:

1. El jefe agrícola puede asignar actividades, pero Mobile consultaba `/api/usuarios`, que exige `usuarios.admin`. Continúa devolviendo 403 para roles operativos; Mobile ahora consulta `/api/actividades/responsables`, limitado al propio jefe y a empleados activos/aprobados de su equipo. Ya no oculta un error de autorización devolviendo solo al jefe.
2. Los formularios móviles de asignación y cosecha usaban catálogos administrativos (`catalogos.view`), ausente en sus roles. Se añadieron tres consultas de opciones para las operaciones existentes; no se concedió edición de catálogos.
3. El minorista tiene `punto_venta.view`, no `inventario.view`. Se añadió una lectura PDV propia; el inventario general y sus escrituras mantienen los permisos anteriores.
4. La selección y asignación de responsables de incidencias existían en web/servicios, pero faltaban rutas API equivalentes. Las nuevas rutas reutilizan `IncidenteReferenciaService` y `IncidenteSeguimientoService`.
5. Los documentos internos guardados en `documentos_entrega` tenían protección en sus controladores, pero faltaba prohibir su acceso estático. Se extendieron los bloqueos de Apache, Nginx y `artisan serve`; no se movieron ni publicaron archivos.

## Matriz real de los ocho roles

La tabla describe los permisos efectivos predeterminados. Cada operación sigue exigiendo su permiso concreto; el nombre del rol no sustituye la autorización. No se agregaron permisos a la matriz.

| Operación | admin | jefe_agricultor | agricultor | jefe_planta | planta | transportista | mayorista | minorista |
|---|---|---|---|---|---|---|---|---|
| Aprobar solicitudes | Sí, solicitudes pendientes | No | No | No | No | No | No | No |
| Administrar catálogo | Según permisos existentes | No | No | No | No | No | No | No |
| Opciones de tipo/prioridad para actividad | Lectura | Lectura | No | No | No | No | No | No |
| Opciones de unidades para cosecha | Lectura | Lectura | Lectura | No | No | No | No | No |
| Consultar responsables de actividad | No operativo | Su equipo y él mismo | No | No | No | No | No | No |
| Asignar actividad | No | Lotes propios/de equipo | No | No | No | No | No | No |
| Inventario PDV específico | Supervisión | No | No | No | No | No | No | PDV propios |
| Reportar incidencia | No | No | No | No | No | Sus viajes | No | No |
| Consultar incidencias | Supervisión | Ámbito agrícola propio | No | Traslados de su planta | No | Sus viajes | Distribución propia | No |
| Asignar responsable faltante/resolver incidencia | No | Ámbito agrícola propio | No | Traslados de su planta | No | No | Distribución propia | No |

### Rutas, condiciones y fuentes

| Método y ruta | Regla y estado | Fuente |
|---|---|---|
| `POST /gestion-usuarios/{usuario}/aprobar` (web) | Administrador con `solicitudes.approve`, solicitud pendiente y rol solicitado admitido; para transportista exige flota | `GestionUsuariosController::aprobarSolicitud/authorizeAprobar`, `CuentaEstado`, `permission_matrix` |
| `GET /api/usuarios` | Administración global con `usuarios.admin`; no es un selector operativo | Rutas API y matriz existentes |
| `GET /api/catalogos-operativos/{catalogo}` | Solo `tipoactividades`, `prioridades`, `unidadesmedida`. Admin necesita `catalogos.view`; tipos/prioridades requieren jefe agrícola con `lotes.create`; unidades requieren campo con `lotes.view` | `SelectorOperativoController`, formularios Mobile y asignación/cosecha existentes |
| `GET /api/actividades/responsables` | Jefe agrícola con `lotes.view`; solo él y empleados agrícolas activos/aprobados bajo `supervisor_usuarioid`; sin correos ni datos del perfil | `UsuarioRol::idsEmpleadosOperativosDeJefeAgricultor/esResponsableActividadPermitido`, validación de `ActividadController` |
| `POST /api/actividades` | Asignación por jefe agrícola, permiso de ruta y lote gestionable; fase y detalle válidos. Reasignación mantiene las reglas de update, el cierre confirmado no se altera | `ActividadController`, `LoteAcceso`, controlador web y trazabilidad agrícola |
| `GET /api/punto-venta/inventario[/{insumo}]` | `punto_venta.view` y `PuntoVentaAccess`; admin supervisa, minorista únicamente su almacén | `PuntoVentaAccess`, `InsumoController` |
| `GET /api/incidentes/responsables?afectado_tipo=...&afectado_id=...` | Actor operativo con creación o actualización, operación visible y ámbito compatible. El transportista puede seleccionar al responsable inicial de un viaje propio; eso no le concede resolución | Servicios de incidencia existentes |
| `POST /api/incidentes` | Transportista con `incidentes.create`, referencia real autorizada y responsable elegible; estado inicial controlado por servidor | `IncidenteRegistroRequest`, servicios existentes |
| `PATCH /api/incidentes/{incidente}/asignar` | `incidentes.update` más responsable por ámbito; solo abierto/pendiente y sin responsable previo. No habilita reasignaciones existentes | `IncidenteSeguimientoService::actualizar` |
| `PATCH /api/incidentes/{incidente}/resolver` | `incidentes.resolve`, responsable por ámbito, referencia visible y explicación; cierre idempotente, otra solución da 409 | `IncidenteSeguimientoService::resolver` |

La aprobación de usuarios sigue siendo web: Mobile no implementa ese flujo ni llama una API de aprobación. No se inventó una nueva facultad de aprobación para jefes. Las lecturas administrativas de catálogos y sus escrituras conservan sus rutas y permisos. Las opciones operativas no exponen un directorio de usuarios.

## Identidad trazable y contrato PDV

La entidad con `codigo_trazabilidad` es **Insumo en el almacén vinculado a un PuntoVenta**. Un producto de catálogo sin almacén no es una existencia PDV. Las presentaciones y partidas (`InventarioPresentacionLote`) no reciben códigos adicionales. Una existencia puede contener varias partidas: el recorrido público mantiene sus referencias y orígenes explícitos; el QR no afirma identificar una única partida si hay varias. Nunca se reconstruye el origen por nombre del producto.

Se conserva la estructura de `/api/insumos` y `/api/insumos/{id}`. El serializador compartido añade los mismos campos a listado, detalle y respuestas de registro/actualización, y a las nuevas lecturas PDV:

```json
{
  "insumoid": 123,
  "codigo_trazabilidad": "TRZ-PDV-01234567-89AB-4CDE-8FAB-0123456789AB",
  "trazabilidad_url": "https://dominio-configurado/trazabilidad/TRZ-PDV-01234567-89AB-4CDE-8FAB-0123456789AB",
  "trazabilidad_estado": "disponible"
}
```

URL generada con la ruta nombrada `trazabilidad.publica` y normalización del EDT 6.1. Se usa `app.public_url` (`APP_PUBLIC_URL`) o `app.url` (`APP_URL`), con esquema HTTP/HTTPS y sin datos de autenticación. No se fija localhost ni se utiliza el Host arbitrario del cliente. La respuesta conserva el código almacenado, incluso si es legacy; la URL utiliza su forma normalizada.

Estados: `disponible`, `sin_codigo_todavia` (existencia PDV elegible), `no_aplica` (catálogo/otra entidad) y `codigo_no_admitido` (código previo fuera de los formatos públicos). En los últimos tres la URL es null. No se reemplazan códigos legacy para hacerlos pasar por válidos.

El alta de una existencia PDV genera el UUID ya utilizado por recepciones conservadas; las dos variantes de recepción y el servicio anterior reutilizan el mismo generador. El índice único existente impide persistir duplicados concurrentes. La regularización usa actualización condicional: dos procesos no sobrescriben el primer código asignado. Los GET y Resources no generan códigos, modifican existencias ni completan antecedentes. Sanctum conserva su auditoría normal `last_used_at` de tokens.

### Regularización controlada

Desde `Web`, con el entorno/base correctos y respaldo operativo según el despliegue:

```powershell
$env:APP_ENV = 'review' # Solo para el entorno local; evita el guard local del proyecto.
php artisan trazabilidad:regularizar-pdv
php artisan trazabilidad:regularizar-pdv --aplicar
```

Sin `--aplicar` solo informa faltantes y códigos no admitidos. Con `--aplicar` procesa únicamente insumos con almacén realmente relacionado por FK con un PDV y código vacío. Es repetible, no cambia stock, partidas, nombres, estados ni vínculos. Los códigos anteriores no admitidos requieren revisión manual autorizada; quedan contabilizados, sin reemplazo automático. No se ejecutó esta regularización en la base operativa como parte de la implementación.

## Archivos

Se conserva la publicación explícita del EDT 6.1: aprobación administrativa, copia privada saneada, endpoint público controlado y `no-store`. Una evidencia aprobada se entrega anónimamente; no se incluye en la consulta de otro producto. El retiro bloquea su endpoint y elimina su aparición pública. Las firmas de recepción, evidencias de actividad y comprobantes mantienen autenticación y ámbito. Se rechazan referencias de documento con traversal o rutas absolutas.

Los prefijos estáticos `actividades_evidencia`, `documentos_entrega`, `certificados`, `recepciones-envio`, `evidencias_publicadas` y `actividades_privadas` se deniegan en `/storage/` mediante las configuraciones del repositorio. No se aprobó/revocó ningún archivo operativo automáticamente. Al desplegar debe aplicarse la configuración de Apache/Nginx; si una CDN conservó copias públicas antiguas, debe invalidarlas. No se ejecutaron Apache, Nginx ni una CDN en esta revisión.

## Verificación

- PHP 8.2.4: verificación final de `PdvTrazabilidadInventarioTest`, `ApiPermisosOperativos63Test`, `ArchivosPublicos63Test`, `SeguridadBaseRbacTest`, `InsumosAccessTest` y `ApiAccessTest`: **34 pruebas, 3542 aserciones, aprobadas** (`storage/logs/edt63-final-correccion.log`).
- En la regresión seleccionada también aprobaron `PermissionMatrixAlineacionTest`, `IncidenteSeguimientoTest`, `ApiEnviosRecepcionQrTest`, `EvidenciaPublicacionTest` y `SolicitudUsuarioTest`. El barrido global de autenticación se adaptó al parámetro enumerado del nuevo selector y se volvió a verificar completo. No se eliminó ninguna protección del test.
- Flutter 3.47.9 / Dart 3.13.7: `flutter test --no-pub test/actividad_assignment_test.dart` (**4 aprobadas**) y `flutter test --no-pub test/cosecha_flow_test.dart` (**2 aprobadas**). Se comprobaron sus rutas reales y se actualizaron los contratos simulados de los selectores.
- Dar formato a los tres archivos Dart con `dart format` y a los archivos PHP nuevos con Pint: correcto. Sintaxis y `git diff --check`: comprobados.
- HTTP anónimo contra el router local: `/storage/documentos_entrega/interno.pdf`, `/storage/actividades_evidencia/interna.png`, `/storage/certificados/interno.pdf` y `/storage/recepciones-envio/firma.png` responden **403**. La prueba aislada de publicación confirma una imagen aprobada anónima con 200 y, tras el retiro, 404.

Las pruebas Feature usan SQLite aislado y autenticación/middleware reales; no se desactivaron. Las pruebas Flutter usan HTTP simulado y no constituyen un recorrido de extremo a extremo contra Laravel. No se ejecutó la suite completa, ni PHP 8.3/8.4, ni se afirmó CI en verde: no se subieron estos cambios. No corresponde compilar frontend: no se modificaron vistas ni estilos. No se alteraron la base operativa, las cantidades ni las aprobaciones de archivos.