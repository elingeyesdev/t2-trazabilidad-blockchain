# Informe de implementación de infraestructura

Completa este documento después de ejecutar las pruebas. Sustituye `PENDIENTE`
por hechos observados y referencias a archivos. No reemplaces una prueba
faltante por la descripción de lo que debería suceder.

## Identificación

| Dato | Valor real |
| --- | --- |
| Materia, tarea y docente | PENDIENTE |
| Integrantes | PENDIENTE |
| Fecha y zona horaria | PENDIENTE |
| Proyecto | AgroFusion: trazabilidad agrícola |
| Revisión Git y cambios locales desplegados | PENDIENTE |
| Hipervisor y versión | PENDIENTE |
| Ubuntu y arquitectura | PENDIENTE |
| Hostname | PENDIENTE |
| IP, prefijo, gateway e interfaz | PENDIENTE |
| Red: puente u otra topología real | PENDIENTE |
| URL web y URL base de API móvil | PENDIENTE |
| Usuario administrador y usuario limitado | PENDIENTE; sin contraseñas |
| Versiones Docker, Compose, PHP, PostgreSQL y Nginx | PENDIENTE |
| CPU/RAM/disco asignados | PENDIENTE |
| CPU/RAM/disco utilizados en la prueba | PENDIENTE |

## Decisiones de infraestructura

Explica con tus palabras por qué asignaste esos recursos, para qué sirve cada
servicio, qué contiene cada volumen y por qué solo permitiste 22 y 80 de entrada.
Incluye el diagrama de README adaptado a tu topología real y sus IP.

PENDIENTE: justificación propia y límites de la demostración HTTP en LAN.

## Comandos y cambios realizados

El catálogo por pasos está en README.md. Para cada modificación adicional que
hiciste durante la instalación, registra:

| Fecha/hora | Equipo y usuario | Comando exacto sin secretos | Qué hizo | Archivos/datos modificados | Privilegios | Resultado y comprobación |
| --- | --- | --- | --- | --- | --- | --- |
| PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |

No incluyas valores de contraseñas en el comando exacto. Especifica que se
ingresaron mediante prompt oculto o editor privado. Para los comandos de
consulta indica «solo lectura». Adjunta únicamente transcripciones revisadas.

## Resultados de verificación

| Criterio de la consigna | Prueba realizada | Resultado observado | Archivo de evidencia |
| --- | --- | --- | --- |
| Ubuntu sin entorno gráfico | Consola y objetivo multi-user | PENDIENTE | PENDIENTE |
| Hostname e IP identificables | hostnamectl y red | PENDIENTE | PENDIENTE |
| SSH desde cliente | PowerShell a Ubuntu | PENDIENTE | PENDIENTE |
| PuTTY desde cliente | Sesión independiente | PENDIENTE | PENDIENTE |
| UFW con solo puertos necesarios | Estado y pruebas TCP externas | PENDIENTE | PENDIENTE |
| Nginx activo y configurado | Sintaxis y publicación | PENDIENTE | PENDIENTE |
| Web desde otro dispositivo | Login y navegación desde Windows | PENDIENTE | PENDIENTE |
| API responde y protege datos | Test público, me sin token y con token | PENDIENTE | PENDIENTE |
| API conectada a PostgreSQL | SELECT por Laravel y perfil por HTTP | PENDIENTE | PENDIENTE |
| BD sin exposición pública | Sin ports y TCP 5432 inaccesible | PENDIENTE | PENDIENTE |
| Usuario con privilegios mínimos | observador sin sudo, Docker ni lectura de .env | PENDIENTE | PENDIENTE |
| Móvil conectado al servidor | Conexión, login y perfil en Android | PENDIENTE | PENDIENTE |
| Política de reinicio | Inspección limitada y reinicio VM | PENDIENTE | PENDIENTE |
| Backup existente | Dump legible y copia fuera de VM | PENDIENTE | PENDIENTE |
| Restauración probada | Base nueva, conteos, marcador y consulta Laravel | PENDIENTE | PENDIENTE |
| Incidente resuelto | Fallo, diagnóstico y recuperación | PENDIENTE | PENDIENTE |
| Otro estudiante siguió el README | Registro de ejecución y correcciones | PENDIENTE | PENDIENTE |

## Backup y recuperación

| Dato | Resultado real |
| --- | --- |
| Fecha/hora de backup | PENDIENTE |
| Nombre, tamaño y SHA-256 del dump | PENDIENTE |
| Nombre, tamaño y SHA-256 del respaldo de uploads | PENDIENTE |
| Ubicación de la copia fuera de VM | PENDIENTE |
| Configuración y APP_KEY guardadas de forma privada | PENDIENTE; sin incluir valores |
| Base de origen / base restaurada | PENDIENTE |
| Conteo usuarios original / restaurado | PENDIENTE |
| Marcador recuperado | PENDIENTE |
| Consulta desde Laravel a la copia restaurada | PENDIENTE |
| Duración aproximada de recuperación | PENDIENTE |

