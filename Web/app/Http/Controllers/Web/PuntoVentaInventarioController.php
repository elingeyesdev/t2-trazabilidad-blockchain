<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Models\AlmacenMovimiento;
use App\Models\Insumo;
use App\Models\PuntoVenta;
use App\Models\TipoMovimientoAlmacen;
use App\Services\InventarioAlmacenProductoService;
use App\Services\AlmacenCapacidadService;
use App\Services\PuntoVentaInventarioPresentacionService;
use App\Services\RecepcionPuntoVentaService;
use App\Support\EliminacionSegura;
use App\Support\PuntoVentaAccess;
use App\Support\TrazabilidadProductoPdvService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Illuminate\View\View;

class PuntoVentaInventarioController extends Controller
{
    public function index(
        Request $request,
        PuntoVentaInventarioPresentacionService $presentaciones,
        RecepcionPuntoVentaService $recepcionPdv
    ): View {
        $user = $request->user();

        $puntos = PuntoVentaAccess::scopePuntosDelUsuario(
            PuntoVenta::query()->where('activo', true)->orderBy('nombre'),
            $user
        )->get();

        $puntosFiltrados = $puntos;
        if ($request->filled('puntoventaid')) {
            $puntosFiltrados = $puntos->where('puntoventaid', (int) $request->puntoventaid)->values();
        }

        // Pedidos ya «recibidos» sin stock visible en el almacén PDV (legado): acreditar una vez.
        $recepcionPdv->repararInventarioPedidosRecibidos($puntosFiltrados);

        $termino = $request->filled('q') ? $request->string('q')->trim()->toString() : null;
        $lineas = $presentaciones->lineasParaPuntos($puntosFiltrados, $termino);

        return view('punto_venta.inventario.index', [
            'puntos' => $puntos,
            'lineas' => $lineas,
            'esAdmin' => $user && \App\Support\UsuarioRol::esAdminGlobal($user),
            'filtroPdv' => $request->integer('puntoventaid') ?: null,
            'filtroPdvNombre' => $request->filled('puntoventaid')
                ? ($puntos->firstWhere('puntoventaid', (int) $request->puntoventaid)?->nombre ?? '')
                : '',
            'filtroQ' => $request->string('q')->toString(),
        ]);
    }

    public function edit(PuntoVenta $punto, Insumo $insumo, AlmacenCapacidadService $capacidadService): View
    {
        $this->autorizarInsumo($punto, $insumo);

        $resumenCapacidad = $punto->almacen
            ? $capacidadService->resumen($punto->almacen)
            : null;

        return view('punto_venta.puntos.inventario.edit', compact('punto', 'insumo', 'resumenCapacidad'));
    }

    public function update(
        Request $request,
        PuntoVenta $punto,
        Insumo $insumo,
        AlmacenCapacidadService $capacidadService
    ): RedirectResponse {
        $this->autorizarInsumo($punto, $insumo);

        $data = $request->validate([
            'nombre' => 'required|string|max:150',
            'stock' => 'required|numeric|min:0',
            'stockminimo' => 'nullable|numeric|min:0',
            'descripcion' => 'nullable|string|max:500',
            'motivo_ajuste' => 'nullable|string|max:500',
        ], [
            'stock.min' => 'El stock no puede ser negativo.',
            'stockminimo.min' => 'El stock mínimo no puede ser negativo.',
        ]);

        $almacen = $punto->almacen;
        abort_unless($almacen !== null, 404);

        app(\App\Services\InventarioMovimientoService::class)->actualizarFicha($request->user(), $insumo,
            ['nombre' => $data['nombre'], 'stock' => $data['stock'], 'stockminimo' => $data['stockminimo'] ?? null,
                'descripcion' => $data['descripcion'] ?? $insumo->descripcion],
            $data['motivo_ajuste'] ?? null, $request->filled('materiaprimaloteid') ? (int) $request->input('materiaprimaloteid') : null);

        $destino = $request->input('return') === 'inventario'
            ? route('punto-venta.inventario.index', ['puntoventaid' => $punto->puntoventaid])
            : route('punto-venta.puntos.show', $punto);

        return redirect()
            ->to($destino)
            ->with('success', 'Producto del inventario actualizado.');
    }

    public function destroy(
        PuntoVenta $punto,
        Insumo $insumo,
        InventarioAlmacenProductoService $inventarioAlmacen
    ): RedirectResponse {
        $this->autorizarInsumo($punto, $insumo);

        $almacen = $punto->almacen;
        abort_unless($almacen !== null, 404);

        $insumoObjetivo = Insumo::query()
            ->whereKey((int) $insumo->insumoid)
            ->where('almacenid', (int) $almacen->almacenid)
            ->firstOrFail();

        EliminacionSegura::ejecutar(
            fn () => $inventarioAlmacen->eliminarProducto($almacen, $insumoObjetivo),
            'No se pudo eliminar el producto. Revise movimientos o referencias vinculadas.'
        );

        $destino = request()->input('return') === 'inventario'
            ? route('punto-venta.inventario.index', ['puntoventaid' => $punto->puntoventaid])
            : route('punto-venta.puntos.show', $punto);

        return redirect()
            ->to($destino)
            ->with('success', 'Producto eliminado del inventario.');
    }

    public function qr(PuntoVenta $punto, Insumo $insumo, TrazabilidadProductoPdvService $service): JsonResponse
    {
        $this->autorizarInsumo($punto, $insumo);

        $url = $service->urlPublica($insumo);
        $insumo->refresh();

        return response()->json([
            'url' => $url,
            'codigo' => $insumo->codigo_trazabilidad,
            'producto' => $insumo->nombre,
        ]);
    }

    private function autorizarInsumo(PuntoVenta $punto, Insumo $insumo): void
    {
        abort_unless(PuntoVentaAccess::puedeEditarPunto(auth()->user(), $punto), 403);
        abort_unless(
            $punto->almacenid && (int) $insumo->almacenid === (int) $punto->almacenid,
            404
        );
    }
}
