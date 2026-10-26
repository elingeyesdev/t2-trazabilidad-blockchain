<?php

// Datos ficticios para integrar perfil y permisos sin usar la base habitual.
require_once __DIR__.'/entorno-flutter.php';
$database = prepararEntornoFlutter('profilecheck', 8009, 'agrofusion-perfil-flutter-');

// El caso negativo usa el nombre admin sin permisos, solo en esta base vacía.
Spatie\Permission\Models\Role::findByName('admin', 'web')->syncPermissions([]);
$cases = [
    'campo' => ['Campo', ['agricultor'], []],
    'multirrol' => ['Equipo', ['agricultor', 'planta'], []],
    'directo' => ['Permiso directo', [], ['pedidos.view']],
    'sinpermisos' => ['Sin permisos', [], []],
    'adminvacio' => ['Admin sin permisos', ['admin'], []],
    'supervisor' => ['Supervisor', ['admin'], ['usuarios.admin']],
];
$users = [];
foreach ($cases as $key => [$name, $roles, $permissions]) {
    $user = App\Models\Usuario::create([
        'nombre' => $name, 'apellido' => 'Flutter',
        'email' => 'flutter.'.$key.'@example.test', 'nombreusuario' => 'flutter_'.$key,
        'passwordhash' => Illuminate\Support\Facades\Hash::make('Flutter-Perfil-2026'),
        'activo' => true, 'estado_cuenta' => App\Support\CuentaEstado::APROBADO,
        'bienvenida_vista' => true, 'nombreusuario_editado' => false,
    ]);
    $user->syncRoles($roles);
    $user->syncPermissions($permissions);
    $users[$key] = $user;
    echo $user->email.' | roles: '.implode(', ', $roles)
        .' | permisos: '.implode(', ', $user->getAllPermissions()->pluck('name')->sort()->all())."\n";
}
$cultivo = App\Models\Cultivo::create(['nombre' => 'Tomate de prueba']);
$estado = App\Models\EstadoLoteTipo::firstOrCreate(['nombre' => 'Planificado']);
foreach (['campo', 'multirrol'] as $key) {
    $lote = App\Models\Lote::create(App\Support\LoteDefaults::enrich([
        'usuarioid' => $users[$key]->usuarioid, 'nombre' => 'Lote Flutter '.$key,
        'superficie' => 1.5, 'ubicacion' => 'Entorno ficticio de verificación',
        'cultivoid' => $cultivo->cultivoid, 'estadolotetipoid' => $estado->estadolotetipoid,
    ]));
    App\Support\LoteDefaults::registrarHistorialInicial($lote);
}
$pedido = App\Models\Pedido::create([
    'numero_solicitud' => 'FLUTTER-PERFIL-001', 'nombre_planta' => 'Planta de prueba',
    'latitud' => 0, 'longitud' => 0, 'estado' => 'pendiente', 'fechapedido' => now(),
]);
$pedido->detalles()->create(['cultivo_personalizado' => 'Tomate de prueba', 'cantidad' => 5]);

echo "Perfil preparado: .env.profilecheck\nBase SQLite aislada: {$database}\n";
echo "Contraseña ficticia común: Flutter-Perfil-2026\n";
echo "Ejecuta: php artisan serve --env=profilecheck --host=127.0.0.1 --port=8009 --no-reload\n";
