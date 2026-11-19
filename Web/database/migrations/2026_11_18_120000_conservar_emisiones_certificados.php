<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        foreach (['certificacion_lote' => 'usuarioid', 'evaluacion_final_lote_produccion' => 'inspector_usuarioid'] as $nombre => $emisor) {
            Schema::table($nombre, function (Blueprint $table) use ($nombre, $emisor) {
                $table->char('emision_uuid', 26)->nullable()->unique();
                $table->uuid('solicitud_id')->nullable();
                $table->char('solicitud_huella', 64)->nullable();
                $table->json('datos_emision')->nullable();
                $table->string('archivo_path')->nullable();
                $table->unsignedSmallInteger('formato_version')->nullable();
                $table->unique([$emisor, 'solicitud_id'], $nombre.'_solicitud_unique');
                if ($nombre === 'evaluacion_final_lote_produccion') {
                    $table->string('codigo_certificado', 60)->nullable()->unique();
                }
            });
        }
        foreach ([['certificacion_lote', 'loteid', 'lote', 'loteid'],
            ['evaluacion_final_lote_produccion', 'loteproduccionpedidoid', 'lote_produccion_pedido', 'loteproduccionpedidoid'],
            ['evaluacion_final_lote_produccion', 'inspector_usuarioid', 'usuario', 'usuarioid']] as [$nombre, $columna, $padre, $clave]) {
            Schema::table($nombre, function (Blueprint $table) use ($columna, $padre, $clave) {
                $table->dropForeign([$columna]);
                $table->foreign($columna)->references($clave)->on($padre)->restrictOnDelete();
            });
        }
    }

    public function down(): void
    {
        throw new RuntimeException('Esta migración conserva antecedentes emitidos y requiere una reversión manual que preserve sus datos y documentos.');
    }
};
