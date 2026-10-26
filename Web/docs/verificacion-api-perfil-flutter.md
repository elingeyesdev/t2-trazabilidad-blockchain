# Verificación de la API de perfil para Flutter

Este registro permite al equipo revisar y reproducir la comprobación final de
la issue #2, **[EDT 1.1] Adaptar API Laravel de perfil y permisos para Flutter**.
El comportamiento de los endpoints y sus campos está descrito en el
[contrato de perfil para Flutter](api-perfil-flutter.md).

## Entorno de ejecución

La comprobación local se realizó el 25 de octubre de 2026 con estas condiciones:

| Elemento | Configuración |
| --- | --- |
| Sistema | Windows y PowerShell. |
| PHP | 8.3.33, con `pdo_sqlite`, `fileinfo` y `gd`. |
| Laravel | 12.40.2. |
| Entorno | `testing`, con clave de aplicación configurada. |
| Base de datos | SQLite `:memory:`, según `phpunit.xml`. |
| Sesión y caché | Controlador `array`. |
| Correo y colas | Correo `array` y cola `sync`. |
| Fotografías | Disco `public` simulado mediante `Storage::fake('public')`. |

Las pruebas de perfil crean sus usuarios, roles, permisos, tokens y archivos.
Las peticiones API pasan por las rutas y el kernel HTTP de Laravel, con tokens
reales de Sanctum emitidos para los usuarios de prueba.

## Resultados

La ejecución final de la suite completa terminó correctamente:

```text
Tests:    1 skipped, 380 passed (4344 assertions)
Duration: 62.74s
```

La prueba omitida es
`ReporteCentroFiltrosRealDbTest::test_reportes_con_filtros_en_bd_real`.
Su condición de ejecución exige una base SQLite persistente y la omite cuando
la base es `:memory:`. El resto de la suite, incluidos perfil, permisos y
funcionalidades web, pasó en este entorno.

La prueba del flujo completo también se ejecutó por separado: **1 prueba
aprobada, 29 aserciones**. La comprobación con Laravel Pint aprobó los once
archivos PHP nuevos o reorganizados de la issue.

## Casos autorizados y denegados

Las siguientes pruebas cubren las reglas del perfil:

| Área | Casos comprobados | Evidencia automatizada |
| --- | --- | --- |
| Consulta autenticada | Devuelve al usuario del token, sus roles, permisos directos y de roles sin duplicados, y capacidades de edición. | `ApiPerfilConsultaTest`. |
| Identidad y datos privados | Un parámetro con otro `usuarioid` no selecciona otro perfil; la respuesta excluye contraseña, tokens y datos internos. | `ApiPerfilConsultaTest`. |
| Credenciales | Sin token o con token inválido, revocado o vencido, la consulta responde 401. | `ApiPerfilConsultaTest`. |
| Estado de cuenta | Cuentas desactivadas o pendientes después de emitir el token reciben 403 al consultar o editar. | `ApiPerfilConsultaTest` y `ApiPerfilActualizacionTest`. |
| Edición propia | Una cuenta sin permisos administrativos cambia su nombre una vez; el mismo nombre no consume el cambio y un segundo valor recibe 403. | `ApiPerfilActualizacionTest`. |
| Campos protegidos | Se rechazan identidad ajena, roles, permisos, correo, contraseña, estado y rutas de imagen enviados en la edición. El perfil permanece sin cambios. | `ApiPerfilActualizacionTest`. |
| Validación | Nombres vacíos, duplicados, demasiado largos, de tipo incorrecto o con caracteres inválidos reciben 422. También se rechaza un envío vacío. | `ApiPerfilActualizacionTest`. |
| Fotografías | Acepta una foto independiente mediante `POST` con `_method=PATCH`; permite reemplazarla después del cambio de nombre y elimina la anterior. | `ApiPerfilActualizacionTest`. |
| Archivos rechazados | Un archivo que no es una imagen o una imagen mayor de 2048 KB recibe 422; un segundo nombre junto a una foto recibe 403 y no guarda el archivo. | `ApiPerfilActualizacionTest`. |
| Fallos de guardado | Si falla la escritura de la imagen o la transacción, conserva la foto y el perfil anteriores y limpia la imagen nueva cuando corresponde. | `ApiPerfilActualizacionTest`. |
| Recorrido de sesión | Login → consulta → nombre → foto → nueva consulta → logout. Tras logout, el mismo token recibe 401 en consulta y edición. | `ApiPerfilFlujoTest`. |
| Compatibilidad web | Conserva redirección y mensaje de éxito, validación del formulario y carga de fotos; un nombre ya bloqueado se sigue ignorando en la web. | `PerfilWebActualizacionTest` y la prueba de perfil de `SolicitudUsuarioTest`. |
| Permisos de módulos | Conserva los controles existentes de acceso, la matriz de permisos y el barrido de rutas protegidas. | `ApiAccessTest`, `PermissionMatrixAlineacionTest` y `SeguridadBaseRbacTest`, dentro de la suite completa. |

## Reproducir las comprobaciones

Necesitas las dependencias de Composer instaladas, las extensiones requeridas
por `composer.json` y una clave de aplicación válida para el entorno de pruebas.
`phpunit.xml` configura SQLite en memoria y los controladores de prueba.

1. Desde la raíz del repositorio, entra en Laravel:

   ```powershell
   Set-Location Web
   ```

2. Ejecuta el recorrido completo del perfil:

   ```powershell
   php artisan test --without-tty --filter=ApiPerfilFlujoTest --no-ansi
   ```

   Confirma **1 prueba aprobada y 29 aserciones**.

3. Ejecuta la suite completa:

   ```powershell
   php artisan test --without-tty --no-ansi
   ```

   Confirma la salida final sin fallos. Para la revisión registrada, el
   resultado es **380 pruebas aprobadas, una omitida y 4344 aserciones**.
   El número puede variar si se incorporan otras pruebas al proyecto.

El workflow [Tests de GitHub Actions](../../.github/workflows/tests.yml)
configura la suite para PHP 8.2, 8.3 y 8.4 cuando se abre un pull request.
La ejecución registrada en este documento corresponde a PHP 8.3.33 y SQLite;
los resultados de las otras versiones se revisan en el pull request.

## Relación con los criterios de aceptación

Las comprobaciones aportan la siguiente evidencia para revisar la issue:

| Criterio | Evidencia |
| --- | --- |
| Consultar el perfil autenticado. | Consulta con un token de Sanctum válido y rechazo de credenciales no válidas. |
| Editar nombre y foto según las restricciones. | Cambio de nombre único, carga y reemplazo de foto, estados de cuenta y validación de archivos. |
| Entregar datos y permisos necesarios para Flutter. | Recurso JSON explícito, unión de permisos y capacidades de perfil; contrato documentado. |
| Impedir modificaciones sin autorización. | Rechazo de campos protegidos, cuentas no autorizadas, segundo nombre y token revocado. |
| Conservar las funcionalidades web existentes. | Pruebas específicas del perfil web y suite completa aprobadas. |

Puedes revisar las pruebas de perfil en estos archivos:

- [Consulta de perfil y permisos](../tests/Feature/ApiPerfilConsultaTest.php).
- [Actualización y restricciones de acceso](../tests/Feature/ApiPerfilActualizacionTest.php).
- [Flujo completo con login y revocación](../tests/Feature/ApiPerfilFlujoTest.php).
- [Compatibilidad del formulario web](../tests/Feature/PerfilWebActualizacionTest.php).
- [Regla existente de cambio de nombre en la web](../tests/Feature/SolicitudUsuarioTest.php).
