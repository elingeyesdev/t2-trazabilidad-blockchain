# Capturas y evidencias de Tarea 10

Guarda las imágenes en una carpeta `evidencias` de tu entrega. Los números
corresponden a los pasos de [README.md](README.md). Son **grupos de evidencias**:
si la salida no cabe, usa `02a`, `02b`, sin reducir el texto hasta hacerlo ilegible.
No fabriques salidas ni utilices las pruebas locales del asistente como si fueran
capturas de tu VM.

## Cómo tomar y presentar las capturas

1. En Windows utiliza **Win+Shift+S** y guarda cada imagen como PNG. Para el móvil,
   usa su captura nativa o la función de captura del emulador.
2. En terminal muestra el comando, el resultado y el prompt con usuario/hostname.
   Ejecuta `date -Is` para relacionar pruebas con la hora del informe: solo consulta
   la fecha en Ubuntu y no requiere sudo.
3. En navegador conserva visible la URL. En PuTTY conserva una parte de la ventana
   que permita identificar el cliente. En el móvil conserva la pantalla de la app.
4. Escribe debajo de cada imagen: objetivo, comando o acción, resultado observado
   y requisito que demuestra. Una imagen sin explicación no sustituye el informe.
5. No captures contraseñas, archivos `.env`, claves privadas, tokens Bearer,
   respuestas de login completas ni dumps abiertos. Usa datos de laboratorio.
   Si se filtra un secreto, retira la imagen y cambia o revoca ese secreto.

## Matriz de evidencias

| Archivo o grupo | Momento y lugar | Qué debe verse | Qué acredita |
| --- | --- | --- | --- |
| `01-recursos-vm.png` | Antes de instalar, VirtualBox/VMware | Nombre VM, CPU, RAM, disco y adaptador puente | Recursos propuestos y topología |
| `02-ubuntu-terminal.png` | README 1–2, consola Ubuntu | Login en consola; versión Ubuntu; `hostnamectl`; `ip -br address`; `systemctl get-default`; RAM/disco | Ubuntu Server, sin escritorio, hostname e IP identificables |
| `03-ssh-powershell.png` | README 3, PowerShell conectado por SSH | Comando de conexión a VM_IP; `whoami`, `hostname`, fecha. En una segunda imagen, validación `sshd -t` y ajustes efectivos relevantes de `sshd -T` | Acceso SSH desde cliente y configuración validada |
| `04-usuario-limitado.png` | README 3, sesión de observador | `whoami`, `id`, intento `sudo -l` denegado; después de preparar `.env`, intento de leerlo denegado | Usuario con permisos mínimos |
| `05-putty.png` | README 3, PuTTY | Sesión real de `observador`, hostname de la VM y consulta de API cuando esté publicada | Conectividad mediante PuTTY |
| `06-docker.png` | README 4, Ubuntu | Versiones Docker y Compose; resultado de hello-world | Motor y Compose instalados en Ubuntu |
| `07-configuracion-segura.png` | README 6, Ubuntu | `docker compose config --quiet` completado y `ls -l .env` con permiso `600`; nunca contenido | Configuración válida y archivo privado |
| `08-rol-postgresql.png` | README 7, psql en Ubuntu | `\du agrofusion_app`, sin atributos de superusuario, creación de roles o bases | Aplicación con rol SQL limitado |
| `09-despliegue.png` | README 8, Ubuntu | Construcción finalizada; `compose ps` con ambos servicios; migraciones `Ran` | Web/API y PostgreSQL en contenedores |
| `10-nginx.png` | README 9, Ubuntu | Sitio instalado sin secretos, `nginx -t` correcto, servicio activo y API por puerto 80 | Nginx configurado y publicando |
| `11-api-base-datos.png` | README 10, Ubuntu | `/up` y `/api/test-api` con 200; `/api/me` sin token con 401; SELECT desde Laravel con base/rol/motor PostgreSQL | Respuesta HTTP, protección de API y conexión real a PostgreSQL |
| `12-red-firewall.png` | README 10, Ubuntu y Windows | UFW activo, entrada solo 22 autorizado y 80; loopback 8080; prueba desde Windows: 22/80 accesibles y 5432/8080 inaccesibles | Puertos mínimos y BD sin exposición pública |
| `13-web-cliente-login.png` | README 10, navegador de Windows | Login con URL `http://VM_IP/login` visible | Web accesible desde otro dispositivo |
| `14-web-cliente-sesion.png` | README 10, navegador de Windows | Sesión válida, dashboard o módulo accesible y URL de VM | Sistema web funcional |
| `15-api-autenticada.png` | README 10, PowerShell | Resultado de `/api/me` con ID/correo de prueba/estado; no token ni contraseña | Cliente → Nginx → API → BD con autenticación |
| `16-movil-conexion.png` | README 11, Android/emulador | Pantalla **Comprobar conexión** de AgroFusion con resultado satisfactorio; captura adicional del comando Flutter con VM_IP si hace falta | Aplicación móvil conectada a la VM |
| `17-movil-perfil.png` | README 11, Android/emulador | Login completado y **Mi perfil** de una cuenta de laboratorio | Autenticación y consulta de datos desde móvil |
| `18-backup.png` | README 12, Ubuntu | Archivo dump de tamaño no nulo, huella SHA-256, catálogo legible, conteo original y marcador | Existencia e integridad verificable del respaldo |
| `19-restauracion.png` | README 12, Ubuntu | Restore sin errores, conteo igual al original, marcador y consulta Laravel a `agrofusion_restore` | Restauración probada con datos recuperados |
| `20-incidente-fallo.png` | README 13, Ubuntu | Fecha, db detenido y petición que consulta BD con error | Incidente controlado observado |
| `21-incidente-diagnostico.png` | README 13, Ubuntu | Logs de app relacionados con el fallo de conexión; estados de servicios | Diagnóstico con evidencia |
| `22-incidente-recuperado.png` | README 13, Ubuntu y/o cliente | db activo/healthy, SELECT exitoso y login/perfil funcionando de nuevo | Solución del incidente y recuperación verificada |
| `23-logs-clientes.png` | Tras pruebas web/móvil, Ubuntu | Access log Nginx con rutas `/api/login`, `/api/me`, IP y horas correspondientes | Solicitudes de los clientes llegando al servidor |
| `24-reinicio.png` | README 14, Ubuntu | Política `unless-stopped`, servicios habilitados y, después de reiniciar, contenedores/API/BD disponibles | Persistencia y recuperación tras reinicio |
| `25-prueba-companero.png` | README 14, equipo de otro estudiante | Prueba efectuada por él y su resultado, si puede capturarla; acompaña su registro escrito | Documentación utilizada por otra persona |

