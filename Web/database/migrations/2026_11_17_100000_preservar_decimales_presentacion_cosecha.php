<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            foreach (['cantidad', 'cantidad_base'] as $columna) {
                if (DB::table('produccion')->whereRaw("$columna < 0 OR $columna >= 1000000000000 OR ABS(CAST($columna AS NUMERIC) - ROUND(CAST($columna AS NUMERIC), 6)) > 0.00000001")->exists()) {
                    throw new RuntimeException("Revise produccion.$columna antes de migrar: hay cantidades fuera del rango o precisión decimal. No se sustituirán silenciosamente.");
                }
            }
        }
        Schema::table('produccion', function (Blueprint $table) {
            // SQLite NUMERIC affinity stores long decimals as binary floats. TEXT keeps the
            // exact same canonical strings as PostgreSQL NUMERIC(18,6) in local/test databases.
            if (DB::getDriverName() === 'sqlite') {
                $table->string('cantidad', 20)->change();
                $table->string('cantidad_base', 20)->nullable()->change();
            } else {
                $table->decimal('cantidad', 18, 6)->change();
                $table->decimal('cantidad_base', 18, 6)->nullable()->change();
            }
            if (! Schema::hasColumn('produccion', 'presentacion_cosecha')) {
                $table->json('presentacion_cosecha')->nullable();
            }
        });
        // Legacy snapshots remain NULL: today's factor is not evidence of the original one.
    }

    public function down(): void
    {
        // Retain exact quantities and historical snapshots, as with the inventory migration.
    }
};
