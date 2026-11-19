<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pedido_decision', function (Blueprint $table) {
            $table->id('pedidodecisionid');
            $table->unsignedBigInteger('pedidoid')->nullable();
            $table->unsignedBigInteger('pedidodistribucionid')->nullable();
            $table->unsignedBigInteger('usuarioid');
            $table->unsignedInteger('secuencia');
            $table->string('accion', 20);
            $table->string('estado_anterior', 40);
            $table->string('estado_resultante', 40);
            $table->string('motivo', 500)->nullable();
            $table->timestamp('fecha');
            $table->foreign('pedidoid')->references('pedidoid')->on('pedido')->restrictOnDelete();
            $table->foreign('pedidodistribucionid')->references('pedidodistribucionid')->on('pedido_distribucion')->restrictOnDelete();
            $table->foreign('usuarioid')->references('usuarioid')->on('usuario')->restrictOnDelete();
            $table->unique(['pedidoid', 'secuencia']);
            $table->unique(['pedidodistribucionid', 'secuencia']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pedido_decision');
    }
};
