# Diseño compartido de AgroFusion

La referencia visual del usuario se aplica desde una sola entrada de estilos: `resources/css/agrofusion-ui.css`. Usa Tabler 1.7.1 y los iconos ya instalados; no agrega dependencias. El verde principal sigue siendo `#23754b`, con verde oscuro `#195c39`, superficies blancas, fondo `#f5f7fb` y barra lateral `#182433`.

## Alcance

- Los layouts `app` y `tabler-lotes` comparten menú lateral, barra superior y comportamiento de navegación. Los enlaces y condiciones de permisos provienen del menú existente. `InterfazContexto` reúne los datos de usuario que antes estaban dentro del layout, sin cambiar las reglas de acceso.
- El layout de Lotes conserva su runtime Tabler/Bootstrap 5 y sus scripts de catálogos y mapas. Las vistas antiguas conservan su runtime Bootstrap 4. Se comparte la apariencia sin ejecutar simultáneamente ambos runtimes en una misma página.
- Autenticación y trazabilidad pública adoptan la misma tipografía, paleta, bordes y superficies. Los formularios de acceso y registro conservan sus campos y acciones.
- Métricas de los paneles por rol, tarjetas `small-box`, tarjetas de inventario y resúmenes de lotes usan etiquetas pequeñas, valores destacados, iconos discretos y bordes finos. No se inventaron porcentajes, series ni tendencias.
- Botones, tablas, formularios, selectores, paneles y modales reciben el tratamiento común. Los gráficos mantienen sus datos y colores semánticos, con tipografía y puntos más discretos.
- El menú conserva el modo reducido en escritorio y el panel desplegable en móvil. Se mejoró contraste, foco, atributos de expansión y cierre con Escape.

`agrofusion-shell.css` conserva la estructura y compatibilidad del layout anterior que estaba embebida en Blade; `agrofusion-ui.css` define el diseño común por encima de esa base. Los estilos operativos de mapas, calendario y trazabilidad permanecen en sus módulos. Tabler e iconos se importan solo desde la entrada común para evitar duplicarlos en el bundle de Lotes.

## Verificación

- `npm.cmd run build`: compilación correcta. El entorno emite el aviso ya existente de Node 22.11 frente al requisito de Vite 22.12; no se actualizaron dependencias.
- `php artisan view:cache`, seguido de `view:clear`: plantillas compiladas correctamente.
- Pruebas dirigidas `LotesAccessTest|CalendarioActividadesTest`: 9 aprobadas, 91 comprobaciones.
- Revisión con Edge en un perfil aislado: inicio, lotes, calendario y detalle en escritorio, más lotes a 390 px; sin desbordamiento horizontal ni excepciones JavaScript en esas páginas.

Las capturas locales se guardan en `storage/app/private/ui-preview/` y no forman parte del código versionado. La revisión visual cubre pantallas representativas; los demás módulos reciben el tema desde sus layouts compartidos.

## Unificación de componentes por módulo

`resources/css/agrofusion-modules.css`, importado por la entrada común, cubre las tarjetas y cabeceras propias que antes conservaban el diseño anterior. Incluye gestión de usuarios, inventarios y almacenes, lotes y actividades, producción y maquinaria, certificaciones, pedidos, puntos de venta, flota, rutas y documentos. Las notificaciones flotantes de los distintos roles comparten el acabado sobrio de tareas pendientes.

Se usan selectores explícitos de componentes para evitar modificar imágenes, marcadores de mapas o controles operativos por coincidencias en sus nombres. Los estados seleccionados siguen resaltados; las barras de ocupación mantienen verde, ámbar y rojo según su estado. Los iconos de acciones permanecen visibles y se retiran los decorativos de los títulos. No se cambian rutas, permisos ni operaciones de negocio.

La revisión visual utiliza perfiles locales de Edge y las cuentas existentes de administrador, jefe agricultor y planta. Se comprobaron pantallas representativas de cada grupo, más usuarios, inventario y puntos de venta a 390 px. La búsqueda de usuarios y la apertura y cierre de avisos se comprueban sin guardar registros ni descartar notificaciones reales. La compilación CSS y la compilación de Blade son las verificaciones de código para esta ampliación visual; no se ejecuta la suite completa.
