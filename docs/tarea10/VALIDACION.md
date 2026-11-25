# Validación de la guía y sus archivos

Fecha de preparación: **11 de noviembre de 2026**.

Estas pruebas se ejecutaron en Docker Desktop con contenedores Linux desde el
equipo Windows. **No se ejecutaron en la VM de Ubuntu del estudiante.** El proyecto
de pruebas se aisló con el nombre `agrofusion-t10-validacion`, un puerto local
18080 y volúmenes nuevos. No se utilizó el `.env` privado de la aplicación local.

## Comprobaciones realizadas

| Prueba local | Resultado observado |
| --- | --- |
| Sintaxis e interpolación de Compose | `config --quiet` pasó usando credenciales sintéticas de prueba |
| Construcción Dockerfile | Imagen construida; Composer y Vite completaron sus pasos |
| Contenido de imagen | Sin `.env` ni `database/database.sqlite`; manifest de assets presente |
| Configuración Apache | `apache2ctl -t`: Syntax OK |
| Sintaxis Nginx | `nginx -t` pasó con este archivo en un contenedor Nginx; no acredita el servicio systemd de Ubuntu |
| Migraciones sobre PostgreSQL vacío | Completadas sin errores, como rol `agrofusion_app` |
| Seeders seleccionados sobre otra BD limpia | RoleSeeder, ConsolidacionRolesPermisosSeeder, RolePermissionSeeder, CatalogosOperacionAgricolaSeeder y AdminUserSeeder terminaron con código 0; seis usuarios iniciales |
| GET /login | HTTP 200; no se comprobó una sesión completa del navegador |
| GET /up | HTTP 200 |
| GET /api/test-api | `{"ok":true}` |
| GET /api/me sin token | HTTP 401 |
| Login API, perfil y logout | Usuario 1 activo/aprobado y perfil devuelto; token omitido de las salidas |
| Consulta PostgreSQL desde Laravel | Base agrofusion, rol agrofusion_app, PostgreSQL 16.15 |
| Tinker como www-data | Funcionó después de configurar su directorio escribible; consulta SELECT correcta |
| Cambio de contraseña por prompt oculto | Función de README ejecutada por Tinker; contraseña enmascarada y retorno null |
| Dump y restauración | Dump custom restaurado en agrofusion_restore sin errores; seis usuarios y marcador BACKUP_T10_VERIFICADO recuperados |
| Acceso Laravel a la BD restaurada | SELECT devolvió el nombre agrofusion_restore y el marcador |
| Detención/inicio de la BD de pruebas | Ambos comandos completados; consulta posterior correcta |
| Diagnóstico de conexión fallida, solo CLI | Un proceso Laravel con DB_HOST=127.0.0.1 devolvió SQLSTATE[08006], Connection refused; el proceso con configuración normal consultó correctamente la BD |
| Estado final previo a limpiar pruebas | App y DB healthy; ambas con restart=unless-stopped |

El dump de validación local se creó dentro del contenedor PostgreSQL para evitar
tratamiento de datos binarios por el shell de Windows. La guía del estudiante
ejecuta redirecciones de dump en **Bash de Ubuntu**, donde se conservan los bytes.

## Problemas encontrados y correcciones

1. **Compose anterior y Dockerfile anterior no comparten protocolo de ejecución.**
   Se preparó una ruta separada para esta tarea, sin sustituir los archivos del
   despliegue existente: Apache/PHP dentro de app y Nginx en el host.
2. **El seeder general falla con PostgreSQL inicializado por las migraciones.**
   `DatosPruebaSeeder` intentó insertar `Sembrado`, ya existente, y recibió
   SQLSTATE[23505]. La guía usa solo los cinco seeders específicos comprobados.
   No se modificó ese seeder ni se atribuye a la guía una carga de todos los datos
   de demostración del proyecto.
3. **PsySH/Tinker intentaba escribir en /var/www/.config/psysh sin permiso.**
   La imagen define XDG_CONFIG_HOME bajo storage/framework. Se reconstruyó y
   volvió a comprobar Tinker como www-data.
4. **La revisión automática rechazó una petición HTTP de simulación del incidente.**
   La herramienta solo indicó «blocked by policy», sin un motivo adicional.
   Se usó una consulta CLI de lectura con un host incorrecto para comprobar el
   diagnóstico y otra con configuración normal para comprobar la conexión.
   No se afirma haber verificado localmente el estado HTTP durante la caída de BD.
5. **Acceso posterior por NAT con un puerto externo distinto de 80.**
   Se cambió el encabezado Host del proxy a `$http_host` para conservar el puerto
   enviado por el navegador. Esto es necesario para enlaces y redirecciones al
   acceder por `http://127.0.0.1:8088`. La configuración Nginx actualizada pasó
   `nginx -t`; la prueba completa por NAT corresponde al servidor del estudiante.

## Pendiente de ejecutar y acreditar por el estudiante

- Instalación y administración real de Ubuntu Server sin escritorio.
- Red del hipervisor, IP y conectividad desde Windows y el teléfono.
- SSH, huellas, usuario observador y PuTTY.
- Configuración efectiva UFW y pruebas TCP externas de 22/80/5432/8080.
- Nginx instalado como servicio del host y publicación por el puerto 80.
- Login y navegación web desde otro dispositivo.
- Compilación, instalación y conexión de Flutter Android a esa VM.
- Backup, copia fuera de VM y restauración realizados en su servidor.
- Incidente HTTP de detener PostgreSQL, logs y recuperación con sus propias horas.
- Persistencia tras reiniciar Ubuntu y prueba de ejecución por otro estudiante.
- Capturas e informe con resultados reales.

La configuración permite HTTP para el laboratorio Android debug en LAN y deja
blockchain desactivado. No es una certificación de seguridad para Internet ni
una prueba de las integraciones externas de la aplicación.
