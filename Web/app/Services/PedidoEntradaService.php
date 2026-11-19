<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\Insumo;
use App\Models\InsumoPresentacion;
use App\Models\InventarioPresentacionLote;
use App\Models\ProduccionAlmacenamiento;
use App\Support\AlmacenAmbito;
use App\Support\CampoAccess;
use App\Support\CosechaDecimal;
use App\Support\InventarioDecimal;
use App\Support\MayoristaAccess;
use App\Support\PedidoCatalogo;
use App\Support\UsuarioRol;
use Brick\Math\BigDecimal;
use Brick\Math\RoundingMode;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;

/** Cantidades exactas y disponibilidad acumulada, compartidas por web, API y confirmación. */
class PedidoEntradaService
{
    public function proteger(Request $request): void
    {
        $reglas = [];
        foreach (['estado', 'creado_por_usuarioid', 'usuarioid', 'propietario', 'organizacionid', 'aceptado_por_usuarioid',
            'fecha_aceptacion', 'fecha_aceptacion_agricola', 'fechapedido', 'solicitud_huella', 'datos_solicitud', 'envio_iniciado_mayorista',
            'fecha_confirmacion_minorista', 'numero_solicitud', 'registrado_manual_por_usuarioid', 'responsable_usuarioid', 'decision', 'motivo_rechazo', 'acciones_disponibles', 'reservado'] as $campo) {
            $reglas[$campo] = ['missing'];
        }
        foreach (['cantidad_kg', 'cantidad_base', 'equivalencia', 'peso_neto_kg', 'datos_solicitud', 'unidadmedidaid', 'pedidoid', 'pedidodistribucionid', 'detallepedidoid', 'detallepedidodistribucionid'] as $campo) {
            $reglas['detalles.*.'.$campo] = ['missing'];
        }
        $request->validate($reglas, ['missing' => 'El campo :attribute lo determina el servidor y no debe enviarse.']);
    }

    private function error(string $campo, string $mensaje): never
    {
        throw ValidationException::withMessages([$campo => $mensaje]);
    }

    public function factor($unidad): ?string
    {
        if (! $unidad) {
            return null;
        }
        $unidad = clone $unidad;
        $unidad->categoria ??= 'peso';

        return CosechaDecimal::factorUnidad($unidad);
    }

