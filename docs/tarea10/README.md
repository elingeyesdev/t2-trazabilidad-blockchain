# Tarea 10: despliega AgroFusion en Ubuntu Server

Esta guía es para el estudiante que administra una VM desde terminal. Al
terminarla, podrás abrir la web desde Windows, conectar la app Flutter,
administrar el servidor por SSH y PuTTY, restaurar un backup y entregar
evidencias verificables. Lee cada explicación antes de ejecutar su bloque.

**Estado:** los archivos son una propuesta de despliegue para una VM nueva.
Consulta [VALIDACION.md](VALIDACION.md) para distinguir las pruebas locales de
las comprobaciones que tú debes realizar en Ubuntu. Una configuración y una
captura de Docker Desktop no demuestran por sí solas el despliegue en Ubuntu.

## 0. Entiende qué vas a instalar

El repositorio contiene Laravel 12 en `Web/` y Flutter en `Mobile/`. La misma
aplicación Laravel sirve la web y la API. Usaremos este recorrido:

```text
Windows / teléfono Android, en la misma red
                   |
              VM_IP:80
                   |
         Nginx del sistema Ubuntu
                   |
          127.0.0.1:8080, en la VM
                   |
   contenedor app: Apache + PHP + Laravel
                   |
        red Docker backend, interna
                   |
          contenedor PostgreSQL:5432
```

Apache ejecuta PHP dentro de la imagen oficial de PHP. Nginx es el servicio
publicador de Ubuntu. Así evitamos usar `php artisan serve` para publicar.
Los únicos puertos de entrada necesarios son **22/TCP y 80/TCP**. PostgreSQL
no publica puertos y el 8080 está vinculado solo al loopback de la VM.

| Recurso propuesto | Justificación para este laboratorio |
| --- | --- |
| Ubuntu Server 24.04 LTS, 64 bits | Sistema sin escritorio y compatible con Docker Engine |
| 2 vCPU | Ejecutar PHP, PostgreSQL y la construcción de dependencias |
| 4 GB RAM | Margen para construir la imagen y ejecutar ambos contenedores; 6 GB si tu PC lo permite |
| Disco virtual dinámico de 40 GB | Ubuntu, imágenes, volúmenes, logs y backups |
| Adaptador puente | Windows y el teléfono pueden alcanzar directamente la VM |
| Internet durante instalación | Descargar paquetes, imágenes y dependencias; algunas funciones externas también lo necesitan |
| Volúmenes `pg-data` y `app-storage` | Conservar base de datos, archivos subidos y sesiones al recrear contenedores |

Estos son recursos propuestos, no mediciones de carga. Registra el consumo real
con `free -h`, `df -h` y `sudo docker stats --no-stream` cuando funcione.

**No uses el Compose anterior para esta guía:** depende de redes externas y
su Nginx espera PHP-FPM en el puerto 9000, mientras el Dockerfile existente
arranca un servidor HTTP. Estos archivos separados evitan esa combinación.
Tampoco uses el `.env` local de `Web/`: su ejemplo usa SQLite.

### Valores que debes reemplazar

| Ejemplo en la guía | Sustituye por |
| --- | --- |
| `192.168.1.50` | IPv4 real de Ubuntu, en adelante VM_IP |
| `192.168.1.20` | IPv4 real de Windows, en adelante IP_WINDOWS |
| `infraadmin` | Usuario administrador creado al instalar Ubuntu; puedes usar este nombre |
| `observador` | Usuario Linux de consulta sin sudo ni acceso a Docker |
| `/srv/agrofusion` | Directorio que crearemos para el proyecto |

No escribas las palabras VM_IP o IP_WINDOWS literalmente en los comandos.
Los ejemplos de direcciones no son una configuración válida para cualquier red.
En Ubuntu, `nano` guarda con **Ctrl+O**, **Enter**, y sale con **Ctrl+X**.

## 1. Crea e instala la máquina virtual

1. Descarga la ISO de Ubuntu Server 24.04 LTS desde el sitio de Ubuntu.
2. En VirtualBox crea una VM Linux/Ubuntu de 64 bits con los recursos indicados.
   En VMware, utiliza los recursos equivalentes.
3. En **Red**, selecciona **Adaptador puente** y tu tarjeta que tiene conexión.
   Usa una red de confianza. El teléfono debe estar en la misma red y sin
   aislamiento entre clientes. No configures reenvío de puertos en el router.
4. Monta la ISO e inicia la VM. Instala **Ubuntu Server**, sin escritorio.
5. Conserva DHCP inicialmente. No adivines una dirección estática.
6. Para el almacenamiento, selecciona **solo el disco virtual nuevo** de la VM.
7. Define hostname `agro-server`, usuario `infraadmin` y una contraseña propia.
8. Marca **Install OpenSSH server**. No instales un entorno gráfico ni snaps
   opcionales que no necesites.
9. Reinicia, desmonta la ISO si lo solicita e inicia sesión en la consola.

Saca las capturas **01 y 02** de [CAPTURAS.md](CAPTURAS.md).
La instalación del hipervisor ocurre en Windows; la administración del servidor
se realiza desde su consola o por SSH.

## 2. Identifica y prepara Ubuntu

Ejecuta este bloque **en Ubuntu**. Los comandos de consulta no cambian archivos.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `cat /etc/os-release` | Identifica la versión del sistema; solo lectura | Usuario |
| `hostnamectl` | Muestra hostname y sistema; solo lectura | Usuario |
| `hostname -I` | Muestra direcciones asignadas; solo lectura | Usuario |
| `ip -br address` / `ip route` | Muestra interfaces, prefijos y puerta de enlace; solo lectura | Usuario |
| `systemctl get-default` | Comprueba el objetivo de arranque; espera `multi-user.target` | Usuario |
| `free -h` / `df -h` | Muestra RAM y discos; solo lectura | Usuario |
| `sudo apt update` | Actualiza índices de paquetes en `/var/lib/apt/lists` | sudo |
| `sudo apt upgrade` | Actualiza paquetes instalados y sus archivos; revisa la propuesta | sudo |
| `sudo apt install ...` | Instala los programas indicados, servicios y configuración en `/etc` | sudo |

```bash
cat /etc/os-release
hostnamectl
hostname -I
ip -br address
ip route
systemctl get-default
free -h
df -h
sudo apt update
sudo apt upgrade
sudo apt install openssh-server ufw nginx curl ca-certificates git nano openssl
```

