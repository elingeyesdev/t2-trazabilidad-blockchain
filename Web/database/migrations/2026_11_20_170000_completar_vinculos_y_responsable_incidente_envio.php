<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('incidente_envio', function (Blueprint $table) {
            $table->string('afectado_tipo', 30)->nullable()->index();
            $table->foreignId('envioasignacionmultipleid')->nullable()->constrained('envio_asignacion_multiple', 'envioasignacionmultipleid')->nullOnDelete();
            $table->foreignId('pedidodistribucionid')->nullable()->constrained('pedido_distribucion', 'pedidodistribucionid')->nullOnDelete();
            $table->foreignId('rutadistribucionid')->nullable()->constrained('ruta_distribucion', 'rutadistribucionid')->nullOnDelete();
            $table->foreignId('responsable_usuarioid')->nullable()->constrained('usuario', 'usuarioid')->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('incidente_envio', function (Blueprint $table) {
            foreach (['envioasignacionmultipleid', 'pedidodistribucionid', 'rutadistribucionid', 'responsable_usuarioid'] as $columna) {
                $table->dropConstrainedForeignId($columna);
            }
            $table->dropColumn('afectado_tipo');
        });
    }
};
