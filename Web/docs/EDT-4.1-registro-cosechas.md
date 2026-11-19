# EDT 4.1 — Registro compartido de cosechas

## Modelo y reglas reutilizadas

La cosecha es `Produccion` (`produccion`, PK `produccionid`), asociada a `Lote`. La presentación real de campo es `CatalogoTamanoConteo` (`catalogo_tamano_conteo`): `peso_promedio_kg` significa **kg por unidad de producto**, y `conteo_por_empaque` indica **unidades por empaque**. No se confunde con `InsumoPresentacion`, que corresponde a presentaciones de traslado/producto terminado.

`CosechaRegistroService` centraliza registro, validación, alcance, conversión y transacción. Web y API conservan la foto obligatoria, el destino Almacenamiento y la transición a Cosechado con historial. No se crean movimientos ni se modifica stock; certificación y envío al almacén conservan su flujo posterior.

Se reutilizan `LoteAcceso`, `UsuarioRol`, `LoteTrazabilidadService` y el permiso `lotes.view`: el jefe registra dentro de su equipo y el operario necesita una actividad de cosecha pendiente asignada. El administrador conserva supervisión sin operaciones de negocio. El lote debe cumplir la fase de cosecha existente. No se agrega una restricción por lote/fecha ni una prohibición de fechas futuras.

Las presentaciones deben existir, estar activas, tener empaque activo, peso positivo y conteo positivo. La pertenencia al producto usa `PedidoCatalogo::insumoIdsRelacionadosParaCalibres`, la misma regla de especie del catálogo existente. Registrar, consultar catálogo y previsualizar no crean factores ni sincronizan plantillas. Se mantiene como valor predeterminado únicamente el calibre planificado en el lote; si no existe, el cliente elige uno del catálogo autorizado.

## Precisión y fórmula

Se utiliza `brick/math`, dependencia **ya presente en composer.lock**, sin agregar paquetes ni exigir BCMath. Las operaciones reciben cadenas decimales; no se calcula con floats.

1. Cantidad original: positiva, hasta 12 enteros y 6 decimales; máximo `999999999999.999999`.
2. Kg equivalentes = cantidad × factor de la unidad de peso. Se reutilizan los factores existentes: kg=1, g=0.001, t=1000, qq=46, lb=0.453592. Las unidades desconocidas o de otra categoría se rechazan, sin asumir kg.
3. La equivalencia en kg se redondea **una vez** a 6 decimales, mitad hacia arriba (`HALF_UP`). El resultado exacto que exceda el máximo se rechaza antes de redondear; también se rechaza una equivalencia redondeada a cero.
4. Unidades estimadas = kg persistibles / peso promedio del calibre, redondeadas al entero más cercano con `HALF_UP`, conservando el significado anterior de la estimación.
5. Empaques = techo de unidades estimadas / conteo por empaque (`CEILING`). El límite de ambos conteos es 2147483647, compatible con INTEGER de PostgreSQL.

Ejemplo independiente: 5250.125000 kg / 0.1750 kg por unidad = 30000.714285… → 30001 unidades. Con 50 unidades por caja: techo(30001/50) = 601 cajas. Son equivalencias estimadas por calibre, no un conteo físico introducido por el usuario.

La web acepta punto decimal sin separadores de miles, lo indica junto al campo y conserva el valor enviado si hay errores. La vista previa llama al servidor; no duplica las fórmulas ni sustituye la cantidad por otra unidad automáticamente.

## Migración e historia

`2026_11_17_100000_preservar_decimales_presentacion_cosecha` cambia `cantidad` y `cantidad_base` de float a NUMERIC(18,6) en PostgreSQL. Verifica rango/precisión de datos previos y detiene la migración ante valores incompatibles; no sustituye silenciosamente conversiones. En SQLite se usa TEXT para estas dos columnas: su afinidad NUMERIC convertiría decimales largos a floats y perdería precisión. Los modelos siguen exponiendo cadenas decimales de escala 6 en ambos motores.

Se agrega únicamente `presentacion_cosecha` JSON nullable. En registros nuevos guarda cantidad, kg, peso unitario, conteo, nombre/etiqueta de presentación y unidad/factor usados, junto con los conteos calculados. El lote, el calibre y la unidad se bloquean durante la transacción; si cambia su catálogo después, la lectura utiliza la instantánea y las cantidades persistidas.

Los registros previos mantienen la instantánea NULL. Si ya tienen kg o conteos, se devuelven esos valores; si no, se muestran como no registrados. No se deduce un factor histórico del catálogo actual ni se reconstruyen conteos ausentes. Las referencias antiguas se conservan. La reversión retiene la precisión y la instantánea para no destruir historia, siguiendo el precedente de la migración decimal de inventario.

