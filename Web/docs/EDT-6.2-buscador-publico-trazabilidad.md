# EDT 6.2 — Buscador público de trazabilidad

## Implementación

- `GET /trazabilidad`: formulario público GET, sin JavaScript, con etiqueta, ayuda y errores asociados al campo. `?codigo=...` reutiliza la normalización del EDT 6.1 y redirige al detalle por una ruta de Laravel.
- `GET /trazabilidad/{codigo}`: consulta pública; 404 propio para códigos inexistentes, 422 para formatos inválidos y 409 para coincidencias ambiguas. Conserva el valor consultado y permite corregirlo. Un fallo interno conserva su estado de error; no se convierte en código inexistente.
- Login conserva su formulario y añade «Consultar trazabilidad».
- Web y API utilizan `ConsultaTrazabilidadPublicaService`, que entrega exclusivamente la proyección de `TrazabilidadPublicaResource`. No se pasan modelos privados a Blade ni se consulta la propia API por HTTP. Se conserva el contrato JSON del EDT 6.1.
- Se mantiene el límite compartido de 60 consultas/minuto por conexión del EDT 6.1. API responde JSON; web devuelve una página legible con HTTP 429 y Retry-After. No se confía en encabezados de proxy arbitrarios.
- El detalle mantiene las cinco etapas, múltiples orígenes, cantidades con unidades o presentación y vínculos registrados. No infiere etapas completadas ni conexiones por el orden visual. Las fechas se muestran con la precisión y zona horaria provistas por la API.
- La certificación muestra todas las emisiones relacionadas; no designa una emisión vigente cuando el modelo no puede determinarlo. Blockchain distingue estado local, confirmación registrada y verificación en vivo. Un hash sin transacción no se presenta como confirmación. No hay llamadas RPC, emisión ni escrituras al consultar.
- Las imágenes solo provienen del mecanismo de aprobación del EDT 6.1 y su endpoint controlado. El retiro elimina su aparición y acceso público. No se publican archivos automáticamente ni se generan accesos a documentos privados.
- Layout público con Tabler, identidad verde, fondo claro y tarjetas sobrias; sin barra administrativa ni dependencias nuevas. Formulario adaptable y campos con salto de códigos/hashes largos, foco visible y lectura sin JavaScript. No se cambiaron tablas ni permisos.

## Verificación realizada

- PHP 8.2.4: `php vendor/phpunit/phpunit/phpunit tests/Feature/TrazabilidadPublicaWebTest.php tests/Feature/TrazabilidadPublicaApiTest.php --colors=never`: **25 pruebas, 735 aserciones, aprobadas**. Incluye 12 casos web y la regresión completa de la API pública.
- Se verificaron búsqueda agrícola y PDV, normalización, errores y corrección, datos privados y contenido escapado, múltiples orígenes y cantidades, historial y blockchain pendiente/confirmado, evidencias privadas/aprobadas/retiradas, límite de solicitudes, autenticación privada, errores internos y consultas sin escritura.
- `npm.cmd run build`: compilación Vite aprobada. El entorno tiene Node 22.11.0; Vite informa que requiere 20.19+ o 22.12+, aunque la compilación finalizó con código 0. No se modificó Node ni las dependencias.
- Pint sobre los archivos PHP implementados y `git diff --check`: aprobados.
- Petición HTTP anónima al buscador en el servidor local: HTTP 200.

## Comprobaciones pendientes

No se realizó revisión visual en 375–390 px, tablet o escritorio ni navegación de teclado en navegador. El navegador integrado no estaba disponible y la revisión automática rechazó leer una ventana existente de Edge con páginas ajenas a la tarea. Los tests Feature no sustituyen esa revisión visual. Las reglas responsive y de foco están implementadas, pero ese criterio debe verificarse en navegador antes de marcarlo como comprobado.

No se ejecutó la suite completa, PHP 8.3/8.4 ni Flutter; esta tarea no modifica código móvil. No se consultó blockchain en vivo. No se publicaron cambios en GitHub.