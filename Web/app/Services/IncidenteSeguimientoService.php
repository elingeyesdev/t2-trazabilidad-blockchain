<?php

namespace App\Services;

use App\Models\IncidenteEnvio;
use App\Models\Usuario;
use App\Support\UsuarioRol;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

final class IncidenteSeguimientoService
{
    public function __construct(private IncidenteReferenciaService $referencias) {}

    public function obtener(int $id, Usuario $usuario): IncidenteEnvio
    {
        return $this->referencias->scope(IncidenteEnvio::query(), $usuario)->with(['responsable', 'reportadoPor', 'resueltoPor'])->findOrFail($id);
    }

    /** A selectable person needs actual resolution permission and access to the same operation. */
    public function responsables(string $tipo, Model $modelo): array
    {
        return Usuario::permission('incidentes.resolve')->where('activo', true)
            ->where(fn ($q) => $q->where('estado_cuenta', 'aprobado')->orWhereNull('estado_cuenta'))
            ->orderBy('usuarioid')->get()->filter(fn ($u) => $this->referencias->puedeAtenderTipo($tipo, $u)
                && $this->referencias->consulta($tipo, $u)->whereKey($modelo->getKey())->exists())
            ->map(fn ($u) => ['usuarioid' => (int) $u->getKey(), 'nombre' => trim($u->nombre.' '.$u->apellido)])->values()->all();
    }

    public function registrar(Usuario $usuario, array $datos): IncidenteEnvio
    {
        abort_unless($usuario->can('incidentes.create') && UsuarioRol::puedeOperar($usuario), 403);
        foreach (['tipo', 'descripcion'] as $campo) {
            if (is_string($datos[$campo] ?? null)) {
                $datos[$campo] = trim($datos[$campo]);
            }
        }
        Validator::make($datos, ['tipo' => 'required|string|max:100', 'descripcion' => 'required|string|max:3000'])->validate();
        [$tipo, $modelo, $vinculos] = $this->referencias->desdeEntrada($datos, $usuario);
        $responsable = (int) ($datos['responsable_usuarioid'] ?? 0);
        if (! in_array($responsable, array_column($this->responsables($tipo, $modelo), 'usuarioid'), true)) {
            throw ValidationException::withMessages(['responsable_usuarioid' => 'Seleccione un responsable elegible para este pedido o envío.']);
        }

        return DB::transaction(fn () => IncidenteEnvio::create([
            ...$vinculos, 'responsable_usuarioid' => $responsable,
            'reportadopor_usuarioid' => $usuario->getKey(), 'estado' => 'abierto',
            'tipo' => trim($datos['tipo']), 'descripcion' => trim($datos['descripcion']),
        ]));
    }

    public function puedeResolver(IncidenteEnvio $incidente, Usuario $usuario): bool
    {
        return UsuarioRol::puedeOperar($usuario) && $usuario->can('incidentes.resolve')
            && $this->referencias->puedeAtenderTipo((string) $incidente->afectado_tipo, $usuario)
            && $incidente->responsable_usuarioid !== null
            && $this->referencias->scope(IncidenteEnvio::whereKey($incidente->getKey()), $usuario)->exists();
    }

    public function actualizar(Usuario $usuario, int $id, array $datos): IncidenteEnvio
    {
        abort_unless(UsuarioRol::puedeOperar($usuario) && $usuario->can('incidentes.update'), 403);

        return DB::transaction(function () use ($usuario, $id, $datos) {
            if (DB::getDriverName() === 'sqlite') {
                DB::table('incidente_envio')->where('incidenteenvioid', $id)->update(['estado' => DB::raw('estado')]);
            }
            $i = $this->referencias->scope(IncidenteEnvio::query(), $usuario)->whereKey($id)->lockForUpdate()->firstOrFail();
            abort_unless(in_array($i->estado, ['abierto', 'pendiente'], true), 409, 'Una incidencia resuelta conserva su contenido confirmado.');
            foreach (['tipo', 'descripcion'] as $campo) {
                if (isset($datos[$campo]) && $datos[$campo] !== $i->{$campo}) {
                    abort_unless((int) $i->reportadopor_usuarioid === (int) $usuario->getKey(), 403);
                    $i->{$campo} = $datos[$campo];
                }
            }
            if (! empty($datos['responsable_usuarioid']) && (int) $datos['responsable_usuarioid'] !== (int) $i->responsable_usuarioid) {
                abort_unless($this->referencias->puedeAtenderTipo((string) $i->afectado_tipo, $usuario), 403);
                abort_if($i->responsable_usuarioid !== null, 409, 'La reasignación no forma parte de este flujo.');
                $entrada = $i->afectado_tipo
                    ? ['afectado_tipo' => $i->afectado_tipo, 'afectado_id' => $i->{$this->referencias->columna($i->afectado_tipo)}]
                    : ['externo_envio_id' => $i->externo_envio_id, 'pedidoid' => $i->pedidoid];
                [$tipo, $modelo, $vinculos] = $this->referencias->desdeEntrada($entrada, $usuario);
                if (! in_array((int) $datos['responsable_usuarioid'], array_column($this->responsables($tipo, $modelo), 'usuarioid'), true)) {
                    throw ValidationException::withMessages(['responsable_usuarioid' => 'El responsable no es elegible para esta operación.']);
                }
                $i->fill($vinculos);
                $i->responsable_usuarioid = $datos['responsable_usuarioid'];
            }
            $i->save();

            return $i;
        }, 5);
    }

    public function resolver(Usuario $usuario, int $id, string $nota): IncidenteEnvio
    {
        $nota = trim($nota);
        if ($nota === '' || mb_strlen($nota) > 2000) {
            throw ValidationException::withMessages(['nota_resolucion' => 'Indique una explicación de solución de hasta 2000 caracteres.']);
        }

        return DB::transaction(function () use ($usuario, $id, $nota) {
            // SQLite cannot SELECT FOR UPDATE: obtain its write lock before reading state.
            if (DB::getDriverName() === 'sqlite') {
                DB::table('incidente_envio')->where('incidenteenvioid', $id)->update(['estado' => DB::raw('estado')]);
            }
            $incidente = $this->referencias->scope(IncidenteEnvio::query(), $usuario)->whereKey($id)->lockForUpdate()->firstOrFail();
            abort_unless($this->puedeResolver($incidente, $usuario), 403);
            if ($incidente->estado === 'resuelto') {
                abort_unless($incidente->nota_resolucion === $nota, 409, 'La incidencia ya tiene otra solución confirmada.');

                return $incidente;
            }
            abort_unless(in_array($incidente->estado, ['abierto', 'pendiente'], true), 409, 'El estado actual no permite resolver la incidencia.');
            $incidente->update(['estado' => 'resuelto', 'nota_resolucion' => $nota,
                'fecha_resolucion' => now(), 'resueltopor_usuarioid' => $usuario->getKey()]);

            return $incidente;
        }, 5);
    }
}
