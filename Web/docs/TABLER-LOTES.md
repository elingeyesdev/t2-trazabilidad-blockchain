# EDT 2.2: base visual de lotes con Tabler

Tabler es la plantilla oficial para las futuras renovaciones web. Por solicitud del usuario, esta entrega ahora comprende el listado, Información del lote, Trazabilidad y Ubicación. Crear, editar, el mapa general, calendario, autenticación y las demás pantallas conservan su diseño actual.

## Instalación y compilación

La aplicación utiliza Laravel 12, PHP 8.2+, Blade, npm y Vite 7. No se introduce Livewire ni Inertia. Se fijan `@tabler/core` **1.7.1**, `@tabler/icons-webfont` **3.35.0**, `leaflet` **1.9.4** y `jquery` **3.7.1**, con `package-lock.json` actualizado. Leaflet conserva los mapas y jQuery permite reutilizar los controles operativos existentes, utilizando exclusivamente los modales de Bootstrap 5 incluidos en Tabler.

Desde `Web`:

```powershell
npm ci
npm run build
php artisan serve --host=127.0.0.1 --port=8001
```

Para desarrollar los recursos se puede usar `npm run dev` en otra terminal. Vite requiere Node 20.19+ o 22.12+; la compilación local terminó con Node 22.11, pero emitió una advertencia por esa versión.