Si el hostname no es el elegido, `sudo hostnamectl set-hostname agro-server`
actualiza `/etc/hostname` y el nombre en ejecución. Después abre
`sudo nano /etc/hosts` y cambia el nombre anterior en la línea `127.0.1.1`
por `agro-server`. Ambos requieren sudo y modifican esos archivos.

Si el sistema solicita reiniciar tras actualizar, `sudo reboot` reinicia toda
la VM y corta temporalmente las conexiones. Hazlo antes de seguir.

DHCP es suficiente para tener una IP identificable. Para conservarla, solicita
una reserva DHCP para la MAC de la VM en el router. Si no controlas el router,
registra la IP y verifica que siga igual antes de la demostración; si cambia,
actualiza las URL de Laravel y Flutter. No publiques una IP fija sin conocer
la subred, puerta de enlace y direcciones disponibles.

## 3. Crea el usuario limitado y protege SSH y el firewall

**En Ubuntu**, conserva abierta la consola de la VM durante estos cambios.
Identifica IP_WINDOWS con `ipconfig` en PowerShell: solo consulta los adaptadores.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo adduser observador` | Crea cuenta, grupo y home; modifica `/etc/passwd`, `/etc/shadow`, `/etc/group` y `/home/observador` | sudo |
| `id observador` | Muestra sus grupos; no debe pertenecer a `sudo` ni `docker` | Usuario |
| `sudo nano /etc/ssh/sshd_config.d/00-agrofusion.conf` | Crea configuración modular de SSH | sudo |
| `sudo sshd -t` | Valida la configuración; sin salida significa sintaxis correcta | sudo; solo lectura |
| `sudo sshd -T` | Muestra la configuración efectiva, sin claves privadas | sudo; solo lectura |
| `sudo systemctl enable --now ssh` | Inicia SSH y habilita su arranque mediante enlaces de systemd | sudo |
| `sudo systemctl reload ssh` | Aplica cambios sin detener el servidor | sudo |
| `sudo ufw default ...` | Define políticas y las guarda en `/etc/ufw` | sudo |
| `sudo ufw allow ...` | Añade una excepción de entrada en `/etc/ufw` | sudo |
| `sudo ufw enable` | Activa el firewall con las reglas preparadas | sudo |
| `sudo ufw status verbose` | Comprueba estado y reglas efectivas; no las modifica | sudo |

```bash
sudo adduser observador
id observador
sudo nano /etc/ssh/sshd_config.d/00-agrofusion.conf
```

Escribe este contenido. Mantener contraseña permite probar PuTTY sin convertir
claves; utiliza contraseñas propias y una regla SSH limitada al cliente.

```text
PermitRootLogin no
PermitEmptyPasswords no
PubkeyAuthentication yes
PasswordAuthentication yes
MaxAuthTries 3
X11Forwarding no
AllowUsers infraadmin observador
```

Valida **antes** de recargar. Si `sshd -t` informa un error, corrígelo y no
ejecutes la recarga hasta que pase.

```bash
sudo sshd -t
sudo sshd -T
sudo systemctl enable --now ssh
sudo systemctl reload ssh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.20 to any port 22 proto tcp
sudo ufw allow 80/tcp
sudo ufw enable
sudo ufw status verbose
```

La excepción SSH debe existir **antes** de activar UFW. Si otro compañero
administrará desde una IP diferente, añade una regla equivalente para esa IP.
El 443 solo se abre si configuras HTTPS. No abras 5432, 8080, 9000 ni todos
los puertos. No agregues a `observador` a sudo, adm ni docker.

### Conecta desde PowerShell y PuTTY

`ssh` abre una sesión cifrada en Ubuntu, sin modificar la aplicación. El primer
acceso guarda la clave pública del servidor en `known_hosts` del cliente.
Antes de aceptarla, compara la huella con la consola de la VM. Allí,
`sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` solo muestra una huella
pública; no muestres archivos de claves privadas.

En **PowerShell de Windows** ejecuta:

```powershell
ssh infraadmin@192.168.1.50
```

En la sesión de Ubuntu, `whoami`, `hostname` y `date -Is` solo muestran usuario,
servidor y fecha. Úsalos en las capturas.

1. Descarga PuTTY desde [su página oficial](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html).
2. En **Host Name**, escribe la IP de Ubuntu; **Port: 22**; **SSH**.
3. Abre la conexión, compara la huella e ingresa como `observador`.
4. Ejecuta `whoami`, `id`, `hostname` y `curl http://VM_IP/api/test-api` cuando
   el servicio esté publicado. Sustituye VM_IP.
5. Ejecuta `sudo -l`, introduce su contraseña y verifica que no pueda ejecutar
   comandos sudo. `sudo -l` solo consulta autorizaciones; puede dejar registro
   del intento en los logs del sistema.

Capturas **03, 04 y 05**: SSH desde PowerShell, usuario limitado y PuTTY.

Si pierdes acceso, usa la consola de la VM para revisar IP, regla UFW y
`sshd -t`. Corrige la regla específica; conserva el firewall activo.

## 4. Instala Docker Engine y Compose

