<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('evidencia_publicacion', function (Blueprint $table) {
            $table->bigIncrements('evidenciapublicacionid');
            $table->foreignId('actividadid')->constrained('actividad', 'actividadid')->restrictOnDelete();
            $table->foreignId('loteproduccionpedidoid')->nullable()->constrained('lote_produccion_pedido', 'loteproduccionpedidoid')->restrictOnDelete();
            $table->foreignId('solicitadopor_usuarioid')->nullable()->constrained('usuario', 'usuarioid')->nullOnDelete();
            $table->string('estado', 30)->default('solicitada')->index();
            $table->string('origen_sha256', 64);
            $table->uuid('token_publico')->unique();
            $table->string('archivo_sanitizado')->nullable();
            $table->timestamp('aprobado_en')->nullable();
            $table->timestamp('retirado_en')->nullable();
            $table->timestamps();
        });
        Schema::create('evidencia_publicacion_evento', function (Blueprint $table) {
            $table->bigIncrements('evidenciapublicacioneventoid');
            $table->foreignId('evidenciapublicacionid')->constrained('evidencia_publicacion', 'evidenciapublicacionid')->restrictOnDelete();
            $table->foreignId('usuarioid')->nullable()->constrained('usuario', 'usuarioid')->nullOnDelete();
            $table->string('accion', 40);
            $table->text('motivo');
            $table->timestamp('fecha');
        });

        Permission::firstOrCreate(['name' => 'evidencias.publicar', 'guard_name' => 'web']);
        // Explicitly approved governance permission, without synchronizing any role's other permissions.
        foreach (Role::where('guard_name', 'web')->whereIn('name', \App\Support\UsuarioRol::nombresRolAdmin())->get() as $rol) {
            $rol->givePermissionTo('evidencias.publicar');
        }
        app(PermissionRegistrar::class)->forgetCachedPermissions();
    }

    public function down(): void
    {
        Schema::dropIfExists('evidencia_publicacion_evento');
        Schema::dropIfExists('evidencia_publicacion');
        // Preserve explicit permission grants; rollback must not revoke unrelated manual grants.
    }
};
