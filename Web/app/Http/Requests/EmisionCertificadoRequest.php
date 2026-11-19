<?php

namespace App\Http\Requests;

use App\Models\CertificacionLote;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class EmisionCertificadoRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $planta = $this->route('loteProduccion') !== null;
        $rules = ['solicitud_id' => ['nullable', 'uuid'],
            'observaciones' => ['nullable', 'string', 'max:'.($planta ? '500' : '1000')],
            'recomendaciones' => ['nullable', 'string', 'max:2000'],
            $planta ? 'razon' : 'resultado' => [$planta ? 'required' : 'nullable', 'string', Rule::in(CertificacionLote::RAZONES)]];
        if (! $planta) {
            $rules['loteid'] = ['required', 'integer', 'exists:lote,loteid'];
        }
        foreach (['usuarioid', 'inspector_usuarioid', 'fecha_certificacion', 'fecha_evaluacion', 'codigo_certificado',
            'archivo_path', 'datos_emision', 'formato_version', 'emision_uuid', 'solicitud_huella', 'blockchain_estado', 'blockchain_txid'] as $campo) {
            $rules[$campo] = ['missing'];
        }

        return $rules;
    }

    public function messages(): array
    {
        return ['*.missing' => 'Este dato lo determina el servidor y no puede modificarse.',
            'solicitud_id.uuid' => 'Use un UUID distinto para cada emisión intencional.'];
    }
}