Este procedimiento usa el repositorio oficial en una **VM nueva**. Comprueba
que `cat /etc/os-release` indique Ubuntu 24.04 y codename `noble`.
`dpkg --print-architecture` solo consulta la arquitectura: normalmente `amd64`.
Si tu VM es ARM, usa su resultado en el archivo de repositorio.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo install -m 0755 -d /etc/apt/keyrings` | Crea el directorio de llaves de repositorios | sudo |
| `sudo curl -fsSL ... -o ...` | Descarga la llave pública de firma de Docker, sin ejecutar scripts | sudo para guardar en `/etc` |
| `sudo chmod a+r ...` | Permite que APT lea esa llave pública | sudo |
| `sudo nano /etc/apt/sources.list.d/docker.sources` | Registra origen, versión, arquitectura y llave del repositorio | sudo |
| `sudo apt install docker-ce ...` | Instala motor, cliente, containerd y plugins; crea datos en `/var/lib/docker` | sudo |
| `sudo systemctl enable --now docker` | Habilita e inicia Docker | sudo |
| `sudo docker version` / `sudo docker compose version` | Consulta versiones | sudo para acceder al daemon |
| `sudo docker run --rm hello-world` | Descarga y ejecuta una prueba; elimina su contenedor al salir, conserva la imagen | sudo |

```bash
dpkg --print-architecture
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo nano /etc/apt/sources.list.d/docker.sources
```

Contenido para Ubuntu 24.04 en x86-64:

```text
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
```

Después ejecuta:

```bash
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker version
sudo docker compose version
sudo docker run --rm hello-world
```

Usamos `sudo docker` de forma explícita: administrar Docker da control elevado
del host. No otorgues ese acceso al usuario de consulta.
Referencia: [instalación oficial de Docker en Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
Captura **06**.

## 5. Copia esta versión del proyecto desde Windows

Usa esta ruta porque los archivos de esta guía pueden no estar todavía en el
remoto de Git. No necesitas instalar PHP, Composer, Node ni PostgreSQL en Ubuntu:
la imagen construye sus dependencias.

En **PowerShell**, desde la raíz del proyecto:

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `Set-Location ...` | Cambia el directorio de la sesión | Usuario de Windows |
| `git rev-parse HEAD` / `git status --short` | Consulta versión y cambios; anótalos en el informe | Usuario |
| `tar -czf ...` | Crea un archivo en TEMP, excluyendo secretos y dependencias locales | Usuario |
| `scp ...` | Copia el paquete y un ejemplo sin secretos al home del administrador de Ubuntu | Usuario; autentica SSH |

```powershell
Set-Location 'C:\Univalle\ProyectoDeSistemasIII\t2-Trazabilidad-Agricola'
git rev-parse HEAD
git status --short
tar -czf "$env:TEMP\agrofusion-t10.tgz" --exclude=.git --exclude=node_modules --exclude=vendor --exclude=.env --exclude='.env.*' --exclude=.dart_tool --exclude=build --exclude=.gradle --exclude=storage --exclude=backups --exclude=evidencias --exclude='*.sqlite*' --exclude='*.backup' --exclude='*.dump' Web docs/tarea10
scp "$env:TEMP\agrofusion-t10.tgz" infraadmin@192.168.1.50:/home/infraadmin/
scp docs/tarea10/.env.example infraadmin@192.168.1.50:/home/infraadmin/entorno-t10.example
```

La plantilla se transfiere aparte porque el filtro `.env.*` también la excluye.
Revisa la lista del paquete con `tar -tzf "$env:TEMP\agrofusion-t10.tgz"` si
quieres comprobar su contenido; ese comando solo lo lista.

En **Ubuntu**:

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo mkdir -p /srv/agrofusion` | Crea el directorio del despliegue | sudo |
| `sudo chown infraadmin:infraadmin /srv/agrofusion` | Entrega solo ese directorio al administrador | sudo |
| `tar -xzf ... -C ...` | Extrae el código y la guía en el directorio elegido | Usuario |
| `cd ...` / `ls -la` | Cambia de directorio / lista nombres y permisos | Usuario |

```bash
sudo mkdir -p /srv/agrofusion
sudo chown infraadmin:infraadmin /srv/agrofusion
tar -xzf ~/agrofusion-t10.tgz -C /srv/agrofusion
cd /srv/agrofusion/docs/tarea10
ls -la
```

**Desde aquí todos los comandos `docker compose` se ejecutan en ese directorio.**
Así Compose elige `compose.yaml` y `.env` correctos.

## 6. Configura los secretos en privado

No grabes la terminal ni tomes capturas de este paso o de contraseñas.
No compartas `.env`, tokens ni claves privadas con la IA o dentro del ZIP.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `umask 077` | Restringe los permisos de archivos que cree esta sesión | Usuario; estado del shell |
| `cp ... .env` | Crea la configuración privada del despliegue | Usuario |
| `chmod 600 .env` | Solo su propietario puede leer y escribir ese archivo | Propietario |
| `openssl rand -base64 32` | Genera 32 bytes aleatorios y los muestra en base64; no guarda archivos | Usuario |
| `openssl rand -hex 24` | Genera un secreto aleatorio hexadecimal; no guarda archivos | Usuario |
| `nano .env` | Edita las cuatro variables privadas y la URL del despliegue | Propietario |
| `sudo docker compose config --quiet` | Valida e interpola Compose sin imprimir secretos; no crea contenedores | sudo |

```bash
umask 077
cp ~/entorno-t10.example .env
chmod 600 .env
openssl rand -base64 32
openssl rand -hex 24
openssl rand -hex 24
nano .env
```

Completa el archivo con tus propios valores:

```dotenv
APP_URL=http://192.168.1.50
APP_KEY=base64:VALOR_BASE64_GENERADO
DB_PASSWORD=PRIMER_VALOR_HEXADECIMAL
POSTGRES_PASSWORD=SEGUNDO_VALOR_HEXADECIMAL
```

Guarda las dos contraseñas en un lugar privado. `DB_PASSWORD` será la contraseña
del rol `agrofusion_app`; `POSTGRES_PASSWORD` es la del administrador de PostgreSQL.
Son cuentas diferentes y la aplicación no recibe la contraseña administrativa.
Conserva APP_KEY: cambiarla puede invalidar datos cifrados y sesiones.

```bash
sudo docker compose config --quiet
ls -l .env
```

No uses `docker compose config` sin `--quiet`, `docker inspect` completo ni
`printenv` para las evidencias: pueden mostrar credenciales. La captura **07**
solo debe mostrar la validación y permisos de `.env`, sin su contenido.

## 7. Inicializa PostgreSQL y su usuario de aplicación