Un fallo durante foto/cosecha/estado/historial revierte las escrituras y elimina el archivo creado por ese intento. El registro no usa una transacción manual con retornos anticipados abiertos.

## API para Flutter

Sanctum y permiso `lotes.view`, con control adicional del lote/asignación en el servicio:

- `GET /api/producciones`: mantiene la lista JSON sin envoltorio; solo registros visibles. Filtro opcional `loteid`.
- `GET /api/producciones/{id}`: mantiene el objeto JSON sin envoltorio.
- `POST /api/producciones`: multipart/form-data; devuelve 201 y valores persistidos.
- `GET /api/lotes/{lote}/producciones` y `GET /api/lotes/{lote}/producciones/{id}`: el registro debe pertenecer al lote solicitado.
- `GET /api/lotes/{lote}/presentaciones-cosecha`: opciones activas del producto del lote autorizado.

Campos de registro: `loteid`, `cantidad`, `unidadmedidaid`, `catalogotamanoconteoid`, `fechacosecha` (AAAA-MM-DD), `evidencia_foto` JPG/PNG/WebP hasta 5 MB y `observaciones` opcional. La fecha omitida conserva el valor predeterminado de hoy; la presentación omitida solo se resuelve desde el calibre planificado. La foto sigue siendo obligatoria para ambos canales.

Envíe `cantidad` como **cadena decimal con punto**, por ejemplo `"5250.125000"`, evitando pérdida de precisión en JSON/Dart. Se aceptan también valores numéricos que cumplan el formato, pero una cadena es necesaria para conservar exactamente los valores largos. No se aceptan comas, separadores de miles, signos negativos ni notación científica en cadenas. La respuesta devuelve `cantidad`, `cantidad_base` y `cantidadkg` como cadenas de escala 6; factores de presentación usan la escala del catálogo (4). Los conteos son enteros.

El alias antiguo `cantidadkg` se admite si no se envía `cantidad`: se interpreta exclusivamente en kg. No se confunde con la unidad elegida. El campo nunca había sido persistido correctamente por el controlador anterior. La respuesta incluye `presentacion` con la instantánea legible y `historica_sin_factor` para registros anteriores.

Errores: 401 sin sesión, 403 sin permiso/asignación, 404 para un lote/cosecha fuera del ámbito o una relación anidada incorrecta y 422 con `{message, errors: {campo: [mensaje]}}` para datos/configuración inválidos. Factores, equivalencias, conteos, propietario, destino e imagen URL no son entradas libres; se rechazan si el cliente los envía. Se mantienen las rutas antiguas de edición/eliminación, pero responden 405 para registros visibles: coinciden con la web de solo lectura y no permiten invalidar una cosecha histórica. No se implementan funcionalidades nuevas de edición o borrado.

## Verificación dirigida

`CosechaRegistroTest` cubre registro web/API y consultas cruzadas con valores concretos, unidades y redondeo, límites de almacenamiento, precisión, validación de catálogos y fotografía, campos manipulados, ámbitos/asignación, catálogos autorizados, rutas anidadas, conservación de instantáneas, registros antiguos y reversión de foto/estado/historial. Usa SQLite aislado y almacenamiento falso; no opera sobre las cosechas del usuario.

Ejecución: 21 pruebas aprobadas (241 comprobaciones) entre cosechas, presentación, planificación y métricas de almacén; después se repitieron los dos casos ampliados de catálogo sin escrituras y ámbitos/asignación (31 comprobaciones), también aprobados. Las plantillas Blade compilaron y el formato de los siete archivos nuevos o reescritos pasó Pint. No se ejecutó la suite completa ni PostgreSQL en este entorno.

Revisión con Edge y copia aislada de SQLite: entrada `1,25` rechazada conservando valor/error, vista previa calculada en Laravel, registro web con fotografía y consulta por API de `5250.125000` kg, `30001` unidades y `601` cajas. Formulario y detalle revisados a 390 px sin desbordes; sin errores JavaScript observados. El envío espera las consultas de vista previa pendientes para que estas no consuman la sesión con los errores y valores anteriores antes de la redirección.

La migración también se aplicó en SQLite local, con respaldo `storage/app/private/respaldos-demo/antes-edt41-20261117-212608.sqlite`. Se compararon las 19 cosechas antes/después, incluidos los campos ajenos a cantidades: conservaron sus datos y la instantánea histórica sigue NULL. No se cargaron las cosechas del navegador en esa base real.
