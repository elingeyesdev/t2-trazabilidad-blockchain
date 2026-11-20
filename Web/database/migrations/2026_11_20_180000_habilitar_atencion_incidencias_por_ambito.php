<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('roles') || ! Schema::hasTable('permissions')) {
            return;
        }

        // Add only the approved permissions to existing roles. Never resync admin or users.
        $permisos = ['incidentes.view', 'incidentes.update', 'incidentes.resolve'];
        foreach ($permisos as $nombre) {
            Permission::firstOrCreate(['name' => $nombre, 'guard_name' => 'web']);
        }
        foreach (Role::where('guard_name', 'web')->whereIn('name', ['jefe_agricultor', 'jefe_planta', 'mayorista', 'jefe_mayorista'])->get() as $rol) {
            $rol->givePermissionTo($permisos);
        }
        app(PermissionRegistrar::class)->forgetCachedPermissions();
    }

    public function down(): void
    {
        // Do not revoke permissions that could have existed before this additive migration.
    }
};