Explica qué recupera el dump, qué recupera el archivo de uploads y por qué los
roles SQL, el código y la configuración también son necesarios.

## Incidente documentado

- **Identificador y responsable:** PENDIENTE.
- **Inicio y fin:** PENDIENTE.
- **Impacto observado:** PENDIENTE.
- **Acción que lo provocó:** PENDIENTE.
- **Síntoma y estado HTTP:** PENDIENTE.
- **Logs y comandos de diagnóstico:** PENDIENTE.
- **Causa identificada y evidencia:** PENDIENTE.
- **Corrección aplicada:** PENDIENTE.
- **Pruebas de recuperación:** PENDIENTE.
- **Prevención o aprendizaje:** PENDIENTE.

Un incidente simulado debe identificarse como tal. Si además reproduces el
fallo del seeder general, regístralo por separado con evidencia de tu propia VM.

## Prueba por otro estudiante

| Campo | Registro |
| --- | --- |
| Estudiante que ejecutó los pasos | PENDIENTE |
| Fecha/hora | PENDIENTE |
| Alcance: instalación limpia completa o manual de operación | PENDIENTE |
| Entorno desde el que lo hizo | PENDIENTE |
| Pasos completados sin ayuda adicional | PENDIENTE |
| Pasos ambiguos o que fallaron | PENDIENTE |
| Correcciones incorporadas al README | PENDIENTE |
| Resultado de repetir los pasos corregidos | PENDIENTE |

No publiques credenciales para facilitar la prueba: compártelas por un medio
privado autorizado y limita los permisos a lo necesario.

## Estructura sugerida del paquete de entrega

```text
Tarea10-Apellido-Nombre/
  INFORME.pdf                       # Este informe completado y exportado
  README.md                         # Guía, adaptada a tu entorno real
  REGISTRO-IA.md
  CAPTURAS.md
  configuracion/
    compose.yaml
    Dockerfile
    Dockerfile.dockerignore
    apache.conf
    nginx.conf
    .env.example                    # Plantilla vacía, nunca el .env real
  evidencias/
    01-recursos-vm.png
    ...
    25-prueba-companero.png
    incidente-revisado.txt
  backups/
    agrofusion-FECHA.dump            # Solo datos de laboratorio
    uploads-FECHA.tgz
    SHA256SUMS-FECHA.txt
  movil/
    app-debug.apk
```

Los archivos Dockerfile y Compose se operan en su posición original dentro
del repositorio (`docs/tarea10/`), porque usan rutas relativas. La carpeta
`configuracion/` del paquete es una copia para revisión; para reproducir usa
la estructura original con `Web/` y `docs/tarea10/`.

No se presupone que debas adjuntar una VM OVA de varios GB: confirma el formato
de entrega solicitado por el docente. Conserva la VM desplegada disponible.
No adjuntes `node_modules`, `vendor`, `.git`, `.env`, claves privadas o tokens.
Si el docente exige credenciales de prueba, entrégalas por separado de forma
privada. No envíes datos reales en los backups.

## Revisión antes del único envío

- [ ] Cada integrante puede explicar el recorrido cliente → Nginx → app → BD.
- [ ] Los comandos del README incluyen propósito, archivos y privilegios.
- [ ] Las IP y URL del informe coinciden con la VM y el APK entregado.
- [ ] PowerShell SSH y PuTTY se conectan desde el cliente autorizado.
- [ ] `observador` no tiene privilegios administrativos ni acceso a `.env`.
- [ ] UFW está activo y PostgreSQL/8080 no son accesibles desde Windows.
- [ ] La web funciona desde Windows y el móvil muestra conexión y perfil.
- [ ] El dump tiene contenido, se restauró y las comprobaciones coinciden.
- [ ] Existe una copia de respaldo fuera de la VM.
- [ ] El incidente incluye síntomas, logs, causa, solución y prueba posterior.
- [ ] Se probó el arranque después de reiniciar la VM.
- [ ] Otro estudiante ejecutó los pasos documentados y quedó registrado.
- [ ] Las capturas son legibles, identificables y no muestran secretos.
- [ ] Se completó REGISTRO-IA.md con aceptaciones, correcciones y verificación.
- [ ] El PDF y el ZIP abren y contienen los archivos esperados.
- [ ] No quedan campos PENDIENTE presentados como resultados definitivos.
