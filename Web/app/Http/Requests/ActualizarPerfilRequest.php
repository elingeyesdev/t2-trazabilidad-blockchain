<?php

namespace App\Http\Requests;

use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Validator;

class ActualizarPerfilRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        $this->user()?->refresh();
    }

    public function authorize(): bool
    {
        $usuario = $this->user();
        if (! $usuario || ! $usuario->cuentaAprobada()) {
            return false;
        }

        $nombre = $this->input('nombreusuario');

        return ! ($this->esApi()
            && $usuario->nombreusuario_editado
            && is_string($nombre)
            && $nombre !== $usuario->nombreusuario);
    }

    protected function failedAuthorization(): void
    {
        throw new AuthorizationException('No tienes autorización para realizar este cambio de perfil.');
    }

    public function rules(): array
    {
        $usuario = $this->user();
        $rules = ['imagen' => 'nullable|image|mimes:jpeg,jpg,png,webp,gif|max:2048'];

        if (! $usuario->nombreusuario_editado || $this->esApi()) {
            $rules['nombreusuario'] = [
                'required',
                'string',
                'max:100',
                'regex:/^[a-zA-Z0-9._-]+$/',
                Rule::unique('usuario', 'nombreusuario')->ignore($usuario->usuarioid, 'usuarioid'),
            ];
            if ($this->esApi()) {
                array_unshift($rules['nombreusuario'], 'sometimes');
            }
        }

        return $rules;
    }

    public function messages(): array
    {
        return [
            'nombreusuario.regex' => 'El nombre de usuario solo puede contener letras, números, puntos, guiones y guiones bajos.',
            'nombreusuario.unique' => 'Ese nombre de usuario ya está en uso.',
        ];
    }

    public function attributes(): array
    {
        return ['nombreusuario' => 'nombre de usuario', 'imagen' => 'foto de perfil'];
    }

    public function after(): array
    {
        if (! $this->esApi()) {
            return [];
        }

        return [function (Validator $validator): void {
            foreach (array_diff(array_keys($this->all()), ['nombreusuario', 'imagen', '_method']) as $campo) {
                $validator->errors()->add($campo, 'Este campo no puede modificarse desde el perfil.');
            }
            if (! $this->has('nombreusuario') && ! $this->hasFile('imagen')) {
                $validator->errors()->add('perfil', 'Envía un nombre de usuario o una imagen.');
            }
        }];
    }

    private function esApi(): bool
    {
        return $this->routeIs('api.me.update');
    }
}
