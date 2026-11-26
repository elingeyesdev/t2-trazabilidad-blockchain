<?php

namespace App\Console\Commands;

use App\Models\Insumo;
use App\Models\PuntoVenta;
use App\Support\CodigoTrazabilidadPdv;
use Illuminate\Console\Command;

class RegularizarCodigosPdvCommand extends Command
{
    protected $signature = 'trazabilidad:regularizar-pdv {--aplicar : Persiste códigos solo donde faltan}';

    protected $description = 'Revisa o regulariza códigos faltantes de productos vinculados a un PDV, sin cambiar stock ni antecedentes';

    public function handle(): int
    {
        $pendientes = 0;
        $asignados = 0;
        $invalidos = 0;
        $query = Insumo::whereIn('almacenid', PuntoVenta::whereNotNull('almacenid')->select('almacenid'));
        foreach ($query->orderBy('insumoid')->lazyById(200, 'insumoid') as $insumo) {
            $datos = CodigoTrazabilidadPdv::datos($insumo);
            if ($datos['trazabilidad_estado'] === 'codigo_no_admitido') {
                $invalidos++;
            }
            if (filled($insumo->codigo_trazabilidad)) {
                continue;
            }
            $pendientes++;
            if ($this->option('aplicar')) {
                CodigoTrazabilidadPdv::asegurar($insumo);
                $asignados++;
            }
        }
        $this->info(($this->option('aplicar') ? 'Aplicación' : 'Solo revisión').": faltantes={$pendientes}; asignados={$asignados}; códigos existentes no admitidos={$invalidos}.");
        $this->line('No se reemplazaron códigos existentes ni se modificaron cantidades o vínculos.');

        return self::SUCCESS;
    }
}
