<?php

namespace App\Services;

use App\Models\Almacen;
use App\Models\Pedido;
use App\Models\Usuario;
use App\Models\Vehiculo;
use App\Support\CampoAccess;
use App\Support\EnvioPedidoService;
use App\Support\EnvioTrayectoCatalogo;
use App\Support\PedidoCatalogo;
use App\Support\UsuarioRol;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

class PedidoAgricolaCreacionService
{
    public function crear(Request $request): \App\Models\Pedido
    {
        EnvioTrayectoCatalogo::autorizarTrayecto($request->user(), EnvioTrayectoCatalogo::TRAYECTO_PLANTA);
        app(PedidoEntradaService::class)->proteger($request);

        return app(PedidoSolicitudService::class)->ejecutar($request, \App\Models\Pedido::class, fn () => $this->crearNuevo($request));
    }

    private function crearNuevo(Request $request): \App\Models\Pedido
    {

        EnvioTrayectoCatalogo::autorizarTrayecto($request->user(), EnvioTrayectoCatalogo::TRAYECTO_PLANTA);

        $data = $request->validate([
            'origen_latitud' => 'required|numeric|between:-90,90',
            'origen_longitud' => 'required|numeric|between:-180,180',
            'origen_direccion' => 'nullable|string|max:255',
            'origen_almacenid' => 'nullable|integer|exists:almacen,almacenid',
            'latitud' => 'required|numeric|between:-90,90',
            'longitud' => 'required|numeric|between:-180,180',
            'direccion_texto' => 'nullable|string|max:255',
            'fechaEntregaDeseada' => 'required|date',
            'hora_recogida' => 'nullable|date_format:H:i',
            'hora_entrega_estimada' => 'nullable|date_format:H:i',
            'instrucciones_recogida' => 'nullable|string|max:2000',
            'instrucciones_entrega' => 'nullable|string|max:2000',
            'observaciones' => 'nullable|string',
            'transportista_usuarioid' => 'required|integer|exists:usuario,usuarioid',
            'vehiculoid' => 'required|integer|exists:vehiculo,vehiculoid',
            'costo_bs' => 'required|integer|min:1|max:99999999',
            'recogidas' => 'nullable|array|max:5',
            'recogidas.*.latitud' => 'required|numeric|between:-90,90',
            'recogidas.*.longitud' => 'required|numeric|between:-180,180',
            'recogidas.*.direccion' => 'nullable|string|max:255',
            'recogidas.*.almacenid' => 'nullable|integer|exists:almacen,almacenid',
            'detalles' => 'required|array|min:1',
            'detalles.*.producto_ref' => ['required', 'string', 'regex:/^(insumo|cosecha|cultivo):\d+$/'],
            'detalles.*.cantidad' => 'required|numeric|min:0.01',
            'detalles.*.observaciones' => 'nullable|string',
        ], [
            'detalles.*.producto_ref.regex' => 'Seleccione un producto válido de producción agrícola.',
            'fechaEntregaDeseada.required' => 'Indique la fecha de entrega deseada.',
        ]);

        // AGR-07: origen / recogidas solo desde almacén agrícola del propio jefe.
        $this->assertAlmacenesAgricolasPropios($request->user(), $data);
        app(PedidoEntradaService::class)->agricola($request, $data);

        $erroresStock = PedidoCatalogo::validarStockDetallesPedido(
            $data['detalles'],
            isset($data['origen_almacenid']) ? (int) $data['origen_almacenid'] : null,
            array_values($data['recogidas'] ?? [])
        );
        if ($erroresStock !== null) {
            throw \Illuminate\Validation\ValidationException::withMessages($erroresStock);
        }

        $erroresPresentacion = PedidoCatalogo::validarPresentacionDetallesPedido($data['detalles']);
        if ($erroresPresentacion !== null) {
            throw \Illuminate\Validation\ValidationException::withMessages($erroresPresentacion);
        }

        $pesoTotalKg = \Brick\Math\BigDecimal::zero();
        foreach ($data['detalles'] as $linea) {
            $pesoTotalKg = $pesoTotalKg->plus((string) $linea['cantidad']);
        }
        $vehiculo = Vehiculo::query()->findOrFail((int) $data['vehiculoid']);
        app(TransporteCapacidadService::class)->validarCarga($vehiculo, (float) (string) $pesoTotalKg);

        $transportistaId = (int) $data['transportista_usuarioid'];
        $vehiculoId = (int) $data['vehiculoid'];
        $costoBs = (float) $data['costo_bs'];
        $recogidasExtra = array_values($data['recogidas'] ?? []);

        $pedido = null;

        try {
            DB::transaction(function () use ($data, $transportistaId, $vehiculoId, $costoBs, $recogidasExtra, &$pedido) {
                $detallesInput = $data['detalles'];
                unset($data['detalles'], $data['transportista_usuarioid'], $data['vehiculoid'], $data['recogidas'], $data['costo_bs']);

                $pedido = Pedido::create([
                    ...$data,
                    'numero_solicitud' => PedidoCatalogo::generarNumeroSolicitud(),
                    'nombre_planta' => null,
                    'estado' => PedidoCatalogo::ESTADO_INICIAL,
                    'creado_por_usuarioid' => auth()->id(),
                    'fechapedido' => now(),
                ]);

                foreach ($detallesInput as $detalle) {
                    $producto = PedidoCatalogo::resolverProductoPedido($detalle['producto_ref']);

                    $pedido->detalles()->create([
                        'insumoid' => $producto['insumoid'],
                        'materiaprimaloteid' => $detalle['materiaprimaloteid'] ?? null,
                        'producto_ref' => $detalle['producto_ref'],
                        'produccionalmacenamientoid' => str_starts_with($detalle['producto_ref'], 'cosecha:')
                            ? (int) substr($detalle['producto_ref'], 8)
                            : null,
                        'cultivo_personalizado' => $producto['cultivo'],
                        'cantidad' => $detalle['cantidad'],
                        'observaciones' => $detalle['observaciones'] ?? null,
                        'datos_solicitud' => $detalle['datos_solicitud'] ?? null,
                    ]);
                }

                $envio = EnvioPedidoService::programarTransportista(
                    $pedido,
                    $transportistaId,
                    $vehiculoId,
                    (int) auth()->id(),
                    $costoBs
                );

                if ($recogidasExtra !== []) {
                    EnvioPedidoService::crearRutaRecogidasMultiples(
                        $pedido,
                        $envio,
                        $recogidasExtra,
                        $transportistaId,
                        (int) auth()->id()
                    );
                }
            });
        } catch (\InvalidArgumentException $e) {
            throw \Illuminate\Validation\ValidationException::withMessages(['vehiculoid' => $e->getMessage()]);
        }

        app(NotificacionUsuarioService::class)->pedidoPendienteAgricola($pedido->fresh(['detalles']));

        return $pedido;
    }

