<?php

namespace Database\Seeders;

use App\Models\Usuario;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Spatie\Permission\Models\Role;

class AdminUserSeeder extends Seeder
{
    private const DEMO_PASSWORD = '12345';

    public function run(): void
    {
        Role::firstOrCreate(['name' => 'admin', 'guard_name' => 'web']);

        $admin = Usuario::updateOrCreate(
            ['email' => 'admin@agrofusion.com'],
            [
                'nombre' => 'Administrador',
                'apellido' => 'AgroFusion',
                'nombreusuario' => 'admin',
                'telefono' => '700000001',
                'passwordhash' => Hash::make(self::DEMO_PASSWORD),
                'role' => 'admin',
                'activo' => true,
                'estado_cuenta' => 'aprobado',
                'fecharegistro' => now(),
                'fechamodificacion' => now(),
            ]
        );

        $admin->syncRoles(['admin']);
    }
}
