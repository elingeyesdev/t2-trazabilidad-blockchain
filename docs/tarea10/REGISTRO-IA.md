# Registro del uso de IA

La consigna permite asistencia y exige validar cada instrucción y explicar los
cambios. Este archivo registra esa validación. No pegues secretos, `.env`, claves
privadas, tokens, datos personales reales ni respuestas de login completas.

## Asistencia recibida al preparar esta guía

La IA inspeccionó código y configuración del repositorio y consultó documentación
oficial. No administró la VM de Ubuntu del estudiante ni tomó sus capturas.
Las pruebas locales se detallan en VALIDACION.md y no sustituyen tu ejecución.

| Consulta o hallazgo | Propuesta recibida | Decisión y motivo | Verificación del estudiante |
| --- | --- | --- | --- |
| Cómo adaptar el proyecto a Ubuntu Server | Guía con recursos, red, usuarios, SSH, UFW y servicios por terminal | PENDIENTE: aceptar/corregir después de revisar | PENDIENTE: versión, comandos y evidencias reales |
| Compose depende de redes externas y el Nginx anterior espera PHP-FPM, pero el Dockerfile arranca HTTP | Configuración separada en docs/tarea10: app Apache/PHP y Nginx del host como proxy | PENDIENTE | PENDIENTE: build, nginx -t y HTTP desde cliente |
| El ejemplo local de Web usa SQLite | PostgreSQL 16 dentro de Compose con volumen y red interna | PENDIENTE | PENDIENTE: SELECT de Laravel y perfil autenticado |
| Docker puede evitar reglas UFW de entrada en puertos publicados | Publicar app solo en 127.0.0.1:8080 y no publicar la BD | PENDIENTE | PENDIENTE: UFW, puertos Compose y TCP desde Windows |
| El seeder general falla por duplicado de Sembrado en PostgreSQL | Ejecutar solo seeders específicos, sin DatosPruebaSeeder | PENDIENTE | PENDIENTE: repetir pasos de esta guía y registrar resultados |
| Los usuarios demo tienen contraseña conocida | Cambiar contraseña del admin y desactivar las cuentas iniciales antes de publicar en esta BD de laboratorio | PENDIENTE | PENDIENTE: login nuevo y rechazo de cuentas inactivas |
| Flutter toma API_BASE_URL por dart-define; Android debug ya permite HTTP | Compilar debug con http://VM_IP/api | PENDIENTE | PENDIENTE: conexión, login, perfil y logs correlacionados |
| Backup no probado no acredita recuperación | Dump, restauración en BD nueva, marcador/conteos y lectura desde Laravel | PENDIENTE | PENDIENTE: archivos, hashes y consultas reales |
| Incidente reproducible sin borrar datos | Detener BD, observar fallo, diagnosticar logs y volver a iniciar | PENDIENTE | PENDIENTE: hora, causa y recuperación |

## Registro propio de consultas durante la instalación

Antes de ejecutar un comando nuevo sugerido por IA, pide:

> Explica qué hace este comando, qué archivos o datos modifica, qué privilegios
> requiere, qué resultado debo esperar y cómo puedo verificarlo.

Si un bloque contiene varias operaciones, entiende cada una. No ejecutes scripts
largos como root sin revisarlos. Las tablas de README proporcionan esa explicación
para sus bloques; anota tus decisiones y cualquier cambio que hayas necesitado.

| Fecha/hora | Pregunta o comando consultado sin secretos | Explicación recibida: efecto, archivos, privilegios | Qué acepté | Qué corregí o rechacé y por qué | Cómo lo verifiqué | Evidencia |
| --- | --- | --- | --- | --- | --- | --- |
| PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE | PENDIENTE |

## Comprobación de comprensión

Cada integrante debe poder responder con sus palabras:

1. ¿Qué diferencia hay entre la IP de Windows, la de Ubuntu y el loopback del móvil?
2. ¿Por qué Nginx puede llegar a 8080 y otro dispositivo no debería poder hacerlo?
3. ¿Cómo llega Laravel a `db` si PostgreSQL no tiene un puerto público?
4. ¿Qué diferencia existe entre `infraadmin`, `observador`, `www-data`, el rol SQL
   `agrofusion_app` y una cuenta de usuario Laravel?
5. ¿Qué datos se conservan al recrear el contenedor y cuáles dependen del backup?
6. ¿Por qué `/api/test-api` no demuestra por sí solo que PostgreSQL esté disponible?
7. ¿Qué hace `unless-stopped` y qué ocurre después de un `docker compose stop`?
8. ¿Qué contiene un dump, qué no contiene y cómo comprobaste que se restauró?
9. ¿Qué indicaba el log durante el incidente y qué prueba confirmó su solución?
10. ¿Qué cambiaste de la propuesta de IA y con qué evidencia lo justificas?
