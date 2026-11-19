# EDT 5.4 · Pantallas web de pedidos y entregas

Se reutilizan Tabler, la barra lateral, los colores verdes y los componentes de operaciones de inventario/planta. Las dos bandejas de distribución comparten una vista; el listado unificado de envíos usa una tabla con datos y acciones agrupados. En móvil, sus filas se apilan con etiquetas de columna y botones accesibles, sin exigir desplazamiento horizontal de toda la página.

## Criterios comprobados

- [x] Listas renovadas: bandejas de minorista/mayorista y listado unificado agrícola, distribución y traslados. Métricas discretas, bordes finos, superficies blancas y estados con texto.
- [x] Búsquedas y filtros: solicitud/producto/destino, estado, punto de venta, almacén autorizado y fechas en pedidos; código, transporte, estado y fechas en envíos. Se puede limpiar la búsqueda. Las fechas inválidas o invertidas producen errores de validación. Un límite superior sin fecha inicial es válido. En las rutas sin fecha de salida, el filtro usa su fecha de registro, igual que la presentación existente.
- [x] Acciones y estados: se reutilizan las reglas de EDT 5.3 para ofrecer «Revisar pedido» y las acciones logísticas existentes. Se conserva «Asignar chofer». Las cantidades se muestran con la unidad/presentación histórica y hasta seis decimales, incluyendo todas las líneas, sin sumar presentaciones incompatibles.
- [x] Pedido → envío: los detalles y las bandejas enlazan la consulta web de seguimiento cuando el usuario tiene acceso efectivo.
- [x] Entrega → comprobante: el seguimiento muestra las recepciones confirmadas y enlaces al PDF privado existente. Se verificaron recepción y PDF para agrícola, distribución y traslado. Un código sin confirmar no ofrece comprobante. No se inventa un comprobante para registros antiguos que carecen de recepción QR persistida.
- [x] Pantallas pequeñas y permisos: tablas apiladas, filtros verticales y formularios dentro del estilo compartido. Comprobados 1440 y 390 píxeles; pruebas HTTP de formularios y de decisiones, autenticación, permisos revocados, pedidos ajenos y comprobantes de otro destinatario.

## Consulta de seguimiento

`GET /seguimiento-envios/{tipo}/{envio}` (`envios.seguimiento`) es una vista de solo lectura protegida por sesión y cuenta aprobada. Reutiliza `EnvioMovilConsultaService` y `EnvioRecepcionQrService::autorizarConsulta`, con sus permisos y ámbitos efectivos. No permite escribir estados, firmar, emitir ni consumir QR. En una ruta mixta, el minorista solo consulta sus pedidos y comprobantes. Las acciones y las rutas de decisión, despacho y recepción permanecen en sus servicios anteriores.

El nuevo `EntregaWebPresentacionService` decide si corresponde anunciar un enlace y obtiene exclusivamente recepciones confirmadas que el usuario puede consultar. El endpoint privado del PDF vuelve a autorizar cada solicitud. No se exponen tokens, firmas ni rutas de almacenamiento en los enlaces nuevos.

## Verificación y límites

Pruebas pertinentes sobre base SQLite aislada, PHP 8.2:

Resultado final: **42 pruebas seleccionadas distintas aprobadas** (9 nuevas de pantallas web, 18 de permisos, 14 de decisiones y 1 de acceso). Se ejecutaron por grupos; los fallos iniciales en las expectativas de las pruebas nuevas se corrigieron y sus casos se volvieron a ejecutar satisfactoriamente.

- `PedidosEntregasWebTest`: listas, búsqueda, fechas, precisión, navegación entre pedido y envío, rutas mixtas, PDF de los tres tipos, ausencia de escrituras al consultar, permisos, estados y formularios.
- `SeguridadBaseRbacTest`: regresión de autenticación y permisos de las rutas.
- `PedidosAccessTest`: administrador conserva consulta y no crea envíos.
- `PedidoDecisionTest`: regresión de aceptación/rechazo, stock, motivo e idempotencia entre web y API.

El build de Vite fue generado correctamente. No se actualizaron paquetes. La versión local de Node 22.11 imprime una advertencia de compatibilidad con Vite, pero completó la compilación.

En la revisión móvil del formulario se detectaron títulos de pasos cortados; se ajustó el indicador a dos columnas para mantener las palabras completas. El flujo de pasos y sus validaciones no cambian.

Evidencia local ignorada por Git: `storage/logs/edt54-*.log`, capturas `storage/app/private/edt54-*.png` y mediciones `edt54-responsive.json`. Las capturas se obtuvieron del HTML real de Blade con datos de prueba y el CSS compilado; no se introdujeron datos de demostración en la base operativa. Listas y seguimiento: ancho del documento igual al viewport en 1440 y 390 píxeles.

No se ejecutaron la suite completa, Flutter, PHP 8.3/8.4 ni pruebas sobre PostgreSQL. La revisión visual no equivale a un recorrido de firma en un teléfono físico. No se modificaron las reglas de inventario ni los contratos API, y esta tarea no requiere migración. Los cambios permanecen locales hasta recibir la orden de subirlos.
