<?php

namespace Tests\Unit;

use App\Support\LoteTrazabilidadService;
use Illuminate\Support\Collection;
use ReflectionClass;
use Tests\TestCase;

class LoteTrazabilidadHistorialOrdenTest extends TestCase
{
    public function test_orden_historial_respeta_ciclo_del_lote(): void
    {
        $svc = app(LoteTrazabilidadService::class);
        $ref = new ReflectionClass($svc);
        $numerar = $ref->getMethod('numerarYOrdenarEventosHistorial');
        $numerar->setAccessible(true);

        /** @var Collection<int, array<string, mixed>> $eventos */
        $eventos = collect([
            $this->eventoPrueba('2026-06-24 20:26:00', 'certificacion', 'certificacion', 'Certificación de lote'),
            $this->eventoPrueba('2026-06-24 20:26:00', 'cosecha', 'cosecha', 'Cosechado'),
            $this->eventoPrueba('2026-06-24 19:30:00', 'actividad', 'en_crecimiento', 'Fertilización', 3),
            $this->eventoPrueba('2026-06-24 12:38:00', 'actividad', 'en_crecimiento', 'Control de plagas', 1),
            $this->eventoPrueba('2026-06-24 12:09:00', 'siembra', 'siembra', 'Siembra de Cebolla'),
            $this->eventoPrueba('2026-06-24 14:00:00', 'actividad', 'preparacion', 'Preparación del terreno', 2),
            $this->eventoPrueba('2026-06-24 11:56:00', 'estado', 'preparacion', 'En planificación'),
        ]);

        /** @var Collection<int, array<string, mixed>> $ordenados */
        $ordenados = $numerar->invoke($svc, $eventos);
        $titulos = $ordenados->pluck('titulo')->values()->all();
        $pasos = $ordenados->pluck('paso')->values()->all();

        $this->assertSame([
            'En planificación',
            'Preparación del terreno',
            'Siembra de Cebolla',
            'Control de plagas',
            'Fertilización',
            'Cosechado',
            'Certificación de lote',
        ], $titulos);

        $this->assertSame([1, 2, 3, 4, 5, 6, 7], $pasos);
    }

    public function test_historial_misma_etapa_usa_creacion_y_desempata_por_id(): void
    {
        $svc = app(LoteTrazabilidadService::class);
        $numerar = (new ReflectionClass($svc))->getMethod('numerarYOrdenarEventosHistorial');
        $eventos = collect([
            $this->eventoPrueba('2026-06-24 13:00:00', 'actividad', 'en_crecimiento', 'Riego', 9)
                + ['fecha_creacion' => '2026-06-24 13:00:00'],
            $this->eventoPrueba('2026-06-24 14:00:00', 'actividad', 'en_crecimiento', 'Riego', 3)
                + ['fecha_creacion' => '2026-06-24 12:00:00'],
            $this->eventoPrueba('2026-06-26 18:00:00', 'actividad', 'en_crecimiento', 'Riego', 1)
                + ['fecha_creacion' => '2026-06-24 12:00:00'],
        ]);

        $ordenados = $numerar->invoke($svc, $eventos);

        $this->assertSame([1, 3, 9], $ordenados->pluck('actividadid')->all());
        $this->assertSame([1, 2, 3], $ordenados->pluck('paso')->all());
    }

    /**
     * @return array<string, mixed>
     */
    private function eventoPrueba(
        string $fecha,
        string $tipo,
        string $fase,
        string $titulo,
        ?int $actividadid = null,
    ): array {
        return [
            'fecha' => $fecha,
            'fecha_fmt' => $fecha,
            'tipo' => $tipo,
            'fase' => $fase,
            'titulo' => $titulo,
            'descripcion' => '',
            'actividadid' => $actividadid,
        ];
    }
}
