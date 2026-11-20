<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class IncidenteResolucionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->can('incidentes.resolve') ?? false;
    }

    protected function prepareForValidation(): void
    {
        if (is_string($this->input('nota_resolucion'))) {
            $this->merge(['nota_resolucion' => trim($this->input('nota_resolucion'))]);
        }
    }

    public function rules(): array
    {
        return ['nota_resolucion' => ['required', 'string', 'max:2000'],
            'estado' => ['missing'], 'responsable_usuarioid' => ['missing'], 'descripcion' => ['missing'],
            'resueltopor_usuarioid' => ['missing'], 'fecha_resolucion' => ['missing']];
    }
}
