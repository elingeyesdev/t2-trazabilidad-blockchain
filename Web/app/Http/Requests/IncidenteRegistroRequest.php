<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class IncidenteRegistroRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('incidentes.create') ?? false;
    }

    protected function prepareForValidation(): void
    {
        foreach (['tipo', 'descripcion', 'externo_envio_id'] as $campo) {
            if (is_string($this->input($campo))) {
                $this->merge([$campo => trim($this->input($campo))]);
            }
        }
    }

    public function rules(): array
    {
        return [
            'afectado_tipo' => ['nullable', 'required_with:afectado_id', 'in:pedido_agricola,pedido_distribucion,envio_agricola,traslado,distribucion'],
            'afectado_id' => ['nullable', 'required_with:afectado_tipo', 'integer', 'min:1'],
            'externo_envio_id' => ['nullable', 'string', 'max:64'],
            'pedidoid' => ['nullable', 'integer', 'min:1'],
            'tipo' => ['required', 'string', 'max:100'],
            'descripcion' => ['required', 'string', 'max:3000'],
            'responsable_usuarioid' => ['nullable', 'integer', 'min:1'],
            'estado' => ['missing'], 'reportadopor_usuarioid' => ['missing'], 'resueltopor_usuarioid' => ['missing'],
            'fecha_resolucion' => ['missing'], 'nota_resolucion' => ['missing'], 'created_at' => ['missing'],
            'almacenid' => ['missing'], 'pedidodistribucionid' => ['missing'], 'rutadistribucionid' => ['missing'],
            'envioasignacionmultipleid' => ['missing'],
        ];
    }
}
