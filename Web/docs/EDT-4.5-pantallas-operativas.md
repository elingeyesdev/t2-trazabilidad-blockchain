# EDT 4.5 — Pantallas de inventario, cosechas y planta

La interfaz conserva Tabler, la paleta verde y las superficies neutras del sistema. Los módulos operativos activan `ag-operacion` mediante una sección del layout; el estilo queda limitado a estas pantallas. Se reutiliza el encabezado de listas y se añaden componentes pequeños para encabezados, métricas y cantidades. Se eliminan las métricas antiguas con degradados del listado de cosechas y planta, y se unifican bordes, tipografía, formularios y tablas.

## Criterios comprobados

- [x] **Listas con la plantilla general:** inventario/insumos, existencias y movimientos por almacén, cosechas y procesamiento de planta; estilos compartidos aplicados también a las vistas de almacenes y solicitudes de producción.
- [x] **Formularios y detalles con estructura común:** cabeceras neutras, campos y secciones consistentes, estados vacíos y acciones con el estilo general. En móvil, la edición de inventario presenta los campos antes de la imagen; el modal de nuevo lote mantiene desplazamiento y pie de acciones.
- [x] **Cantidades con unidad o presentación:** saldos físicos, reservados, vencidos, bloqueados, disponibles y mínimos llevan unidad. Las materias usadas y los objetivos conservan decimales. Si falta una unidad se indica expresamente; no se supone que sean kg. El formulario de inventario acepta seis decimales y su vista previa no redondea a dos.
- [x] **Estados y alertas legibles:** se distinguen existencia física y disponible, mínimo sin configurar y existencias bajas; las etapas incluyen textos como Actual, Completada, Próxima y Pendiente. Las cifras calculadas de planta se identifican como estimaciones.
- [x] **Acciones según permisos efectivos:** el administrador consulta sin enlaces a registrar ingresos/salidas ni formularios de mínimo; el operario consulta sus lotes y no crea, edita ni certifica. Los lotes procesados no ofrecen eliminación. Permanecen los controles del servidor y el aislamiento por almacén/lote.
- [x] **Consulta y registro en pantallas pequeñas:** revisión a 390 px y escritorio a 1440 px, sin desbordamiento horizontal de la página. Las tablas anchas desplazan su contenido dentro de su contenedor. Se guardó una edición de inventario y una cosecha con foto desde el navegador móvil en una base aislada.

## Validación ejecutada

**43 pruebas pertinentes distintas aprobadas**, con PHP 8.2 / SQLite en bases aisladas. Se ejecutaron:

- `PantallasOperativasTest`: cantidades concretas, unidades ausentes y cero, consultas sin alterar saldos, filtros, administrador, operario, almacén ajeno y vínculo producto/almacén.
- `CosechaRegistroTest`: registro web/API, presentaciones, precisión, validación, permisos, instantáneas y compensación de errores.
- `ExistenciasAlmacenTest`: partidas, mínimo, vencimientos, movimientos, consumo y permisos.
- `OperarioPlantaProcesamientoTest`, `InventarioAccessTest` y `PermissionMatrixAlineacionTest`.
- `ProductoPlantaCatalogoTest`, y repetición del caso de planta tras ajustar la presentación exacta de objetivos y estados.

La primera ejecución encontró un error en el dato de prueba de aislamiento (faltaba el tipo obligatorio del insumo); se corrigió la preparación y el caso pasó. Las once comprobaciones finales de pantallas/catálogo y la comprobación posterior de planta finalizaron sin fallos. No se ejecutó la suite completa para esta renovación visual.

Vite compiló correctamente (código de salida 0), Blade compiló y Pint pasó en la nueva prueba. La versión local de Node 22.11 emite el aviso de versión recomendado por Vite; no impidió generar los assets. No se cambiaron dependencias. `git diff --check` no detectó errores.

Edge revisó listas y detalles de los tres módulos, edición de inventario, modal de nuevo lote y registro de cosecha. No se observaron excepciones JavaScript. El inventario conservó `95.000456 kg` después de editar el nombre y se registró una cosecha de `12.345678 kg` con foto. También se confirmó la vista del administrador sin enlaces operativos. Las capturas/resultados quedan como evidencia local en storage privado ignorado por Git; los datos de revisión no se introdujeron en la base habitual.

No se modifican contratos de API, cálculos de inventario, cierre de EDT 4.3 ni conservación de certificados de EDT 4.4. El cambio en `ProductoPlantaCatalogo` afecta al texto del objetivo, que ya no redondea a dos decimales. La lista de planta carga la unidad de las materias primas con sus relaciones para mostrarla sin consultas por fila.

La matriz remota PHP 8.3/8.4, PostgreSQL y Flutter no se ejecutaron. No se publicaron cambios en GitHub.