    private function assertAlmacenesAgricolasPropios(?Usuario $user, array $data): void
    {
        if (! $user || UsuarioRol::esAdminGlobal($user)) {
            return;
        }

        $errores = [];
        $ids = [];

        if (! empty($data['origen_almacenid'])) {
            $ids['origen_almacenid'] = (int) $data['origen_almacenid'];
        }

        foreach ($data['recogidas'] ?? [] as $i => $recogida) {
            if (! empty($recogida['almacenid'])) {
                $ids['recogidas.'.$i.'.almacenid'] = (int) $recogida['almacenid'];
            }
        }

        if ($ids === [] && UsuarioRol::gestionaCampo($user)) {
            throw ValidationException::withMessages([
                'origen_almacenid' => 'Debe indicar el almacén agrícola de origen de su equipo.',
            ]);
        }

        foreach ($ids as $campo => $almacenId) {
            $almacen = Almacen::query()->find($almacenId);
            if ($almacen === null || ! CampoAccess::puedeVerAlmacen($user, $almacen)) {
                $errores[$campo] = 'No puede usar un almacén agrícola que no pertenece a su equipo.';
            } elseif (UsuarioRol::esJefeAgricultor($user)
                && ! CampoAccess::puedeGestionarAlmacen($user, $almacen)) {
                $errores[$campo] = 'Solo puede enviar desde un almacén agrícola del que es responsable.';
            }
        }

        if ($errores !== []) {
            throw ValidationException::withMessages($errores);
        }
    }
}
