# EDT 2.3: búsqueda y filtros del listado de lotes

La ruta `GET /lotes` mantiene Blade, Tabler verde y el detalle `GET /lotes/{lote}`. No se modifican la API de Flutter, los modelos, las migraciones, las dependencias ni los permisos.

## Parámetros GET

| Parámetro | Significado |
| --- | --- |
| `q` | Nombre completo o parcial del lote. Se recorta el texto, hasta 100 caracteres. Vacío o solo espacios equivale a no buscar. No consulta ubicación ni código de trazabilidad. |
| `cultivoid` | ID del cultivo relacionado mediante `lote.cultivoid`; no equivale al insumo de semilla. |
| `estadolotetipoid` | ID del estado real del lote. La etiqueta usa `EstadoLoteCatalogo`. |
| `insumosemillaid`, `usuarioid` | Filtros adicionales existentes, ahora con opciones limitadas al conjunto autorizado. |
| `page` | Página positiva; 15 registros por página, orden descendente por `loteid`. |
| `filtros_abiertos` | Conserva el panel de filtros abierto; booleano opcional. |

Los criterios se combinan con AND sobre la consulta completa autorizada, antes de paginar. Las opciones de los selectores se obtienen del conjunto autorizado sin aplicar los filtros activos; por eso se mantienen disponibles al combinar criterios sin coincidencias. Los valores deben ser enteros y pertenecer a esas opciones. Los parámetros inválidos usan la validación habitual de Laravel: redirección con errores en navegación web y `422` para solicitudes JSON.

La búsqueda usa parámetros vinculados y `LIKE ... ESCAPE '!'`: `%`, `_` y `!` se buscan literalmente. Reutiliza `BusquedaTexto` para normalizar mayúsculas y acentos españoles, incluida la equivalencia `ñ`/`n`. La normalización no es una transliteración Unicode completa; otros alfabetos o diacríticos dependen de `LOWER` y la configuración de SQLite/PostgreSQL. No requiere extensiones nuevas de base de datos.

El formulario GET no envía `page`: al cambiar los criterios vuelve a la primera página. Los enlaces del paginador conservan los parámetros actuales. «Limpiar filtros» conserva únicamente `filtros_abiertos=1`, restableciendo también la página. Se distinguen los mensajes de listado autorizado vacío y filtros sin coincidencias.

## Autorización y detalle

Se conserva `LoteAcceso::aplicarScopeVisibles` para el listado. Los catálogos de filtros derivan de esa misma consulta y no muestran usuarios, cultivos o estados exclusivos de otros equipos. La acción «Ver detalle» reutiliza `lotes.show`, que mantiene `autorizarLoteVisible`. Un identificador inexistente responde `404`; uno fuera del alcance mantiene la denegación existente (JSON `403`, navegación web con aviso y redirección).

## Verificación

`tests/Feature/LotesListadoFiltrosTest.php` utiliza SQLite en memoria, dos equipos, distintos cultivos y estados, y comprueba los IDs incluidos/excluidos. Cubre búsqueda completa/parcial, espacios, caracteres especiales, normalización española, criterios individuales/combinados, catálogos autorizados, parámetros inválidos, estado vacío, enlaces de detalle y paginación. El formulario sin `page` y el enlace de limpieza se comprueban junto con las páginas resultantes.

```powershell
php artisan test --filter='LotesListadoFiltrosTest|LotesAccessTest|ApiConsultaLotesActividadesTest|ApiCampoOwnershipAislamientoTest|AgriculturaOwnershipAislamientoTest'
```

EDT 2.1 cuenta con recursos, contrato API y pruebas; EDT 2.2 cuenta con el layout y los componentes Tabler. Ambas dependencias están disponibles. Los cambios de EDT 2.3 no requieren recompilar JavaScript/CSS porque solo afectan a consultas, vistas Blade y pruebas.

El conjunto relacionado terminó con **31 pruebas aprobadas y 235 verificaciones**. La revisión en Edge comprobó seleccionar cultivo y estado, buscar un nombre con espacios, combinar los criterios, abrir el detalle, limpiar filtros, navegar a la segunda página y volver a la primera al buscar. Se revisaron las capturas en escritorio y móvil (390 px), sin desbordamiento de la página ni errores JavaScript. Las evidencias locales quedan en `storage/logs/edt23-*.png`.
