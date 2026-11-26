<?php

namespace App\Services;

use App\Models\EnvioAsignacionMultiple;
use App\Models\RecepcionQrEnvio;
use App\Models\RutaDistribucion;
use App\Models\Usuario;
use App\Support\CosechaDecimal;
use App\Support\PublicUrlHelper;
use App\Support\RecepcionFirmaImagen;
use App\Support\UsuarioRol;
use Brick\Math\BigDecimal;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class EnvioRecepcionQrService
{
    public function __construct(private readonly EnvioMovilConsultaService $consulta) {}

    /** Un QR por destinatario; los códigos anteriores no cambian ni se invalidan. */
    public function emitir(EnvioAsignacionMultiple|RutaDistribucion $envio): array
    {
        return DB::transaction(function () use ($envio) {
            $envio = $this->bloquear($envio);
            $tipo = $this->consulta->tipo($envio);
            $destinatarios = $tipo === 'distribucion'
                ? $envio->pedidos()->with('puntoVenta')->get()->pluck('puntoVenta.usuarioid')->filter()->unique()->all()
                : [null];
            $resultado = [];
            foreach ($destinatarios as $id) {
                $clave = $tipo.':'.$envio->getKey().':'.($id ?? 'destino');
                $qr = RecepcionQrEnvio::where('clave_operacion', $clave)->first();
                if (! $qr) {
                    // La asignación agrícola ya tiene una restricción única; ampliar su código previo.
                    $qr = $tipo === 'agricola' ? app(RecepcionQrFirmaService::class)->ensureToken($envio) : new RecepcionQrEnvio;
                    $token = $qr->exists ? $qr->token : Str::random(48);
                    $qr->forceFill(['token' => hash('sha256', $token), 'token_cifrado' => $token,
                        'clave_operacion' => $clave, 'destinatario_usuarioid' => $id,
                        'envioasignacionmultipleid' => $tipo === 'agricola' ? $envio->getKey() : null,
                        'rutadistribucionid' => $tipo === 'agricola' ? null : $envio->getKey()])->save();
                }
                $resultado[] = $qr;
            }

            return $resultado;
        }, 5);
    }

    public function url(RecepcionQrEnvio $qr): string
    {
        return PublicUrlHelper::absoluteForQr('/recepcion/'.$qr->token);
    }

    public function resolver(string $contenido): RecepcionQrEnvio
    {
        if (str_contains($contenido, '://')) {
            $url = parse_url($contenido);
            $origenes = array_unique([rtrim(PublicUrlHelper::absoluteForQr(), '/'), rtrim(config('app.url'), '/'), rtrim(config('app.public_url') ?? '', '/')]);
            $origen = ($url['scheme'] ?? '').'://'.($url['host'] ?? '').(isset($url['port']) ? ':'.$url['port'] : '');
            if (! in_array($origen, $origenes, true) || isset($url['user']) || isset($url['pass']) || isset($url['query']) || isset($url['fragment']) || ! preg_match('~^/recepcion/([A-Za-z0-9_-]{16,64})$~D', $url['path'] ?? '', $m)) {
                $this->error('codigo', 'El QR no corresponde a un enlace de recepción de este sistema.');
            }
            $contenido = $m[1];
        }
        if (! preg_match('/^[A-Za-z0-9_-]{16,64}$/D', $contenido)) {
            $this->error('codigo', 'El código de recepción no es válido.');
        }
        $qr = RecepcionQrEnvio::where('token', hash('sha256', $contenido))
            ->orWhere(fn ($q) => $q->whereNull('token_cifrado')->where('token', $contenido))->first();
        if (! $qr) {
            $this->error('codigo', 'El código de recepción no es válido.');
        }

        return $qr;
    }

    public function operacion(RecepcionQrEnvio $qr): EnvioAsignacionMultiple|RutaDistribucion
    {
        return app(RecepcionQrFirmaService::class)->resolverOperacion($qr);
    }

    public function autorizarConsulta(RecepcionQrEnvio $qr, Usuario $user): EnvioAsignacionMultiple|RutaDistribucion
    {
        $envio = $this->operacion($qr);
        $envio = $this->consulta->buscar($this->consulta->tipo($envio), (int) $envio->getKey(), $user);
        if ($qr->destinatario_usuarioid && UsuarioRol::esMinorista($user)) {
            abort_unless((int) $qr->destinatario_usuarioid === (int) $user->getKey(), 404);
        }

        return $envio;
    }

    public function puedeConfirmar(RecepcionQrEnvio $qr, Usuario $user, EnvioAsignacionMultiple|RutaDistribucion $envio): bool
    {
        $tipo = $this->consulta->tipo($envio);
        if (! UsuarioRol::puedeOperar($user) || ! $this->consulta->permiso($tipo, $user, true) || (int) $envio->transportista_usuarioid === (int) $user->getKey()) {
            return false;
        }
        if ($tipo === 'distribucion') {
            return UsuarioRol::esMinorista($user) && (int) $qr->destinatario_usuarioid === (int) $user->getKey()
                && $envio->pedidos()->whereHas('puntoVenta', fn ($p) => $p->where('usuarioid', $user->getKey())->where('activo', true))->exists();
        }

        return app(RecepcionQrFirmaService::class)->esReceptorAutorizado($envio, $user);
    }

    /** Todos los efectos de recepción y el consumo del código se confirman juntos. */
    public function confirmar(RecepcionQrEnvio $qr, Usuario $user, array $lineas, string $imagen): RecepcionQrEnvio
    {
        $path = null;
        $operacion = $this->operacion($qr);
        try {
            return DB::transaction(function () use ($qr, $user, $lineas, $imagen, $operacion, &$path) {
                // Mismo mutex de operación para web/API y para códigos de destinatarios diferentes.
                // En SQLite, la primera consulta de la transacción debe adquirir el lock de escritura.
                $envio = $this->bloquear($operacion);
                $qr = RecepcionQrEnvio::whereKey($qr->getKey())->lockForUpdate()->firstOrFail();
                $this->autorizarConsulta($qr, $user);
                abort_unless($this->puedeConfirmar($qr, $user, $envio), 403);
                abort_if($qr->utilizado_en !== null, 409, 'Este código ya fue utilizado. Consulte el comprobante de la recepción registrada.');
                $tipo = $this->consulta->tipo($envio);
                // Los QR generales anteriores no pueden confirmar varios destinatarios.
                if ($tipo === 'distribucion' && ! $qr->destinatario_usuarioid) {
                    $this->error('codigo', 'Utilice el QR específico del destinatario.');
                }
                if (! $this->listaParaRecepcion($envio)) {
                    $this->error('envio', 'La recepción requiere un envío en ruta, llegada confirmada, incidentes revisados y firma del transportista.');
                }
                $esperadas = $this->consulta->lineas($envio, $user);
                if ($esperadas === [] || count($lineas) !== count($esperadas)) {
                    $this->error('lineas', 'Indique exactamente una cantidad por cada línea de este destinatario.');
                }
                $mapa = [];
                foreach ($lineas as $i => $linea) {
                    $id = $linea['id'] ?? null;
                    if (! is_scalar($id) || ! ctype_digit((string) $id) || isset($mapa[(int) $id])) {
                        $this->error('lineas.'.$i.'.id', 'La línea no es válida o está duplicada.');
                    }
                    $mapa[(int) $id] = $linea;
                }
                $cantidades = $traslado = $persistidas = [];
                foreach ($esperadas as $linea) {
                    $id = $linea['id'];
                    $dato = $mapa[$id] ?? null;
                    if (! $dato) {
                        $this->error('lineas', 'Las líneas deben pertenecer al envío y destinatario actuales.');
                    }
                    if (array_diff(array_keys($dato), ['id', 'cantidad_recibida', 'motivo'])) {
                        $this->error('lineas', 'Envíe solo la línea, cantidad recibida y motivo; la unidad y equivalencia las determina el servidor.');
                    }
                    $valor = $dato['cantidad_recibida'] ?? null;
                    $cero = $tipo === 'traslado' && is_scalar($valor) && ! is_bool($valor) && preg_match('/^0(?:\.0{1,4})?$/D', (string) $valor);
                    $cantidad = $cero ? '0.000000' : CosechaDecimal::cantidad($valor, 'lineas.'.$id.'.cantidad_recibida');
                    $recibida = BigDecimal::of($cantidad);
                    $enviada = BigDecimal::of($linea['cantidad_enviada']);
                    if ($recibida->isGreaterThan($enviada)) {
                        $this->error('lineas.'.$id.'.cantidad_recibida', 'No puede recibir más de lo enviado.');
                    }
                    if ($tipo === 'distribucion' && ! $recibida->isEqualTo($enviada)) {
                        $this->error('lineas.'.$id.'.cantidad_recibida', 'La distribución actual requiere recepción completa; no admite recepciones parciales.');
                    }
                    $motivo = $dato['motivo'] ?? null;
                    if ($motivo !== null && (! is_string($motivo) || mb_strlen($motivo) > 255)) {
                        $this->error('lineas.'.$id.'.motivo', 'El motivo debe ser texto de hasta 255 caracteres.');
                    }
                    if ($tipo === 'traslado') {
                        if (! preg_match('/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,4})?$/D', (string) $valor)) {
                            $this->error('lineas.'.$id.'.cantidad_recibida', 'El traslado admite hasta cuatro decimales.');
                        }
                        if ($recibida->isLessThan($enviada) && trim($motivo ?? '') === '') {
                            $this->error('lineas.'.$id.'.motivo', 'Indique el motivo de la diferencia recibida.');
                        }
                        $traslado[$id] = ['recibido' => $cantidad, 'motivo' => $motivo];
                    }
                    $cantidades[$id] = $cantidad;
                    $persistidas[] = $linea + ['cantidad_recibida' => $cantidad, 'motivo' => $motivo];
                }
                $bytes = RecepcionFirmaImagen::decodificar($imagen);
                $path = 'recepciones-envio/'.Str::uuid().'.png';
                if (! Storage::disk('local')->put($path, $bytes)) {
                    throw new \RuntimeException('No se pudo guardar la firma privada.');
                }
                if ($tipo === 'agricola') {
                    app(CierreEnvioAgricolaService::class)->guardarFirmaRecepcion($envio, $user, $imagen);
                    app(RecepcionPlantaEnvioService::class)->confirmarDesdePedido($envio->pedido, $user, $cantidades);
                } elseif ($tipo === 'traslado') {
                    app(CierreEnvioPlantaMayoristaService::class)->guardarFirmaRecepcion($envio, $user, $imagen, $traslado);
                    app(TrasladoPlantaMayoristaService::class)->transferirInventarioAlCompletar($envio->fresh(), $user);
                    $envio->update(['estado' => 'completada']);
                } else {
                    $pedidos = $envio->pedidos()->whereHas('puntoVenta', fn ($p) => $p->where('usuarioid', $user->getKey()))->orderBy('pedidodistribucionid')->lockForUpdate()->get();
                    foreach ($pedidos as $pedido) {
                        if ($pedido->estado !== 'en_transito') {
                            $this->error('envio', 'Uno de los pedidos ya fue recibido o no está en tránsito.');
                        }
                        app(RecepcionPuntoVentaService::class)->confirmar($pedido, $user);
                    }
                }
                $envio->refresh();
                $datos = $this->consulta->datos($envio, $user);
                $qr->forceFill(['firma_path' => $path, 'utilizado_en' => now(),
                    'datos_recepcion' => ['envio' => ['id' => $envio->getKey(), 'tipo' => $tipo, 'referencia' => $datos['referencia']],
                        'destinos' => $datos['destinos'], 'lineas' => $persistidas,
                        'firmante' => ['id' => (int) $user->getKey(), 'nombre' => RecepcionQrFirmaService::nombreDesdeUsuario($user)],
                        'fecha' => now()->toIso8601String()]])->save();

                return $qr;
            });
        } catch (\Throwable $e) {
            // Este método no ejecuta efectos posteriores al commit. Solo elimina su archivo nuevo.
            if ($path !== null) {
                Storage::disk('local')->delete($path);
            }
            throw $e;
        }
    }

    public function listaParaRecepcion(EnvioAsignacionMultiple|RutaDistribucion $envio): bool
    {
        $estadoValido = $envio instanceof EnvioAsignacionMultiple
            ? in_array($envio->estado, ['en_transporte_planta', 'en_ruta', 'en_transito'], true) && ! $envio->fecha_recepcion_planta
            : $envio->estado === 'en_ruta';

        return $estadoValido && $envio->llegada_confirmada_at !== null
            && $envio->checklistIncidente()->exists() && $envio->firmaTransportista()->exists();
    }

    private function bloquear(EnvioAsignacionMultiple|RutaDistribucion $envio): EnvioAsignacionMultiple|RutaDistribucion
    {
        if (DB::getDriverName() === 'sqlite') {
            $envio->newQuery()->whereKey($envio->getKey())->update(['estado' => DB::raw('estado')]);
        }

        return $envio->newQuery()->whereKey($envio->getKey())->lockForUpdate()->firstOrFail();
    }

    private function error(string $campo, string $mensaje): never
    {
        throw ValidationException::withMessages([$campo => $mensaje]);
    }
}
