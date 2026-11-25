<?php

namespace App\Console\Commands;

use Database\Seeders\AgroFusionDemoSeeder;
use Database\Seeders\CatalogosOperacionAgricolaSeeder;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Console\Command;

class AsegurarDatosDemoCommand extends Command
{
    protected $signature = 'agrofusion:asegurar-datos-demo';

    protected $description = 'Asegura catálogos, cuentas y recorrido completo de trazabilidad demo de AgroFusion';

    public function handle(): int
    {
        $this->info('Asegurando datos demo de AgroFusion (campo, planta, mayorista, distribución y PDV)…');

        $this->call('db:seed', ['--class' => RolePermissionSeeder::class, '--force' => true]);
        $this->call('db:seed', ['--class' => CatalogosOperacionAgricolaSeeder::class, '--force' => true]);
        $this->call('db:seed', ['--class' => AgroFusionDemoSeeder::class, '--force' => true]);

        $this->newLine();
        $this->info('Datos demo listos.');

        return self::SUCCESS;
    }
}
