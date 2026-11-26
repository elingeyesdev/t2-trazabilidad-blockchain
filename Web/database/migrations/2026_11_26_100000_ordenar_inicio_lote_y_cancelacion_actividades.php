<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('lote', function (Blueprint $table) {
            // Null conserva la situación histórica: no presume preparación realizada.
            $table->boolean('preparacion_requerida')->nullable();
            $table->foreignId('agricultor_inicial_usuarioid')->nullable()->constrained('usuario', 'usuarioid');
            $table->uuid('solicitud_registro_id')->nullable()->unique();
            $table->string('solicitud_registro_huella', 64)->nullable();
        });
        Schema::table('actividad', function (Blueprint $table) {
            $table->timestamp('cancelada_en')->nullable();
            $table->foreignId('cancelada_por_usuarioid')->nullable()->constrained('usuario', 'usuarioid');
            $table->string('motivo_cancelacion', 500)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('actividad', function (Blueprint $table) {
            $table->dropForeign(['cancelada_por_usuarioid']);
            $table->dropColumn(['cancelada_en', 'cancelada_por_usuarioid', 'motivo_cancelacion']);
        });
        Schema::table('lote', function (Blueprint $table) {
            $table->dropForeign(['agricultor_inicial_usuarioid']);
            $table->dropUnique(['solicitud_registro_id']);
            $table->dropColumn(['preparacion_requerida', 'agricultor_inicial_usuarioid', 'solicitud_registro_id', 'solicitud_registro_huella']);
        });
    }
};