Referencias oficiales consultadas: [instalación](https://docs.tabler.io/ui/getting-started/installation/), [repositorio y uso con módulos](https://github.com/tabler/tabler), [desplegables](https://docs.tabler.io/ui/components/dropdown).

## Archivos y aislamiento

| Archivo | Responsabilidad |
| --- | --- |
| `resources/views/layouts/tabler-lotes.blade.php` | Variante Blade independiente con menú del módulo, lotes activos y cierre de sesión con CSRF. |
| `resources/views/lotes/index.blade.php` | Filtros GET, métricas existentes, tabla, tarjetas, avisos y modal de creación adaptados a Tabler. |
| `resources/views/components/tabler/lote-actions.blade.php` | Consultar, trazabilidad, editar y eliminar según los permisos y reglas de estado existentes. |
| `resources/views/components/tabler/lote-state.blade.php` | Etiquetas y colores de estado basados en `EstadoLoteCatalogo`. |
| `resources/views/components/tabler/catalogo-filter.blade.php` | Selector paginado con búsqueda sobre los endpoints de catálogo existentes; modal compartido entre filtros. |
| `resources/views/components/tabler/pagination.blade.php` | Paginación Tabler en español, sin alterar las traducciones globales. |
| `resources/views/lotes/partials/tabler-empty.blade.php` | Estado vacío y acciones permitidas. |
| `resources/css/tabler-lotes.css` | CSS de Tabler, iconos y ajustes acotados a esta variante. |
| `resources/js/tabler-lotes.js` | Módulos Tabler, cambio de vista, búsqueda de catálogos, aviso de creación y confirmación antes de enviar DELETE. |
| `vite.config.js`, `package.json`, `package-lock.json` | Entradas independientes y dependencias reproducibles. |
| `tests/Feature/LotesAccessTest.php`, `tests/TestCase.php` | Regresión de acciones, filtros, paginación y permisos; las pruebas HTTP no dependen del manifiesto de Vite. |

Este layout no extiende `layouts.app`: no carga Bootstrap 4, Font Awesome, estilos del módulo anterior ni Tailwind. Tabler incluye Bootstrap 5, por lo que no se instala ni carga otra copia de Bootstrap. Los recursos anteriores siguen disponibles para las demás vistas. Los iconos, Leaflet y jQuery se sirven desde el build local, sin CDN. Los mapas solicitan sus teselas al proveedor OpenStreetMap.

## Información, trazabilidad y ubicación

Se conserva la apariencia nativa de Tabler con el verde anterior del proyecto (`#23754b`) como color principal, superficies blancas y texto oscuro. Botones, enlaces, progreso, foco, avisos informativos y marcadores del mapa comparten ese acento; los estados usan etiquetas neutras con texto. Se eliminaron los encabezados con degradados y los colores diferentes para cada etapa. Las pestañas Información del lote, Trazabilidad y Ubicación identifican la sección activa y mantienen el contexto del mismo registro.

`lotes/tabler/header`, `navigation`, `actions` y `alerts` comparten el encabezado y navegación. Información utiliza el componente data grid y un resumen de actividad; Ubicación integra Leaflet, datos del terreno y un estado vacío. Trazabilidad conserva el progreso, las acciones según etapa, certificación/blockchain, el envío a almacén, los filtros de historial y las evidencias.

Los parciales operativos adaptados viven en `resources/views/lotes/tabler/`. Se conservan las versiones anteriores de los parciales compartidos para evitar cambios en otras pantallas. Los campos, validaciones, rutas y métodos HTTP proceden de los formularios originales. Al modificar un flujo operativo en el futuro, revisar también su variante Tabler.

Los scripts de estos parciales se ejecutan como módulos dependientes de `tabler-lotes.js`, que expone las dependencias necesarias antes de inicializarlos. El selector de responsable devuelve el foco al modal de siembra al cerrar su catálogo. Los marcadores de mapas se incluyen en el build y el nombre del lote se muestra como texto en la ventana del mapa.

Se mantienen las rutas y los métodos HTTP, el orden descendente existente, los filtros `q`, `insumosemillaid`, `cultivoid`, `estadolotetipoid`, `usuarioid` y los parámetros en los enlaces de paginación. El componente de acciones mantiene CSRF y DELETE, con confirmación nativa del navegador. Las autorizaciones del servidor no cambian. No se modifican controladores, modelos, tablas, migraciones ni contratos API por EDT 2.2.

## Verificación

```powershell
npm run build
php artisan test --filter='LotesAccessTest|ActividadLotePermisosTest|AgriculturaOwnershipAislamientoTest|ApiConsultaLotesActividadesTest|ApiCampoOwnershipAislamientoTest|CertificacionesAccessTest'
```

El conjunto backend pasó con **32 pruebas y 156 verificaciones**. Incluye aislamiento de usuarios, permisos de creación y edición, acciones de lotes cerrados, conservación de filtros y paginación, método DELETE, CSRF y renderización de las nuevas pantallas y del formulario de asignación de siembra. Las pruebas usan SQLite en memoria.

La revisión de navegador usa Edge sin interfaz visible sobre el servidor local: listado con los 16 lotes disponibles, permisos de administrador, desplegables, cambio tabla/tarjetas, filtros, selector de encargado, paginación y estado vacío. La ampliación revisa Información, Trazabilidad, filtros del historial, apertura de evidencias y Ubicación para dos lotes reales, incluyendo el mapa con teselas OpenStreetMap. Se comprueban escritorio (1440 px), ancho intermedio (800 px) y móvil (390 px), sin errores JavaScript ni desbordamientos en las pantallas de detalle. La tabla del listado tiene desplazamiento horizontal propio en móvil. Las capturas locales quedan en `storage/logs/edt22-*.png` y `storage/logs/tabler-*.png` y no se versionan.

El catálogo de semillas local devuelve una colección vacía; se verifica ese estado, sin inventar registros ni modificar su endpoint. La selección de semillas con datos y la confirmación efectiva de eliminación/creación requieren una cuenta y registros apropiados en un entorno de integración; no se eliminan lotes reales para comprobar el cambio visual. La prueba backend cubre las acciones del jefe agrícola y la renderización de Información, Ubicación sin coordenadas, Trazabilidad y el formulario Tabler para asignar siembra.

## Dependencia EDT 2.1

Existen los recursos y controladores de consulta de lotes y actividades, el contrato `docs/API-LOTES-ACTIVIDADES-FLUTTER.md` y las pruebas de consulta y aislamiento, que pasan en el conjunto anterior. No hay un bloqueo backend para EDT 2.2 y no se altera esa API. No se certifica el funcionamiento de Flutter de extremo a extremo.

## Criterios de aceptación

1. **Compatibilidad:** Tabler compila con Vite y convive mediante un layout independiente con las vistas anteriores.
2. **Listado con Tabler:** menú activo, filtros, datos reales, estados, acciones, avisos y paginación adaptados.
3. **Acciones conservadas:** enlaces, formularios, permisos y reglas de estado preservados, con regresión backend y comprobaciones de navegador. Las operaciones de escritura sobre datos reales quedan fuera de la comprobación visual.
