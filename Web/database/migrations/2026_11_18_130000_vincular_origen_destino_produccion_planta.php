<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('lote_produccion_materia_prima', function (Blueprint $table) {
            $table->unsignedBigInteger('almacen_movimientoid')->nullable();
            $table->foreign('almacen_movimientoid', 'lp_materia_movimiento_fk')->references('almacen_movimientoid')->on('almacen_movimiento')->restrictOnDelete();
        });
        Schema::table('almacenaje_lote_produccion', function (Blueprint $table) {
            $table->unsignedBigInteger('insumoid')->nullable();
            $table->unsignedBigInteger('insumo_presentacionid')->nullable();
            $table->unsignedBigInteger('inventario_presentacion_loteid')->nullable();
            $table->json('datos_ingreso')->nullable();
            $table->foreign('insumoid', 'alm_produccion_insumo_fk')->references('insumoid')->on('insumo')->restrictOnDelete();
            $table->foreign('insumo_presentacionid', 'alm_produccion_presentacion_fk')->references('insumo_presentacionid')->on('insumo_presentacion')->restrictOnDelete();
            $table->foreign('inventario_presentacion_loteid', 'alm_produccion_partida_fk')->references('inventario_presentacion_loteid')->on('inventario_presentacion_lote')->restrictOnDelete();
        });
    }

    public function down(): void
    {
        throw new RuntimeException('Las referencias de trazabilidad requieren una reversión manual que preserve los ingresos registrados.');
    }
};
