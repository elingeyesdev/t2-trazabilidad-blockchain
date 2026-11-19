<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('envio_asignacion_multiple', function (Blueprint $table) {
            $table->json('recepcion_planta_datos')->nullable();
        });
        Schema::table('materia_prima_lote', function (Blueprint $table) {
            $table->foreignId('detallepedidoid')->nullable()->constrained('detallepedido', 'detallepedidoid')->restrictOnDelete();
        });
    }

    public function down(): void
    {
        // Conservar vínculos y comprobantes de operaciones confirmadas.
    }
};
