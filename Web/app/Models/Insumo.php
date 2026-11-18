<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Insumo extends Model
{
    use HasFactory;

    protected $table = 'insumo';
    protected $primaryKey = 'insumoid';
    public $timestamps = false;

    protected $fillable = [
        'nombre',
        'tipoinsumoid',
        'unidadmedidaid',
        'stock',
        'stockminimo',
        'proveedor',
        'actorid',
        'preciounitario',
        'descripcion',
        'imagenurl',
        'dosis_por_ha',
        'dosis_unidad',
        'semillas_por_kg',
        'rendimiento_cosecha_kg_ha',
        'codigo_transporte_requerido',
        'almacenid',
        'codigo_trazabilidad',
    ];

    protected $casts = [
        'insumoid'       => 'integer',
        'tipoinsumoid'   => 'integer',
        'unidadmedidaid' => 'integer',
        'actorid'        => 'integer',
        'stock'          => 'float',
        'stockminimo'    => 'float',
        'preciounitario' => 'float',
        'dosis_por_ha'   => 'float',
        'semillas_por_kg' => 'float',
        'rendimiento_cosecha_kg_ha' => 'float',
        'almacenid' => 'integer',
    ];

    protected $hidden = [
        'loteInsumos',
    ];

    public function tipo()
    {
        return $this->belongsTo(TipoInsumo::class, 'tipoinsumoid', 'tipoinsumoid');
    }

    public function unidadMedida()
    {
        return $this->belongsTo(UnidadMedida::class, 'unidadmedidaid', 'unidadmedidaid');
    }

    public function loteInsumos()
    {
        return $this->hasMany(LoteInsumo::class, 'insumoid', 'insumoid');
    }

    public function actorAbastecimiento()
    {
        return $this->belongsTo(ActorAbastecimiento::class, 'actorid', 'actorid');
    }

    public function almacen()
    {
        return $this->belongsTo(Almacen::class, 'almacenid', 'almacenid');
    }

    public function presentaciones()
    {
        return $this->hasMany(InsumoPresentacion::class, 'insumoid', 'insumoid');
    }

    /**
     * Decrementa el stock del insumo
     * @param float $cantidad
     * @return bool
     * @throws \Exception
     */
    public function decrementarStock(float|string $cantidad, ?int $partidaId = null, bool $retiro = false, ?int $excluirPedidoId = null, ?int $presentacionLoteId = null, ?string $unidades = null): bool
    {
        app(\App\Services\InventarioExistenciaService::class)->descontar($this, $cantidad, $partidaId, $retiro, $excluirPedidoId, $presentacionLoteId, $unidades);
        return true;
    }

    /**
     * Incrementa el stock del insumo
     * @param float $cantidad
     * @return bool
     */
    public function incrementarStock(float|string $cantidad): bool
    {
        $cantidad = \App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($cantidad));
        if (\App\Support\InventarioDecimal::unidades($cantidad) === 0) {
            throw new \Exception("La cantidad a incrementar debe ser mayor a 0");
        }

        return $this->modificarStockDecimal($cantidad, true);
    }

    /** Atomic compare-and-set also protects callers holding an outdated Eloquent model. */
    private function modificarStockDecimal(string $cantidad, bool $incrementar): bool
    {
        $delta = \App\Support\InventarioDecimal::unidades($cantidad);
        for ($intento = 0; $intento < 10; $intento++) {
            $raw = static::query()->whereKey($this->insumoid)->toBase()->value('stock');
            if ($raw === null) {
                throw new \InvalidArgumentException('El insumo ya no está disponible.');
            }
            $actual = \App\Support\InventarioDecimal::unidades($raw);
            if (! $incrementar && $actual < $delta) {
                throw new \InvalidArgumentException('Stock insuficiente para completar el consumo.');
            }
            $nuevo = $incrementar ? $actual + $delta : $actual - $delta;
            if ($nuevo > 999999999999999999) {
                throw new \InvalidArgumentException('El stock excede el rango decimal admitido.');
            }
            $cambio = static::query()->whereKey($this->insumoid)->where('stock', $raw)
                ->update(['stock' => \App\Support\InventarioDecimal::texto($nuevo)]);
            if ($cambio === 1) {
                $this->refresh();
                return true;
            }
        }
        throw new \RuntimeException('El inventario cambió concurrentemente. Reintente la operación.');
    }

    /**
     * Verifica si hay stock suficiente
     * @param float $cantidad
     * @return bool
     */
    public function tieneStockSuficiente(float $cantidad): bool
    {
        return $this->stock >= $cantidad;
    }

    /**
     * Verifica si el stock está por debajo del mínimo
     * @return bool
     */
    public function stockBajo(): bool
    {
        return app(\App\Services\InventarioExistenciaService::class)->resumen($this)['existencias_bajas'];
    }

    public function partidas()
    {
        return $this->hasMany(MateriaPrimaLote::class, 'insumoid', 'insumoid');
    }

    public function setStockAttribute($cantidad): void
    {
        $texto = \App\Support\InventarioDecimal::texto(\App\Support\InventarioDecimal::unidades($cantidad));
        $this->attributes['stock'] = rtrim(rtrim($texto, '0'), '.');
    }

    public function imagenSrc(int $width = 256): string
    {
        return \App\Support\InsumoImagenCatalogo::urlPara($this, $width);
    }
}
