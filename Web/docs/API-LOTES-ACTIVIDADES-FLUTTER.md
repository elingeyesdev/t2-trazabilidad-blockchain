# Contrato API: lotes y actividades

La API usa Laravel Sanctum con token Bearer. Las lecturas requieren `lotes.view` (`action.permission:lotes,read`) y además aplican los alcances existentes de `LoteAcceso` y `ActividadPermisos`. No se debe enviar un `usuarioid` para decidir permisos: el servidor los obtiene del usuario autenticado.

## Endpoints

| Método y ruta | Respuesta |
| --- | --- |
| `GET /api/lotes` | Lotes visibles, paginados. |
| `GET /api/lotes/{lote}` | Detalle del lote, actividades visibles e historial de trazabilidad. |
| `GET /api/lotes/{lote}/actividades` | Actividades visibles dentro del lote; paginado. |
| `GET /api/lotes/{lote}/actividades/{actividad}` | Detalle de una actividad que pertenece al lote y es visible. |
| `GET /api/actividades` | Actividades visibles para el usuario; paginado. |
| `GET /api/actividades/{actividad}` | Detalle de una actividad visible. |
| `GET /api/historial-estados-lote` | Cambios de estado de lotes visibles; paginado. |
| `GET /api/historial-estados-lote/{historial}` | Cambio de estado perteneciente a un lote visible. |

Los recursos inexistentes o fuera del alcance responden `404`; la falta de autenticación responde `401`, permisos de módulo insuficientes `403` y filtros inválidos `422`.

## Paginación y filtros

Las colecciones usan el envelope estándar del paginador Laravel: `{ "data": [...], "links": {...}, "meta": {...} }`. El tamaño por defecto es 15 y `per_page` acepta de 1 a 100. Seguir `links.next` hasta `null` para cargar todas las páginas; no asumir que la primera página contiene todos los lotes o actividades.

`GET /api/lotes`: filtros opcionales `q`, `insumosemillaid`, `cultivoid`, `estadolotetipoid`, `usuarioid`; orden permitido: `loteid`, `nombre`, `superficie`, `fechasiembra`, `fechacreacion`, `fechamodificacion`.

`GET /api/actividades` y la ruta anidada: filtros opcionales `q`, `estado` (`pendiente` o `completada`), `loteid` (solo en la ruta no anidada) y `tipoactividadid`; orden permitido: `actividadid`, `descripcion`, `fechainicio`, `fecha_planificada`, `fechafin`.

`GET /api/historial-estados-lote`: filtros opcionales `loteid`, `estadolotetipoid`, `fecha_desde`, `fecha_hasta`; orden permitido: `historial_estado_id`, `loteid`, `fecha_cambio`.

Todos los listados aceptan `page`, `per_page`, `sort` y `direction` (`asc` o `desc`). Un filtro válido que no coincide devuelve `data: []`; relaciones opcionales sin valor devuelven `null`, y colecciones sin registros devuelven `[]`.

## Campos y significado

- Lote: `loteid`, `nombre`, `ubicacion`, `superficie`, `cultivoid`, `cultivo`, `cultivo_etiqueta`, `estadolotetipoid`, `estado_tipo`, `usuario` (responsable), `fechasiembra`, `fechacreacion`, `fechamodificacion`, coordenadas y código de trazabilidad. `cultivo_etiqueta` conserva la resolución web: nombre de la semilla registrada si existe; en caso contrario, nombre del cultivo.
- Actividad: `actividadid`, `loteid`, `descripcion`, `tipo_actividad`, `prioridad`, `usuario`/`responsable`, `ejecutor`, `fechainicio`, `fecha_planificada`, `fechafin`, `pendiente`, `completada` y `estado_tarea`. Pendiente significa exclusivamente `fechafin IS NULL`, igual que el listado web. `fecha_planificada` es la fecha planificada; `fechainicio` y `fechafin` son datos de ejecución.
- `historial` del detalle de lote proviene de `LoteTrazabilidadService::buildEventos()`, la misma fuente de la trazabilidad web. Puede contener cambios de estado y otros eventos reales de la línea de tiempo; no se deriva de `fechamodificacion`.
- Las actividades incluyen `evidencia_foto_path` como ruta relativa del disco público para compatibilidad con Flutter, `evidencia_foto_url` (URL pública derivada por el helper web) y `tiene_evidencia`. Nunca se serializa una ruta absoluta del servidor. El detalle tampoco incluye `passwordhash` ni `detalle_json`.

## Fechas

Las fechas sin hora (`fechasiembra`, `fecha_planificada`) se serializan como `YYYY-MM-DD`. Las fechas con hora de los modelos se serializan en ISO-8601 UTC. En los eventos de `historial`, `fecha_iso` usa la zona `APP_TIMEZONE` configurada en la aplicación; `fecha_fmt` es solo presentación y no debe usarse para ordenar.

## Ejemplo de respuesta

```json
{
  "data": {
    "loteid": 27,
    "nombre": "Lote Norte",
    "cultivo_etiqueta": "Papa",
    "estado_tipo": { "estadolotetipoid": 3, "nombre": "En crecimiento" },
    "usuario": { "usuarioid": 8, "nombre": "Ana", "apellido": "Rojas" },
    "actividades": [
      {
        "actividadid": 91,
        "fechainicio": "2026-08-03T08:15:00.000000Z",
        "fecha_planificada": "2026-08-04",
        "fechafin": null,
        "pendiente": true,
        "estado_tarea": "pendiente"
      }
    ],
    "actividades_pendientes": 1,
    "historial": []
  }
}
```

La app móvil del repositorio ya acepta listas directas o `data`, pero debe seguir `links.next` para recorrer la paginación. Esta documentación describe el contrato backend; no constituye una verificación end-to-end de Flutter.