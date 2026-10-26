<?php

// Entorno local reproducible para verificar Flutter sin usar la base habitual.
require_once __DIR__.'/entorno-flutter.php';
$database = prepararEntornoFlutter('authcheck', 8008, 'agrofusion-auth-flutter-');

$user = App\Models\Usuario::create([
    'nombre' => 'Cuenta Flutter',
    'apellido' => 'Prueba',
    'email' => 'flutter.autorizado@example.test',
    'nombreusuario' => 'flutter_autorizado',
    'passwordhash' => Illuminate\Support\Facades\Hash::make('Flutter-Prueba-2026'),
    'activo' => true,
    'estado_cuenta' => App\Support\CuentaEstado::APROBADO,
    'bienvenida_vista' => true,
    'nombreusuario_editado' => false,
]);
$user->assignRole('agricultor');

echo "Entorno preparado: .env.authcheck\n";
echo "Base SQLite aislada: {$database}\n";
echo "Cuenta ficticia aprobada: flutter.autorizado@example.test\n";
echo "Contraseña de prueba: Flutter-Prueba-2026\n";
echo "Ejecuta: php artisan serve --env=authcheck --host=127.0.0.1 --port=8008 --no-reload\n";