    public function agricola(Request $request, array &$data): void
    {
        $request->validate(['detalles.*.insumo_presentacionid' => ['missing'],
            'detalles.*.materiaprimaloteid' => ['nullable', 'integer', 'min:1'],
            'detalles.*.catalogotamanoconteoid' => ['nullable', 'integer', 'min:1']], ['missing' => 'El pedido agrícola usa la presentación de su origen, no una presentación industrial.']);
        $ids = CampoAccess::scopeAlmacenesAgricolas(Almacen::query()->where('activo', true), $request->user())->pluck('almacenid')->all();
        $acumulado = [];
        $porPartida = [];
        foreach ($data['detalles'] as $i => &$linea) {
            $campo = 'detalles.'.$i;
            $ref = $linea['producto_ref'];
            $cantidad = CosechaDecimal::cantidad($linea['cantidad'], $campo.'.cantidad');
            $parteId = $request->input($campo.'.materiaprimaloteid');
            if (str_starts_with($ref, 'cosecha:')) {
                if ($parteId) {
                    $this->error($campo.'.materiaprimaloteid', 'La cosecha ya identifica su partida de almacenamiento.');
                }
                $origen = ProduccionAlmacenamiento::with(['unidadMedida', 'produccion', 'catalogoTamanoConteo.tipoEmpaque'])->whereIn('almacenid', $ids)->find((int) substr($ref, 8));
                $stock = $origen?->fechasalida === null ? $origen?->getRawOriginal('cantidad') : '0';
                $factor = $origen?->produccion?->presentacion_cosecha['unidad_factor_kg'] ?? $this->factor($origen?->unidadMedida);
                $calibre = $origen?->catalogoTamanoConteo;
                $presentacion = $calibre?->nombre;
                if ($request->input($campo.'.catalogotamanoconteoid') !== null && (int) $request->input($campo.'.catalogotamanoconteoid') !== (int) $calibre?->getKey()) {
                    $this->error($campo.'.catalogotamanoconteoid', 'La presentación no corresponde a esta cosecha.');
                }
            } elseif (str_starts_with($ref, 'insumo:')) {
                $origen = Insumo::with(['unidadMedida', 'tipo'])->whereIn('almacenid', $ids)->find((int) substr($ref, 7));
                $stock = $origen ? app(InventarioExistenciaService::class)->resumen($origen)['cantidad_disponible'] : null;
                $factor = $this->factor($origen?->unidadMedida);
                $calibreId = $request->input($campo.'.catalogotamanoconteoid');
                $calibre = $calibreId ? \App\Models\CatalogoTamanoConteo::whereKey($calibreId)->where('insumoid', $origen?->getKey())->where('activo', true)->first() : null;
                if ($calibreId && ! $calibre) {
                    $this->error($campo.'.catalogotamanoconteoid', 'La presentación no corresponde al material de siembra.');
                }
                $presentacion = $calibre?->nombre;
            } else {
                $this->error($campo.'.producto_ref', 'Seleccione una cosecha o material de siembra con existencias; un cultivo de catálogo no identifica stock.');
            }
            if (! $origen || ! in_array($origen->almacenid, $ids)) {
                $this->error($campo.'.producto_ref', 'El producto no pertenece a un almacén agrícola de su ámbito.');
            }
            if ($origen instanceof Insumo) {
                PedidoCatalogo::resolverProductoPedido($ref);
            }
            $recogida = $i === 0 ? ($data['origen_almacenid'] ?? null) : ($data['recogidas'][$i - 1]['almacenid'] ?? $data['origen_almacenid'] ?? null);
            if ($recogida && (int) $recogida !== (int) $origen->almacenid) {
                $this->error($campo.'.producto_ref', 'El producto no corresponde al almacén de recogida.');
            }
            if ($factor === null || $stock === null) {
                $this->error($campo.'.producto_ref', 'El origen no tiene una equivalencia verificable en kg.');
            }
            if ($origen instanceof Insumo) {
                $partidas = app(InventarioExistenciaService::class)->partidas($origen);
                if ($partidas->isNotEmpty() && ! $parteId) {
                    $this->error($campo.'.materiaprimaloteid', 'Seleccione la partida de material que realmente se utilizará.');
                }
                if ($parteId) {
                    $parte = $partidas->firstWhere('materiaprimaloteid', (int) $parteId);
                    if (! $parte || ! app(InventarioExistenciaService::class)->utilizable($parte)) {
                        $this->error($campo.'.materiaprimaloteid', 'La partida es ajena al producto, está vencida o no está habilitada.');
                    }
                    $porPartida[$parteId] = ($porPartida[$parteId] ?? BigDecimal::zero())->plus($cantidad);
                    if ($porPartida[$parteId]->isGreaterThan(BigDecimal::of((string) $parte->getRawOriginal('cantidad_disponible'))->multipliedBy($factor))) {
                        $this->error($campo.'.cantidad', 'Las líneas exceden la cantidad utilizable de la partida seleccionada.');
                    }
                }
            }
            try {
                BigDecimal::of($cantidad)->dividedBy($factor, 6, RoundingMode::UNNECESSARY);
            } catch (\Brick\Math\Exception\MathException $e) {
                $this->error($campo.'.cantidad', 'La cantidad no puede expresarse con seis decimales en la unidad del origen.');
            }
            $acumulado[$ref] = ($acumulado[$ref] ?? BigDecimal::zero())->plus($cantidad);
            $kgStock = BigDecimal::of((string) $stock)->multipliedBy($factor);
            if ($acumulado[$ref]->isGreaterThan($kgStock)) {
                $this->error($campo.'.cantidad', 'La cantidad acumulada supera las existencias disponibles del origen.');
            }
            $linea['cantidad'] = $cantidad;
            $linea['materiaprimaloteid'] = $parteId ? (int) $parteId : null;
            $linea['datos_solicitud'] = ['unidad' => 'kg', 'unidad_origen_id' => $origen->unidadmedidaid,
                'factor_origen_kg' => $factor, 'almacen_id' => (int) $origen->almacenid,
                'catalogotamanoconteoid' => $calibre ? (int) $calibre->getKey() : null,
                'presentacion' => $presentacion ?? PedidoCatalogo::descripcionEmpaqueDetalle($linea['observaciones'] ?? null)];
        }
    }

