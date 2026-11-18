<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class PlantaEtapaRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        $rules = [
            'parametros' => ['present', 'array', 'max:100'],
            'parametros.*' => ['array:variableestandarid,valor'],
            'parametros.*.variableestandarid' => ['required', 'integer', 'min:1', 'distinct'],
            'parametros.*.valor' => ['required', 'numeric'],
        ];
        foreach (['usuarioid', 'operador_usuarioid', 'responsable', 'estado', 'hora_inicio', 'hora_fin', 'fecha_registro', 'maquinaplantaid', 'procesoplantaid', 'loteproduccionpedidoid', 'cantidad_entrada', 'cantidad_salida', 'completar', 'completada_en', 'creado_en', 'asignado_por_usuarioid', 'registroprocesomaquinaplantaid'] as $campo) {
            $rules[$campo] = ['missing'];
        }

        return $rules;
    }

    public function messages(): array
    {
        return ['*.missing' => 'Este campo lo determina el servidor y no puede enviarse.',
            'parametros.present' => 'Envíe los parámetros medidos; use una lista vacía si esta etapa no requiere mediciones.',
            'parametros.*.variableestandarid.distinct' => 'El parámetro está repetido.',
            'parametros.*.valor.numeric' => 'Indique un valor numérico.'];
    }
}
