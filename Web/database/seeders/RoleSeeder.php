<?php

namespace Database\Seeders;

use App\Models\Usuario;
use Illuminate\Database\Seeder;
use Spatie\Permission\Models\Role;

class RoleSeeder extends Seeder
{
    public const ROLES_CANONICOS = [
        'admin',
        'jefe_agricultor',
        'agricultor',
        'jefe_planta',
        'planta',
        'jefe_mayorista',
        'mayorista',
        'minorista',
        'transportista',
    ];

    public const ROLES_LEGACY = [
        'operador',
        'almacen',
        'Operador',
        'Almacen',
        'Admin',
        'Agricultor',
        'admin_agricola',
        'admin_planta',
    ];

    public function run(): void
    {
        foreach (self::ROLES_CANONICOS as $nombre) {
            Role::firstOrCreate(['name' => $nombre, 'guard_name' => 'web']);
        }

        // Migrar usuarios con rol legacy «Admin» al slug canónico «admin».
        Usuario::query()
            ->where(function ($q) {
                $q->where('role', 'Admin')
                    ->orWhereHas('roles', fn ($r) => $r->where('name', 'Admin'));
            })
            ->each(function (Usuario $usuario) {
                $usuario->syncRoles(['admin']);
                $usuario->role = 'admin';
                $usuario->fechamodificacion = now();
                $usuario->save();
            });

        // Migrar usuarios con roles legacy «operador» o «almacen» a «agricultor».
        Usuario::query()
            ->where(function ($q) {
                $q->whereIn('role', ['operador', 'almacen'])
                    ->orWhereHas('roles', fn ($r) => $r->whereIn('name', ['operador', 'almacen']));
            })
            ->each(function (Usuario $usuario) {
                $usuario->syncRoles(['agricultor']);
                $usuario->role = 'agricultor';
                $usuario->fechamodificacion = now();
                $usuario->save();
            });

        // Limpiar roles legacy vacíos para no contaminar el catálogo.
        Role::query()
            ->whereIn('name', self::ROLES_LEGACY)
            ->each(function (Role $role) {
                if ($role->users()->count() === 0) {
                    $role->delete();
                }
            });
    }
}
