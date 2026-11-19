<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $columnasDecimales = ['insumo' => ['stock', 'stockminimo'], 'materia_prima_lote' => ['cantidad', 'cantidad_disponible'], 'almacen_movimiento' => ['cantidad'], 'inventario_presentacion_lote' => ['cantidad_unidades', 'cantidad_kg'], 'lote_produccion_materia_prima' => ['cantidad_planificada', 'cantidad_usada']];
        // Comprobar todos los datos antes de efectuar cambios de esquema.
        foreach ($columnasDecimales as $tabla => $columnas) {
            foreach ($columnas as $columna) {
                if (DB::getDriverName() === 'pgsql' && DB::table($tabla)->whereRaw(
                    "$columna < 0 OR $columna >= 1000000000000 OR ABS(CAST($columna AS NUMERIC) - ROUND(CAST($columna AS NUMERIC), 6)) > 0.00000001"
                )->exists()) {
                    throw new RuntimeException("Revise $tabla.$columna: existen cantidades incompatibles con decimal(18,6).");
                }
            }
        }
        // No inferir almacenes, proveedores ni fechas de las partidas históricas.
        $this->nuevaColumna('materia_prima_lote', 'insumoid', fn ($table) => $table->foreignId('insumoid')->nullable()->constrained('insumo', 'insumoid')->restrictOnDelete());
        $this->nuevaColumna('materia_prima_lote', 'almacenid', fn ($table) => $table->foreignId('almacenid')->nullable()->constrained('almacen', 'almacenid')->restrictOnDelete());
        Schema::table('materia_prima_lote', function (Blueprint $table) {
            $columnas = collect(Schema::getColumns('materia_prima_lote'))->keyBy('name');
            foreach (['materiaprimabaseid', 'proveedor_actorid'] as $columna) {
                if (! $columnas[$columna]['nullable']) {
                    $table->unsignedBigInteger($columna)->nullable()->change();
                }
            }
            if (! Schema::hasIndex('materia_prima_lote', 'partida_existencia_almacen_idx')) {
                $table->index(['almacenid', 'insumoid'], 'partida_existencia_almacen_idx');
            }
        });
        $this->nuevaColumna('inventario_presentacion_lote', 'fecha_vencimiento', fn ($table) => $table->date('fecha_vencimiento')->nullable());
        $this->nuevaColumna('lote_produccion_materia_prima', 'inventario_presentacion_loteid', fn ($table) => $table->foreignId('inventario_presentacion_loteid')->nullable()->constrained('inventario_presentacion_lote', 'inventario_presentacion_loteid')->restrictOnDelete());
        $this->nuevaColumna('lote_produccion_materia_prima', 'cantidad_unidades_consumidas', fn ($table) => (DB::getDriverName() === 'sqlite' ? $table->string('cantidad_unidades_consumidas', 32) : $table->decimal('cantidad_unidades_consumidas', 18, 6))->nullable());
        foreach ($columnasDecimales as $tabla => $columnas) {
            foreach ($columnas as $columna) {
                if (DB::getDriverName() === 'sqlite' && in_array(Schema::getColumnType($tabla, $columna), ['varchar', 'text'], true)) {
                    continue;
                }
                Schema::table($tabla, function (Blueprint $table) use ($columna) {
                    $column = DB::getDriverName() === 'sqlite' ? $table->string($columna, 32) : $table->decimal($columna, 18, 6);
                    if ($columna === 'stockminimo') {
                        $column->nullable()->default(null);
                    } elseif ($columna === 'stock') {
                        $column->default(0);
                    }
                    $column->change();
                });
            }
        }
        foreach (['materiaprimaloteid' => ['materia_prima_lote', 'materiaprimaloteid'],
            'inventario_presentacion_loteid' => ['inventario_presentacion_lote', 'inventario_presentacion_loteid'],
            'unidadmedidaid' => ['unidadmedida', 'unidadmedidaid']] as $columna => [$tablaReferencia, $clave]) {
            $this->nuevaColumna('almacen_movimiento', $columna, fn ($table) => $table->foreignId($columna)->nullable()->constrained($tablaReferencia, $clave)->restrictOnDelete());
        }
        foreach (['saldo_anterior', 'saldo_posterior'] as $saldo) {
            $this->nuevaColumna('almacen_movimiento', $saldo, fn ($table) => (DB::getDriverName() === 'sqlite' ? $table->string($saldo, 32) : $table->decimal($saldo, 18, 6))->nullable());
        }
    }

    private function nuevaColumna(string $tabla, string $columna, Closure $definir): void
    {
        if (! Schema::hasColumn($tabla, $columna)) {
            Schema::table($tabla, $definir);
        }
    }

    public function down(): void
    {
        // Conservar trazabilidad y precisión confirmadas; una reversión no debe borrar auditoría.
    }
};
