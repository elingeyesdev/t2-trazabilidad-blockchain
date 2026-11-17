<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Existing floats cannot guarantee exact inventory arithmetic. Keep six decimals
        // (movements already use three), and stop rather than silently round legacy data.
        foreach (['insumo' => 'stock', 'loteinsumo' => 'cantidadusada'] as $table => $column) {
            if (DB::getDriverName() === 'pgsql') {
                $incompatible = DB::table($table)->whereRaw(
                    "$column < 0 OR $column >= 1000000000000 OR ABS(CAST($column AS NUMERIC) - ROUND(CAST($column AS NUMERIC), 6)) > 0.00000001"
                )->exists();
                if ($incompatible) {
                    throw new RuntimeException("Revise la precisión de $table.$column antes de aplicar la migración decimal; no se modificaron esos datos.");
                }
            }
        }
        Schema::table('insumo', fn (Blueprint $table) => $table->decimal('stock', 18, 6)->change());
        Schema::table('loteinsumo', fn (Blueprint $table) => $table->decimal('cantidadusada', 18, 6)->change());
    }

    public function down(): void
    {
        // Deliberately retain decimal precision: rolling back must not lose confirmed stock.
    }
};