    public function distribucion(Request $request, array $lineas, ?int $excluirPedido = null, bool $bloquear = true): void
    {
        $existencias = app(InventarioExistenciaService::class);
        // Las reservas comerciales, consumos y entradas compiten por el mismo lock de producto.
        if ($bloquear) {
            $existencias->bloquear(array_values(array_unique(array_column($lineas, 'insumoid'))));
        }
        $porPresentacion = $porPartida = $porProductoKg = [];
        foreach ($lineas as $i => $linea) {
            $campo = 'detalles.'.$i;
            $cantidad = CosechaDecimal::cantidad($linea['cantidad'], $campo.'.cantidad');
            $insumo = Insumo::with('almacen')->find($linea['insumoid']);
            $presentacion = InsumoPresentacion::whereKey($linea['insumo_presentacionid'] ?? 0)->where('insumoid', $linea['insumoid'])->where('activo', true)->first();
            if ($presentacion && ($presentacion->getRawOriginal('peso_neto_kg') === null || ! BigDecimal::of((string) $presentacion->getRawOriginal('peso_neto_kg'))->isPositive())) {
                $this->error($campo.'.insumo_presentacionid', 'La presentación no tiene un peso configurado válido.');
            }
            if (! $presentacion) {
                $this->error($campo.'.insumo_presentacionid', 'La presentación no existe, está inactiva o no pertenece al producto.');
            }
            if (! $insumo || $insumo->almacen?->ambito !== AlmacenAmbito::MAYORISTA || ! $insumo->almacen->activo) {
                $this->error($campo.'.insumoid', 'El producto no está disponible en almacén mayorista.');
            }
            if (UsuarioRol::esMayorista($request->user()) && ! MayoristaAccess::puedeVerAlmacen($request->user(), $insumo->almacen)) {
                abort(403, 'El producto «'.$insumo->nombre.'» pertenece a un almacén mayorista que no es suyo.');
            }
            $seleccionado = $linea['inventario_presentacion_loteid'] ?? null;
            $partidas = InventarioPresentacionLote::where('insumoid', $insumo->getKey())->where('almacenid', $insumo->almacenid)->where('insumo_presentacionid', $presentacion->getKey())->orderBy('inventario_presentacion_loteid')->get();
            if ($seleccionado && ! $partidas->contains('inventario_presentacion_loteid', (int) $seleccionado)) {
                $this->error($campo.'.inventario_presentacion_loteid', 'La partida no corresponde al producto, presentación y almacén.');
            }
            $utiles = $partidas->filter(fn ($p) => $existencias->estadoFecha($p->fecha_vencimiento?->toDateString()) !== 'vencido' && ($p->fecha_vencimiento !== null || config('inventario.permitir_sin_fecha')));
            $stock = BigDecimal::zero();
            foreach ($utiles as $p) {
                $stock = $stock->plus((string) $p->getRawOriginal('cantidad_unidades'));
            }
            $reservaQuery = \App\Models\DetallePedidoDistribucion::query()->join('pedido_distribucion as p', 'p.pedidodistribucionid', '=', 'detalle_pedido_distribucion.pedidodistribucionid')
                ->where('p.estado', 'confirmado')->where('detalle_pedido_distribucion.insumoid', $insumo->getKey())
                ->where('detalle_pedido_distribucion.insumo_presentacionid', $presentacion->getKey())
                ->when($excluirPedido, fn ($q) => $q->where('p.pedidodistribucionid', '!=', $excluirPedido));
            $reservas = $reservaQuery->get(['detalle_pedido_distribucion.cantidad', 'detalle_pedido_distribucion.inventario_presentacion_loteid']);
            $reservado = BigDecimal::zero();
            foreach ($reservas as $r) {
                $reservado = $reservado->plus((string) $r->getRawOriginal('cantidad'));
            }
            $clave = $presentacion->getKey();
            $porPresentacion[$clave] = ($porPresentacion[$clave] ?? BigDecimal::zero())->plus($cantidad);
            if ($porPresentacion[$clave]->isGreaterThan($stock->minus($reservado))) {
                $this->error($campo.'.cantidad', 'La cantidad acumulada supera el stock utilizable sin reservar de esta presentación.');
            }
            if ($seleccionado) {
                $porPartida[$seleccionado] = ($porPartida[$seleccionado] ?? BigDecimal::zero())->plus($cantidad);
                $partida = $utiles->firstWhere('inventario_presentacion_loteid', (int) $seleccionado);
                $reservadoPartida = BigDecimal::zero();
                foreach ($reservas->where('inventario_presentacion_loteid', (int) $seleccionado) as $r) {
                    $reservadoPartida = $reservadoPartida->plus((string) $r->getRawOriginal('cantidad'));
                }
                if (! $partida || $porPartida[$seleccionado]->isGreaterThan(BigDecimal::of((string) $partida->getRawOriginal('cantidad_unidades'))->minus($reservadoPartida))) {
                    $this->error($campo.'.cantidad', 'La partida está vencida, bloqueada o no tiene cantidad suficiente sin reservar.');
                }
            }
            $kg = BigDecimal::of(CosechaDecimal::kg($cantidad, (string) ($linea['datos_solicitud']['peso_neto_kg'] ?? $presentacion->getRawOriginal('peso_neto_kg'))));
            $porProductoKg[$insumo->getKey()] = ($porProductoKg[$insumo->getKey()] ?? BigDecimal::zero())->plus($kg);
            $resumen = $existencias->resumen($insumo);
            $disponible = BigDecimal::of($resumen['cantidad_fisica'])->minus($resumen['cantidad_vencida'])->minus($resumen['cantidad_bloqueada'])
                ->minus(InventarioDecimal::texto($existencias->reservado($insumo, $excluirPedido)));
            if (! $resumen['saldo_coherente'] || $porProductoKg[$insumo->getKey()]->isGreaterThan($disponible)) {
                $this->error($campo.'.cantidad', 'Las líneas del mismo producto exceden su disponibilidad total, incluidas reservas y vencimientos.');
            }
        }
    }
}