Para la segunda parte de `04`, `head -n 1 /srv/agrofusion/docs/tarea10/.env`
ejecutado como `observador` debe mostrar **Permission denied**. Es una consulta
que no requiere privilegios y no cambia archivos. Si llega a mostrar contenido,
interrumpe la captura y corrige propietario/permisos como administrador. Esta
prueba no debe mostrar ningún valor del archivo.

Para `12`, una comprobación local no basta: usa también `Test-NetConnection`
desde Windows. Que un puerto esté bloqueado no identifica por sí solo la causa;
combina la prueba con Compose sin `ports` para BD y la regla de loopback de app.

## Relación con los seis entregables

| Entregable de la consigna | Archivos/evidencias que debes adjuntar o demostrar |
| --- | --- |
| 1. Servidor con proyecto desplegado | VM operativa; URL e IP; recursos; capturas 01–02, 06–12 y 24; configuración; backup, restauración e incidente 18–22 |
| 2. Documentación de cada comando | README con efectos, archivos y privilegios; informe completado; registro de terminal revisado; registro de IA |
| 3. Acceso desde aplicación móvil | APK debug con URL correcta, capturas 16–17 y solicitudes correlacionadas en 23 |
| 4. Web desde otro dispositivo | Capturas 13–14 desde Windows con URL visible y prueba HTTP externa |
| 5. Usuario con mínimo privilegio | Cuenta Linux `observador`, captura 04; rol SQL limitado en 08 como evidencia adicional |
| 6. SSH y PuTTY | Capturas 03 y 05 con sesiones reales, usuarios y hostname |

Los criterios de backup, incidente, reinicios y prueba de otro estudiante siguen
siendo obligatorios aunque la lista final enumere solo seis entregables.
