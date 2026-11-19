<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recepcion_qr_envio', function (Blueprint $table) {
            // Los códigos anteriores permanecen intactos, con clave_operacion nula.
            $table->dropUnique(['rutadistribucionid']);
            $table->string('clave_operacion')->nullable()->unique();
            $table->text('token_cifrado')->nullable();
            $table->unsignedBigInteger('destinatario_usuarioid')->nullable();
            $table->foreign('destinatario_usuarioid')->references('usuarioid')->on('usuario')->restrictOnDelete();
            $table->timestamp('utilizado_en')->nullable();
            $table->string('firma_path')->nullable();
            $table->json('datos_recepcion')->nullable();
            $table->index(['rutadistribucionid', 'destinatario_usuarioid'], 'recepcion_qr_destino_idx');
        });
    }

    public function down(): void
    {
        throw new RuntimeException('Las recepciones y firmas deben conservarse. Prepare una reversión manual con respaldo.');
    }
};
