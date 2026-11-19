<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class PlantaRecepcionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $rules = ['cantidades' => ['required', 'array', 'min:1', 'max:200'],
            'cantidades.*' => ['required', 'regex:/^(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,6})?$/D', 'numeric', 'gt:0']];
        foreach (['usuarioid', 'recepcion_usuarioid', 'estado', 'almacenid', 'fecha_recepcion_planta', 'stock', 'insumoid', 'fecha_vencimiento', 'recepcion_planta_datos', 'pedidoid', 'envioasignacionmultipleid'] as $campo) {
            $rules[$campo] = ['missing'];
        }

        return $rules;
    }

    public function messages(): array
    {
        return ['*.missing' => 'Este campo lo determina el servidor y no puede enviarse.',
            'cantidades.required' => 'Indique el pesaje por línea del pedido.',
            'cantidades.*.regex' => 'Indique una cantidad positiva con hasta seis decimales.',
            'cantidades.*.gt' => 'La cantidad recibida debe ser mayor que cero.'];
    }
}
