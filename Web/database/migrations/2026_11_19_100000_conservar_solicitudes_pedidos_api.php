<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('pedido', function (Blueprint $t) {
            $t->unsignedBigInteger('creado_por_usuarioid')->nullable()->index();
        });
        foreach (['pedido', 'pedido_distribucion'] as $tabla) {
            Schema::table($tabla, function (Blueprint $t) use ($tabla) {
                $t->uuid('solicitud_id')->nullable();
                $t->char('solicitud_huella', 64)->nullable();
                $t->unique(['creado_por_usuarioid', 'solicitud_id'], $tabla.'_solicitud_unica');
            });
        }
        foreach (['detallepedido', 'detalle_pedido_distribucion'] as $tabla) {
            Schema::table($tabla, function (Blueprint $t) {
                // Misma estrategia exacta de cosechas/inventario: SQLite necesita TEXT.
                if (DB::getDriverName() === 'sqlite') {
                    $t->string('cantidad', 20)->change();
                } else {
                    $t->decimal('cantidad', 18, 6)->change();
                }
                $t->json('datos_solicitud')->nullable();
            });
        }
        Schema::table('detallepedido', function (Blueprint $t) {
            $t->unsignedBigInteger('materiaprimaloteid')->nullable();
            $t->foreign('materiaprimaloteid', 'detallepedido_partida_origen_fk')->references('materiaprimaloteid')->on('materia_prima_lote')->restrictOnDelete();
        });
    }

    public function down(): void
    {
        throw new RuntimeException('La reversión debe preservar manualmente cantidades, autoría y solicitudes registradas.');
    }
};
