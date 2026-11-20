# EDT 5.5 — Consulta del recorrido e indicadores

## Integración

GET web `/consulta-recorrido` y GET API `/api/consulta-recorrido` comparten `RecorridoConsultaController`, `RecorridoIndicadoresService` y `ProductoRecorridoConsultaService`. Se añadieron accesos desde los detalles existentes de cosecha y procesamiento. La pantalla mínima mantiene el layout, componentes de operación y tema existentes; no sustituye la vista final de la iteración 6.

Parámetros: `tipo=cosecha|planta`, `partida=<produccionid|loteproduccionpedidoid>`, `desde`, `hasta`, `almacenid`, `per_page` (1–50), `pendientes_page`, `bajas_page`. Para consultar solo indicadores, omitir tipo y partida. Ambos identificadores de tipo/partida se exigen juntos. Un producto genérico de catálogo no es una partida.

## Fuentes y vínculos

- La cosecha parte de `produccion`; mantiene `loteid`, cantidad, unidad y presentación registrada. No agrega otras cosechas del mismo lote. Consulta almacenamientos por `produccionid` y distingue `almacendestinoid` planificado de una recepción.
- Planta parte de `lote_produccion_pedido`. Reutiliza `ProduccionPlantaRecorridoService` (EDT 4.6) para consumos, partidas, recepciones de origen, productos obtenidos, ingresos originales y ubicaciones actuales. No calcula cantidades originales a partir del saldo actual.
- Los orígenes agrícolas recorren las FK de materia prima → detalle de pedido → almacenamiento de cosecha → producción → lote agrícola. Las actividades se consultan una vez por `actividadid`, aunque varios consumos compartan un lote.
- Las etapas proceden de `registro_proceso_maquina_planta`, con sus parámetros registrados, responsable y cierre único. No se crean resultados parciales ni cantidades de etapa.
- Los movimientos conservan su FK de lote de producción, partida y unidad registrada. No se relacionan por referencia textual.
- Los traslados se vinculan mediante `detalle_traslado_planta_mayorista.loteproduccionpedidoid`; los pedidos de distribución mediante `inventario_presentacion_loteid`. No se atribuye a una partida todo pedido del mismo producto.
- Las operaciones agrícolas enlazan el pedido explícito de la recepción o del detalle de cosecha. No se serializan otras líneas del envío. La fecha de recepción no equivale a la salida ni a la ubicación actual.
- Los antecedentes de emisiones conservan las referencias de EDT 4.4. No se modifica ni regenera su snapshot, archivo o contenido.

El conjunto de elementos conserva el contexto autorizado completo. `coincide_filtros` identifica los elementos que responden a la consulta; no convierte la ordenación en una secuencia causal. Los saldos actuales y los ingresos históricos se muestran separados. `antecedentes` y `emisiones_historicas` son contexto, no totales filtrados.

## Indicadores y poblaciones

1. `tareas_pendientes`: número de actividades agrícolas sin `fechafin` autorizadas con `ActividadPermisos`, más asignaciones de planta con el scope existente `pendientes()` (`estado=pendiente`). Operarios ven sus propias asignaciones; jefes/admin consultan dentro de `ProduccionPlantaAcceso`. Las programadas, completadas y canceladas de planta no se cuentan como pendientes; no se incluyen pedidos pendientes de decisión. Las tareas conservan tipo y significado. Las actividades agrícolas no tienen un campo de cancelación independiente.
2. `registros_producto_almacen_bajos`: número de registros `insumo` con almacén autorizado y mínimo configurado cuyo `InventarioExistenciaService::resumen()` devuelve `existencias_bajas=true`. Es un conteo de registros producto–almacén, no de productos distintos ni una suma de cantidades. Se conserva la comparación disponible <= mínimo, el mínimo cero y el mínimo null. El disponible descuenta reservas, bloqueos y vencimientos siguiendo EDT 4.2. No se suman unidades incompatibles.

El total del indicador y el total paginado se obtienen de la misma colección completa ya autorizada y filtrada, antes de extraer cada página. Cada listado conserva su paginación independiente y parámetros. Un indicador sin permiso devuelve null, no cero. Una población autorizada vacía devuelve cero. No hay caché compartida.

Las secciones se consultan sucesivamente: no se promete una fotografía transaccional única de todos los módulos ante escrituras concurrentes. Dentro de cada población, indicador y detalle se materializan juntos y permanecen coherentes en la respuesta.

## Fechas y almacenes

Zona horaria: `config('app.timezone')`, actualmente America/La_Paz. Desde/hasta son fechas inclusivas, deben proporcionarse juntas y el intervalo no puede superar 366 días. Los datetime con zona se convierten a la zona de aplicación; las fechas sin hora permanecen fechas de calendario. Si una fila no tiene fecha y se solicita intervalo, queda como contexto en recorrido y fuera del conteo de pendientes del intervalo.