Estos pasos son para el volumen nuevo de esta VM. Las variables de PostgreSQL
solo inicializan un volumen vacío; editar `.env` no cambia una contraseña de
una base ya creada.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo docker compose up -d db` | Descarga PostgreSQL y crea red, volumen y contenedor de BD | sudo |
| `sudo docker compose ps` | Consulta contenedores y healthchecks; no los cambia | sudo |
| `sudo docker compose exec db psql -U postgres -d agrofusion` | Abre el cliente SQL dentro del contenedor como administrador de BD | sudo para Docker; rol SQL postgres |

```bash
sudo docker compose up -d db
sudo docker compose ps
sudo docker compose exec db psql -U postgres -d agrofusion
```

Espera a que `db` aparezca `healthy` antes de entrar. Dentro de **psql**, ejecuta
una instrucción a la vez:

```sql
CREATE ROLE agrofusion_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
\password agrofusion_app
ALTER DATABASE agrofusion OWNER TO agrofusion_app;
GRANT USAGE, CREATE ON SCHEMA public TO agrofusion_app;
\du agrofusion_app
\q
```

| Instrucción SQL / psql | Qué modifica / por qué |
| --- | --- |
| `CREATE ROLE ...` | Crea un rol con login, sin superusuario ni capacidad de crear roles o bases |
| `\password agrofusion_app` | Solicita dos veces, sin mostrarla, exactamente la contraseña de `DB_PASSWORD`; cambia el verificador del rol |
| `ALTER DATABASE ... OWNER ...` | Permite a la aplicación administrar su propia base y sus migraciones |
| `GRANT USAGE, CREATE ON SCHEMA public ...` | Permite usar el esquema y crear tablas de esta aplicación |
| `\du ...` | Consulta atributos del rol; no muestra su contraseña |
| `\q` | Sale del cliente |

Esto no convierte al rol en administrador del clúster. Para una aplicación con
migraciones, necesita DDL en su base. `observador`, el rol SQL y las cuentas
Laravel son tres identidades distintas. Captura **08** solo de `\du`.

## 8. Construye e inicializa Laravel

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo docker compose build app` | Lee Dockerfile, instala dependencias PHP, compila assets con Vite y crea una imagen | sudo; root solo dentro de la construcción |
| `sudo docker compose up -d app` | Crea el contenedor HTTP y volumen de archivos; espera a PostgreSQL | sudo |
| `... exec --user www-data app php artisan migrate --force` | Crea y actualiza tablas y registra migraciones en PostgreSQL | sudo para Docker; www-data en contenedor y rol SQL de aplicación |
| `... db:seed --class=... --force` | Inserta/actualiza únicamente roles, permisos, catálogos o usuarios indicados | Igual que migraciones |
| `... php artisan tinker` | Abre consola PHP de la aplicación; los cambios dependen de lo que escribas | Igual que migraciones |

```bash
sudo docker compose build app
sudo docker compose up -d app
sudo docker compose exec --user www-data app php artisan migrate --force
sudo docker compose exec --user www-data app php artisan db:seed --class=RoleSeeder --force
sudo docker compose exec --user www-data app php artisan db:seed --class=ConsolidacionRolesPermisosSeeder --force
sudo docker compose exec --user www-data app php artisan db:seed --class=RolePermissionSeeder --force
sudo docker compose exec --user www-data app php artisan db:seed --class=CatalogosOperacionAgricolaSeeder --force
sudo docker compose exec --user www-data app php artisan db:seed --class=AdminUserSeeder --force
```

Comprueba el resultado de **cada comando** antes de seguir. No uses
`migrate:fresh`, `docker compose down -v` ni borres volúmenes para resolver fallos.
No ejecutes `db:seed` sin clase: durante la validación, `DatosPruebaSeeder`
intentó duplicar `Sembrado`, ya creado por las migraciones. La ruta de esta guía
usa solo los seeders anteriores; no asegura tener todos los datos de demostración.

### Sustituye las credenciales demo antes de publicar

`AdminUserSeeder` trae cuentas con una contraseña conocida. En esta **BD nueva
de laboratorio**, desactiva las cuentas demo y define una contraseña propia
para el administrador. No apliques este bloque sobre una base compartida con
usuarios reales: desactiva sus cuentas.

Abre Tinker sin grabar ni capturar este paso:

```bash
sudo docker compose exec --user www-data app php artisan tinker
```

Dentro de Tinker pega esta función completa, léela antes y ejecútala una vez:

```php
(function () {
    $clave = \Laravel\Prompts\password('Nueva contraseña admin (12 o más caracteres)', required: true);
    if (strlen($clave) < 12) {
        throw new \RuntimeException('Usa al menos 12 caracteres. No se aplicaron cambios.');
    }
    \Illuminate\Support\Facades\DB::transaction(function () use ($clave) {
        \App\Models\Usuario::query()->update(['activo' => false]);
        $admin = \App\Models\Usuario::where('email', 'admin@agrofusion.com')->firstOrFail();
        $admin->passwordhash = \Illuminate\Support\Facades\Hash::make($clave);
        $admin->activo = true;
        $admin->estado_cuenta = 'aprobado';
        $admin->save();
    });
})()
```

La función pide la contraseña sin imprimirla, verifica longitud, desactiva las
cuentas iniciales y guarda el hash de la contraseña nueva. La transacción revierte
todo si ocurre un error. La función evita que Tinker muestre la contraseña como
resultado de una asignación. Escribe `exit` para salir. La cuenta de aplicación
será `admin@agrofusion.com` con **tu contraseña**, no la del README antiguo.
No vuelvas a ejecutar `AdminUserSeeder`: restablecería las credenciales demo.

El Dockerfile limita escritura de Laravel a `storage` y `bootstrap/cache` para `www-data`.
No hace falta `chmod 777`. La imagen no incluye `.env`, la SQLite local ni
dependencias de Windows. El volumen `app-storage` conserva las fotos subidas.

Consulta, sin modificar, las migraciones y los contenedores:

```bash
sudo docker compose exec --user www-data app php artisan migrate:status
sudo docker compose ps
curl -i http://127.0.0.1:8080/api/test-api
```

Espera migraciones `Ran`, contenedores activos y HTTP 200 con `{"ok":true}`.
La API pública de prueba no consulta PostgreSQL; la conexión se demuestra en
el paso 10. Captura **09**.

## 9. Publica con Nginx del host

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `sudo cp nginx.conf /etc/nginx/sites-available/agrofusion` | Instala el sitio de esta guía | sudo |
| `sudo ln -s ...` | Habilita el sitio creando un enlace en `sites-enabled` | sudo |
| `sudo unlink /etc/nginx/sites-enabled/default` | Quita solo el enlace del sitio de bienvenida; conserva su archivo original | sudo |
| `sudo nginx -t` | Comprueba sintaxis y archivos referenciados | sudo; consulta |
| `sudo systemctl enable --now nginx` | Habilita e inicia el servicio al arrancar | sudo |
| `sudo systemctl reload nginx` | Aplica la configuración validada sin cortar el proceso principal | sudo |
| `systemctl is-active nginx` | Consulta si está activo | Usuario |

```bash
sudo cp nginx.conf /etc/nginx/sites-available/agrofusion
sudo ln -s /etc/nginx/sites-available/agrofusion /etc/nginx/sites-enabled/agrofusion
sudo unlink /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
systemctl is-active nginx
curl -i http://127.0.0.1/api/test-api
```

Este bloque asume el Nginx recién instalado. Si el enlace ya existe, no lo
crees de nuevo. Si `nginx -t` falla, corrige el problema antes de recargar.
El sitio reenvía a Laravel, conserva el Host y sustituye encabezados de proxy
del cliente. Laravel solo publica su directorio `public` a través de Apache.
Captura **10**.

Docker puede desviar tráfico antes de las reglas UFW de entrada. Por eso no
confiamos solo en UFW para proteger puertos Docker: el único puerto publicado
por Compose es `127.0.0.1:8080`; la BD no tiene `ports`. Consulta la explicación
oficial de [Docker y UFW](https://docs.docker.com/engine/network/packet-filtering-firewalls/).

Esta ruta usa HTTP para una demostración en una LAN de confianza con cuentas
de laboratorio. Para Internet o datos reales necesitas HTTPS y cookies seguras.
No reenvíes el puerto de tu router para convertir este laboratorio en un servicio
público. SSH sí cifra la administración.

## 10. Verifica web, API, conexión a PostgreSQL y puertos

### Desde Ubuntu

Todos los comandos de este bloque son de consulta. Los `exec` requieren sudo
para Docker; PHP se ejecuta como `www-data`. `tinker --execute` ejecuta la
expresión dada; aquí solo hace un SELECT y muestra datos no secretos.

```bash
curl -i http://127.0.0.1/up
curl -i http://127.0.0.1/api/test-api
curl -i -H 'Accept: application/json' http://127.0.0.1/api/me
sudo docker compose exec --user www-data app php artisan tinker --execute="dump(DB::select('SELECT current_database() AS base, current_user AS rol, version() AS motor'));"
sudo docker compose port app 80
sudo docker compose port db 5432
sudo ss -lntp
sudo ufw status verbose
```

Espera `/up` y `/api/test-api` con 200, y `/api/me` **sin token con 401**.
El SELECT debe mostrar PostgreSQL, base `agrofusion` y rol `agrofusion_app`.
`compose port app 80` debe mostrar loopback; `compose port db 5432` no debe
mostrar un puerto publicado y puede terminar con un aviso o código distinto de
cero. Esto último es esperado. `ss` muestra los listeners del host; Docker puede
implementar publicación mediante reglas NAT, por lo que también se verifica
desde Windows. Capturas **11 y 12**.

En `compose ps`, ver solo `5432/tcp` en la fila db indica un puerto del
contenedor; una publicación al host tendría una flecha como `IP:PUERTO->5432/tcp`.

### Desde Windows: prueba externa y autenticación de API

Abre en el navegador **`http://192.168.1.50/login`**, inicia sesión y navega por
el sistema. Incluye la barra de direcciones en las capturas **13 y 14**. Haz
la prueba desde Windows, no desde un navegador dentro del servidor.

En PowerShell, `Test-NetConnection` solo prueba conectividad TCP y puede tardar
cuando un puerto está bloqueado. `Invoke-RestMethod` hace peticiones HTTP. El
login siguiente crea un token en la BD y logout lo revoca. Las credenciales y
el token se guardan temporalmente en variables, sin imprimirlos.

```powershell
Test-NetConnection 192.168.1.50 -Port 22
Test-NetConnection 192.168.1.50 -Port 80
Test-NetConnection 192.168.1.50 -Port 5432
Test-NetConnection 192.168.1.50 -Port 8080
Invoke-RestMethod http://192.168.1.50/api/test-api
$cred = Get-Credential -UserName 'admin@agrofusion.com' -Message 'Cuenta Laravel del laboratorio'
$payload = @{ email = $cred.UserName; password = $cred.GetNetworkCredential().Password } | ConvertTo-Json
$sesion = Invoke-RestMethod -Method Post -Uri http://192.168.1.50/api/login -ContentType 'application/json' -Body $payload
$headers = @{ Authorization = "Bearer $($sesion.token)" }
$perfil = Invoke-RestMethod -Uri http://192.168.1.50/api/me -Headers $headers
$perfil | Select-Object usuarioid,email,activo,estado_cuenta
Invoke-RestMethod -Method Post -Uri http://192.168.1.50/api/logout -Headers $headers
Remove-Variable cred,payload,sesion,headers,perfil
```

Espera `TcpTestSucceeded: True` solo para 22 y 80, `False` para 5432 y 8080.
El perfil autenticado demuestra el recorrido cliente → Nginx → API → BD.
No ejecutes `$sesion`, `$headers` ni `$payload` por separado: revelarían secretos.
`Remove-Variable` elimina las referencias de esta sesión, sin prometer borrado
seguro de la memoria. Captura **15** del resultado de perfil, sin variables privadas.

## 11. Conecta la app Flutter desde tu equipo

En **Windows**, abre la carpeta `Mobile`. No necesitas instalar Flutter en el
servidor. Un teléfono físico y Windows deben alcanzar VM_IP; desde el teléfono
prueba primero `http://192.168.1.50/api/test-api` en su navegador.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `flutter doctor` | Diagnostica el SDK y herramientas del cliente | Usuario de Windows |
| `flutter pub get` | Descarga dependencias y actualiza artefactos locales del proyecto móvil | Usuario |
| `flutter devices` | Lista dispositivos/emuladores disponibles | Usuario |
| `flutter run ... --dart-define=...` | Compila e instala una app debug con la URL de esta VM | Usuario; permisos de depuración del dispositivo |
| `flutter build apk --debug ...` | Genera el APK debug en `build/app/outputs/flutter-apk/app-debug.apk` | Usuario |

```powershell
Set-Location 'C:\Univalle\ProyectoDeSistemasIII\t2-Trazabilidad-Agricola\Mobile'
flutter doctor
flutter pub get
flutter devices
flutter run -d ID_DISPOSITIVO --dart-define=API_BASE_URL=http://192.168.1.50/api
```

Sustituye `ID_DISPOSITIVO` por el identificador de `flutter devices`, sin los
signos de ejemplo. Usa un Android físico con depuración USB o un emulador Android
en Windows que tenga ruta hacia la VM. La URL debe terminar en **`/api`**.
`127.0.0.1` en el móvil es el móvil; `10.0.2.2` apunta al host del emulador,
no directamente a la VM. Con puente utiliza la IP real de Ubuntu.

En esta versión, `Mobile/android/app/src/debug/AndroidManifest.xml` ya permite
HTTP para debug. La versión release no ofrece esa misma configuración.
Para entregar un APK de esta demostración HTTP, compila **debug**:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.50/api
```

En la app, pulsa **Comprobar conexión**, inicia sesión y abre **Mi perfil**.
Captura **16** de conexión y **17** del perfil. Muestra también en Ubuntu una
petición correspondiente en el log de Nginx (paso 13). Un JSON abierto en el
navegador del teléfono no sustituye la evidencia de la aplicación móvil.

Si aparece cuenta pendiente, apruébala desde administración antes de intentar
login; el registro móvil no inicia sesión automáticamente. Para esta prueba
puedes utilizar la cuenta activa de laboratorio preparada en el paso 8.
Flutter Android nativo no requiere abrir puertos adicionales ni configurar
CORS. Flutter web es un cliente distinto y no reemplaza esta prueba móvil.

## 12. Crea un backup y prueba una restauración

Hazlo **en Ubuntu**, en `/srv/agrofusion/docs/tarea10`. El backup guarda datos de
esta BD; PostgreSQL no incluye las fotos subidas, por eso se respaldan aparte.
El dump tampoco incluye los roles del clúster: el paso 7 documenta su recreación.

### Respalda y comprueba los archivos

| Comando / expresión | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `mkdir -p backups` / `chmod 700 backups` | Crea y restringe el directorio de copias del administrador | Usuario |
| `MARCA=$(date +%Y%m%d-%H%M%S)` | Guarda fecha/hora en una variable del shell; no modifica archivos | Usuario |
| `BACKUP=...` | Guarda la ruta del archivo en una variable | Usuario |
| `... psql ... -c 'SQL'` | Ejecuta el SQL de evidencia indicado; crea una tabla y un registro de prueba | sudo para Docker; rol SQL postgres |
| `... pg_dump -Fc ... > archivo` | Produce un dump consistente, comprimido, de una BD; la redirección crea el archivo en Ubuntu | sudo para Docker; archivo del usuario |
| `... tar -czf - ... > archivo` | Respalda `storage/app/public` desde el contenedor | sudo para Docker; archivo del usuario |
| `cp .env ...` | Conserva una copia privada de configuración y APP_KEY, no entregable | Propietario |
| `sha256sum ...` | Calcula huellas de integridad; la redirección guarda el comprobante | Usuario |
| `... pg_restore --list` | Comprueba que el dump se puede interpretar; no restaura | sudo para Docker |

Primero crea un marcador sin información privada. Así comprobarás un dato
conocido después de restaurar:

```bash
umask 077
mkdir -p backups
chmod 700 backups
MARCA=$(date +%Y%m%d-%H%M%S)
BACKUP="backups/agrofusion-$MARCA.dump"
sudo docker compose exec -T db psql -U postgres -d agrofusion -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS evidencia_t10 (id integer PRIMARY KEY, descripcion text NOT NULL); INSERT INTO evidencia_t10 VALUES (1, 'BACKUP_T10_VERIFICADO') ON CONFLICT (id) DO NOTHING;"
sudo docker compose exec -T db pg_dump -U postgres -d agrofusion -Fc --no-owner --no-privileges > "$BACKUP"
```

Comprueba inmediatamente el resultado del último comando con `echo $?`: solo
muestra su código de salida; **0 significa éxito**. Si falla, no consideres
válido un archivo solo porque exista. Después continúa:

```bash
sudo docker compose exec -T app tar -czf - -C /var/www/html/storage app/public > "backups/uploads-$MARCA.tgz"
cp .env "backups/entorno-$MARCA.conf"
sha256sum "$BACKUP" "backups/uploads-$MARCA.tgz" > "backups/SHA256SUMS-$MARCA.txt"
ls -lh backups
sudo docker compose exec -T db pg_restore --list < "$BACKUP"
sudo docker compose exec -T db psql -U postgres -d agrofusion -c "SELECT count(*) AS usuarios_original FROM usuario; SELECT * FROM evidencia_t10;"
```

Anota el número de usuarios y el marcador. Captura **18** sin abrir el archivo
`entorno-*.conf`. Mantén esta sesión para conservar las variables. En una sesión
nueva, asigna `BACKUP` a la ruta real que aparece en `ls`, no a un archivo inventado.

### Restaura en una base nueva y comprueba desde Laravel

Restaurar en otra base demuestra la recuperación sin borrar la BD operativa.
El nombre `agrofusion_restore` debe estar libre: si ya existe, elige otro nombre
y reemplázalo en todos los comandos. No lo elimines automáticamente.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `createdb ... -O agrofusion_app agrofusion_restore` | Crea una BD de prueba propiedad del rol de la aplicación | sudo para Docker; postgres |
| `pg_restore ... --role=agrofusion_app` | Restaura esquema y datos con ese propietario en la nueva BD; falla ante errores | sudo para Docker; postgres cambia al rol indicado |
| `psql ... SELECT ...` | Consulta filas y conteos restaurados | sudo para Docker; consulta SQL |
| `tinker --execute=...` | Cambia solo la conexión de ese proceso PHP, la reinicia y consulta la BD restaurada | sudo para Docker; www-data y rol SQL de app |

```bash
sudo docker compose exec -T db createdb -U postgres -O agrofusion_app agrofusion_restore
sudo docker compose exec -T db pg_restore -U postgres -d agrofusion_restore --role=agrofusion_app --no-owner --no-privileges --exit-on-error < "$BACKUP"
sudo docker compose exec -T db psql -U postgres -d agrofusion_restore -c "SELECT count(*) AS usuarios_restaurados FROM usuario; SELECT * FROM evidencia_t10;"
sudo docker compose exec --user www-data app php artisan tinker --execute="config(['database.connections.pgsql.database' => 'agrofusion_restore']); DB::purge('pgsql'); dump(DB::select('SELECT current_database() AS base, descripcion FROM evidencia_t10 WHERE id = 1'));"
```

Espera el mismo conteo de usuarios, el marcador y una consulta Laravel indicando
`agrofusion_restore`. El Compose sigue conectado a `agrofusion`; esta prueba no
cambia la configuración permanente. Captura **19**.

El marcador fue creado por postgres para la demostración; el dump omite dueños
y se restaura como `agrofusion_app`, de modo que Laravel puede leerlo en la copia.

Para una recuperación completa después de perder la VM: reconstruye Ubuntu,
copia el código y esta guía, recupera el `.env` privado y su APP_KEY, recrea el
rol SQL y una BD vacía, restaura el dump y los uploads y vuelve a publicar con
Nginx. El backup no sustituye al código ni a esa configuración.

### Saca una copia fuera de la VM

En **PowerShell**, `New-Item` crea el directorio local; `scp` copia los backups
por SSH. Copia solo el dump, uploads y huellas para la entrega. La copia de
entorno con secretos debe guardarse por separado de forma privada.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\Documents\Tarea10-backups"
scp 'infraadmin@192.168.1.50:/srv/agrofusion/docs/tarea10/backups/*.dump' "$env:USERPROFILE\Documents\Tarea10-backups\"
scp 'infraadmin@192.168.1.50:/srv/agrofusion/docs/tarea10/backups/uploads-*.tgz' "$env:USERPROFILE\Documents\Tarea10-backups\"
scp 'infraadmin@192.168.1.50:/srv/agrofusion/docs/tarea10/backups/SHA256SUMS-*.txt' "$env:USERPROFILE\Documents\Tarea10-backups\"
```

Un snapshot de VirtualBox es útil, pero no reemplaza el dump ni esta prueba.
Referencias: [pg_dump 16](https://www.postgresql.org/docs/16/app-pgdump.html)
y [pg_restore 16](https://www.postgresql.org/docs/16/app-pgrestore.html).

## 13. Provoca, diagnostica y resuelve un incidente controlado

Hazlo con el backup ya verificado y sin otros usuarios trabajando. No borres
datos ni cambies contraseñas para provocar el fallo: detén PostgreSQL y luego
recupéralo. Un endpoint que no consulta la BD puede seguir respondiendo 200.

| Comando | Qué hace / qué modifica | Privilegios |
| --- | --- | --- |
| `mkdir -p ~/evidencias` | Crea directorio para registros textuales | Usuario |
| `script -a ~/evidencias/incidente.txt` | Graba la terminal hasta `exit`; crea/amplía ese archivo | Usuario |
| `date -Is` | Muestra hora para la cronología | Usuario |
| `sudo docker compose stop db` | Detiene solo PostgreSQL, conserva contenedor y volumen | sudo |
| `sudo docker compose logs --tail=60 app db` | Muestra logs recientes; revisa si contienen datos privados antes de entregar | sudo |
| `sudo tail -n 20 /var/log/nginx/...` | Lee logs de acceso y error de Nginx | sudo |
| `sudo journalctl -u nginx -n 30 --no-pager` | Consulta el log del servicio del sistema | sudo |
| `sudo docker compose start db` | Inicia la misma BD con sus mismos datos | sudo |
| `exit` | Finaliza el shell de `script` y cierra el registro | Usuario |

```bash
mkdir -p ~/evidencias
script -a ~/evidencias/incidente.txt
date -Is
sudo docker compose ps
sudo docker compose stop db
sudo docker compose ps -a
curl -i -H 'Accept: application/json' http://127.0.0.1/api/login -H 'Content-Type: application/json' -d '{"email":"prueba-incidente@example.com","password":"valor-ficticio"}'
sudo docker compose logs --tail=60 app db
sudo tail -n 20 /var/log/nginx/agrofusion.error.log
sudo journalctl -u nginx -n 30 --no-pager
```

La petición usa valores ficticios: al intentar consultar un usuario, la API debe
fallar por conexión a BD, normalmente con 500 y sin detalles internos al cliente.
El log de Laravel debe permitir relacionar el error con PostgreSQL detenido.
Nginx puede no registrar error propio cuando solo reenvía un 500; consulta
también su access log. Captura **20** del fallo y **21** del diagnóstico.

Recupera inmediatamente:

```bash
sudo docker compose start db
sudo docker compose ps
sudo docker compose exec --user www-data app php artisan tinker --execute="dump(DB::select('SELECT current_database() AS base, current_user AS rol'));"
date -Is
exit
```

Cuando db esté `healthy`, repite login y perfil desde la app o PowerShell.
Un **401 por credenciales ficticias** con la BD recuperada ya demuestra una
respuesta distinta al fallo de conexión; con credenciales válidas debe devolver
200. Captura **22**. Completa el registro de incidente de [ENTREGA.md](ENTREGA.md)
con tus horas y resultados, no con resultados esperados escritos como reales.

`unless-stopped` no reinicia un contenedor que tú detuviste deliberadamente con
`stop`. En este incidente se recupera con `start`. Los healthchecks detectan
estado, pero no reinician por sí solos un proceso vivo que está `unhealthy`.

Para correlacionar la prueba móvil, `sudo tail -n 30
/var/log/nginx/agrofusion.access.log` muestra método, ruta, estado, IP y hora
de las peticiones. Es solo lectura y requiere sudo. Captura **23**.

## 14. Comprueba el arranque y la operación por otro compañero

Los dos servicios Compose tienen `restart: unless-stopped`. Compruébalo sin
mostrar variables de entorno:

```bash
sudo docker inspect --format '{{.Name}} restart={{.HostConfig.RestartPolicy.Name}}' "$(sudo docker compose ps -q app)" "$(sudo docker compose ps -q db)"
sudo systemctl is-enabled docker nginx ssh
sudo reboot
```

`docker inspect --format` solo muestra el nombre y la política de los dos
contenedores seleccionados. `is-enabled` solo consulta la habilitación.
`reboot` reinicia toda la VM: asegúrate de haber iniciado db tras el incidente.
Vuelve a conectar por SSH después del reinicio y ejecuta:

```bash
cd /srv/agrofusion/docs/tarea10
sudo docker compose ps
systemctl is-active nginx
curl -i http://127.0.0.1/api/test-api
sudo docker compose exec --user www-data app php artisan tinker --execute="dump(DB::select('SELECT current_database() AS base, current_user AS rol'));"
```

La política de reinicio y Docker habilitado permiten levantar los contenedores;
el orden de disponibilidad tras reiniciar puede causar errores transitorios
hasta que PostgreSQL termine de arrancar. Verifica después el login y el perfil.
Captura **24**.

Pide a otro estudiante que siga esta guía para conectarse, identificar los
servicios, abrir la web, comprobar la API y localizar el backup. Para acreditar
la instalación completa desde cero, debe repetirla en otra VM o una copia limpia.
Registra exactamente cuál de las dos pruebas hizo, su nombre, fecha, problemas
y correcciones. Una revisión de lectura no acredita ejecución.

## 15. Manual breve para operar el servidor

Ejecuta en `/srv/agrofusion/docs/tarea10`. Antes de cada acción, comprueba si
es consulta o modificación:

| Tarea / comando | Efecto y archivos | Privilegios |
| --- | --- | --- |
| Estado: `sudo docker compose ps` | Consulta contenedores | sudo |
| Logs: `sudo docker compose logs --tail=100 app db` | Consulta salida de procesos; logs Docker rotan a 10 MB por archivo, 3 archivos por servicio | sudo |
| Recursos: `sudo docker stats --no-stream` | Consulta CPU/RAM de contenedores | sudo |
| Detener servicio: `sudo docker compose stop app` | Interrumpe web/API; conserva datos | sudo |
| Iniciar servicio: `sudo docker compose start app` | Reanuda el contenedor existente | sudo |
| Reiniciar: `sudo docker compose restart app` | Reinicia el proceso, no aplica cambios de variables del Compose | sudo |
| Aplicar `.env`: `sudo docker compose up -d app` | Recrea app si cambió su configuración; sesiones/uploads siguen en volumen | sudo |
| Publicador: `sudo nginx -t` y luego `sudo systemctl reload nginx` | Valida y aplica archivos en `/etc/nginx` | sudo |
| Cambios de código: `sudo docker compose build app`, después `sudo docker compose up -d app` | Construye y sustituye imagen/contenedor; realiza backup antes | sudo |
| Cambios de esquema: `sudo docker compose exec --user www-data app php artisan migrate --force` | Modifica BD con migraciones pendientes; realiza backup antes | sudo y rol SQL de app |
| Ver configuración pública: `cat compose.yaml` / `cat nginx.conf` | Consulta las plantillas, sin expandir `.env` | Usuario |

Después de reconstruir o cambiar configuración, repite API, SELECT y login.
No ejecutes seeders en cada reinicio. No borres volúmenes para actualizar.

### Diagnóstico rápido

| Síntoma | Comprueba primero | Corrección orientada a la causa |
| --- | --- | --- |
| SSH no conecta | IP, puente, UFW, servicio SSH y cliente autorizado | Corrige IP/regla específica desde consola de la VM |
| Otro equipo no abre la web | `Test-NetConnection` a 80, IP, Nginx activo, misma LAN | Corrige conectividad o servicio; no abras todos los puertos |
| Página de bienvenida Nginx | Sitio default todavía habilitado | Revisa enlaces y valida antes de recargar |
| 502 Bad Gateway | App detenida o no escucha en 127.0.0.1:8080 | Revisa `compose ps`, logs y curl al backend |
| Laravel 500 | Logs de app, conexión DB, APP_KEY y permisos de storage | Corrige el dato o permiso específico; no actives debug público |
| `password authentication failed` | `.env` no coincide con contraseña real del rol | Cambia con `\password` y recrea app si editaste `.env`; conserva datos |
| Error de permisos PostgreSQL | Propietario de BD/esquema y rol efectivo | Revisa paso 7 y el SELECT del paso 10 |
| Móvil no conecta | URL compilada con `/api`, VM_IP, debug Android, ruta desde teléfono | Reconstruye con la URL correcta; usa APK debug para esta LAN HTTP |
| Perfil 401 | Falta token o fue revocado | Inicia sesión otra vez |
| Perfil 403 | Cuenta pendiente/inactiva o permiso denegado | Revisa aprobación y rol; no elimines autenticación |
| Seed genérico duplica `Sembrado` | `DatosPruebaSeeder` y migraciones ya insertaron el catálogo | Usa solo los seeders verificados del paso 8 |

Si el puente no funciona por restricciones de tu Wi-Fi, usa otra LAN sin
aislamiento o conecta el host por cable. Como alternativa de laboratorio,
VirtualBox NAT con reenvío de **127.0.0.1:2222 → VM:22** y
**127.0.0.1:8088 → VM:80** permite probar desde Windows con
`ssh -p 2222 ...@127.0.0.1` y `http://127.0.0.1:8088`. Debes adaptar la regla
SSH a la IP de origen vista por la VM y APP_URL a la URL usada por el cliente.
Ese reenvío solo en localhost no sirve para un teléfono físico; para cumplir
el entregable móvil utiliza puente o un emulador Android que pueda acceder al
host y compila con su ruta real hacia el puerto reenviado. No mezcles ambas
topologías ni atribuyas la IP 10.0.2.2 a Ubuntu sin comprobarla.

## 16. Prepara la entrega

1. Sigue [CAPTURAS.md](CAPTURAS.md) para las evidencias, en el orden de la guía.
2. Completa [ENTREGA.md](ENTREGA.md) con valores y resultados reales.
3. Completa [REGISTRO-IA.md](REGISTRO-IA.md) con decisiones y verificaciones.
4. Entrega la documentación, configuraciones sin secretos, APK debug y backups
   de datos de laboratorio según solicite tu docente.
5. Mantén la VM encendida y accesible durante la demostración. Confirma si el
   docente requiere exportar OVA; la consigna no define ese formato.

Con un solo envío permitido, usa la lista de control de ENTREGA.md antes de
subir el paquete. No marques pruebas pendientes como completadas.

### Fuentes técnicas para explicar y validar los cambios

- [Instala Ubuntu Server](https://ubuntu.com/tutorials/install-ubuntu-server): instalación por consola.
- [OpenSSH en Ubuntu](https://documentation.ubuntu.com/server/how-to/security/openssh-server/): configuración modular y validación antes de aplicar.
- [Docker Engine en Ubuntu](https://docs.docker.com/engine/install/ubuntu/): repositorio oficial y paquetes.
- [Docker y firewalls](https://docs.docker.com/engine/network/packet-filtering-firewalls/): interacción con UFW.
- [Permisos de Docker en Linux](https://docs.docker.com/engine/install/linux-postinstall/): alcance administrativo del grupo docker.
- [Guía de Nginx](https://nginx.org/en/docs/beginners_guide.html): proxy HTTP y aplicación de configuración.
- [Despliegue de Laravel 12](https://laravel.com/docs/12.x/deployment): directorio público, configuración y permisos.
- [pg_dump 16](https://www.postgresql.org/docs/16/app-pgdump.html) y [pg_restore 16](https://www.postgresql.org/docs/16/app-pgrestore.html): respaldo y restauración.
- [Configuración de seguridad de Android](https://developer.android.com/privacy-and-security/security-config): comportamiento de HTTP/HTTPS.

La aplicación usa funciones de clima y blockchain externas. No se necesitan
claves de esos servicios para probar infraestructura, login y perfil. Esta guía
deja blockchain desactivado; no atribuyas esa funcionalidad externa a las pruebas
realizadas ni incluyas tokens reales en el informe.