| Sección / elemento | Campo de fecha y significado | Relación del almacén |
|---|---|---|
| Pendiente agrícola | actividad.fecha_planificada: programación, sin fallback a creación | No aplica: la tarea no tiene almacén directo; se conserva y se indica expresamente |
| Pendiente de planta | asignacion_etapa_planta.creado_en: asignación, no programación de ejecución | Almacén de materias primas o ingreso explícito del lote; siempre autorizado |
| Alertas / existencias actuales | Fecha NO aplica; no son stock histórico | Ubicación actual del insumo |
| Cosecha | produccion.fechacosecha: ejecución de cosecha, fecha sin hora | Sin almacén directo en el evento; su destino planificado es otro elemento |
| Almacenamiento agrícola | produccionalmacenamiento.fechaentrada: ingreso | Almacén del registro; el saldo mostrado se etiqueta actual |
| Origen de planta | Fecha registrada de recepción de la línea, cuando existe | Almacén de la materia prima consumida |
| Actividad en recorrido | actividad.fechafin: cierre; fecha_planificada se conserva como contexto | No aplica a registros sin almacén directo |
| Etapa de planta | registro_proceso_maquina_planta.fecha_registro: registro del cierre único | No aplica: no se inventa almacén propio de la etapa |
| Ingreso de producción | datos_ingreso.fecha conservada o fecha_almacenaje del registro antiguo | Destino original del ingreso, independiente del saldo actual |
| Movimiento | almacen_movimiento.fecha: fecha del movimiento, sin hora | Almacén del movimiento |
| Envío agrícola / traslado | fecha_salida: salida registrada | Envío agrícola sin FK directa de almacén; traslado admite origen o destino autorizado, conservando ambos identificadores permitidos |
| Recepción de envío | recepcion_qr_envio.utilizado_en: confirmación registrada; solo líneas explícitas de la partida consultada | Destino autorizado del traslado; sin almacén directo en las demás líneas de recepción |
| Pedido de distribución | fechapedido: solicitud del pedido | Origen de la línea o cabecera registrada |
| Producción derivada de cosecha | fecha_creacion: creación de la operación industrial vinculada | Contexto del vínculo; los ingresos contienen sus almacenes propios |
| Ubicación actual | Fecha NO aplica; saldo actual | Ubicación actual de la partida |
| Emisiones de certificados | Contexto histórico conservado, no afectado por el intervalo | Autorización independiente del certificado |

`fecha_filtro_aplica` y `almacen_filtro_aplica` acompañan cada elemento. Los almacenes seleccionables y los registros se limitan al mismo ámbito. Un almacén inexistente o ajeno devuelve 404.

## Autorización, ausencias y solo lectura

Se exige autenticación, cuenta activa aprobada y al menos uno de los permisos existentes lotes.view, lote_produccion.view o inventario.view. Cada sección verifica su permiso y su scope. Para datos agrícolas se reutilizan LoteAcceso y ActividadPermisos; para planta ProduccionPlantaAcceso; para inventario AlmacenAcceso; para operaciones de transporte EnvioMovilConsultaService y PuntoVentaAccess. Los movimientos exigen además almacen.movimientos.view. Los antecedentes de certificados usan CertificadoAcceso.

No se exponen nombres ni identificadores de partidas/almacenes no autorizados en alertas, opciones o conteos. Se mantiene el tratamiento parcial del recorrido de EDT 4.6. Una referencia relacionada no amplía los permisos del módulo de destino. Operarios solo reciben sus registros de etapa.

La respuesta distingue selección ausente, colección autorizada sin resultados, dato null, filtro no aplicable e información parcial. Los errores se propagan con el tratamiento Laravel existente; no se convierten en colecciones vacías. Los GET no invocan sincronizaciones, emisión/consumo de QR, movimientos, cambios de estado o generación de certificados. No hay nuevas tablas, paquetes ni cambios en contratos anteriores.

## Verificación

Pruebas aisladas: `tests/Feature/RecorridoIndicadoresTest.php`. Cubren claves de origen y operación; múltiples orígenes y destinos; otra partida del mismo producto; parámetros sin parciales; pendientes por usuario y estados; mínimos por almacén, igualdad, cero y null; disponible con partidas vencidas/bloqueadas; filtros y límites de zona; totales antes de paginar; contexto sin coincidencias y ausencia de vínculos; invitado, falta de permiso y ámbitos ajenos; coherencia web/API y repetición sin escritura en tablas, incluidas emisiones históricas.

Resultados: 11 pruebas nuevas y 9 regresiones seleccionadas aprobadas en PHP 8.2 (20 casos distintos). Las regresiones incluyen aceptación/rechazo, bandejas web, comprobantes y permisos, vencimientos/reservas y antecedentes inmutables. La prueba adicional de envíos confirma traslados y distribución en la base aislada y comprueba exactamente el ID de línea, comprobante y cantidad recibida por partida. Los GET de la nueva consulta se repiten y se compara el contenido de las tablas antes/después, incluidas las emisiones.

Vite compiló los assets existentes. El entorno muestra una advertencia previa: Node 22.11.0 frente al mínimo 22.12 que solicita Vite 7; no se actualizaron dependencias. Blade se compila al verificar las respuestas web. Pint y sintaxis PHP revisados en los archivos nuevos. No se ejecutó la suite completa, Flutter, PHP 8.3/8.4 ni los workflows remotos.

Revisión en Edge sin interfaz visible, con HTML producido por las pruebas aisladas y assets compilados: 1440×1000 y 390×844. Sin desbordamiento horizontal del documento. Capturas y medidas locales privadas en `storage/app/private/edt55-*.png` y `edt55-responsive.json`; no se publican datos de prueba ni credenciales. No se requiere migración ni carga de datos operativos.

### Criterios verificados

- [x] Consulta por partida con origen, actividades y destinos registrados.
- [x] Identificadores y operaciones de procedencia conservados, múltiples orígenes/destinos sin mezclar partidas.
- [x] Pendientes y existencias bajas del ámbito autorizado.
- [x] Fechas y almacenes con significado explícito, incluyendo secciones donde no aplican.
- [x] Indicadores calculados desde el mismo conjunto completo que su detalle paginado.
- [x] Ausencias, información parcial y consultas sin coincidencias identificadas; consultas sin efectos operativos.
