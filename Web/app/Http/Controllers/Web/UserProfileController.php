<?php

namespace App\Http\Controllers\Web;

use App\Http\Controllers\Controller;
use App\Http\Requests\ActualizarPerfilRequest;
use App\Services\PerfilUsuarioService;
use App\Support\UsuarioAvatar;
use Illuminate\Http\RedirectResponse;
use Illuminate\View\View;

class UserProfileController extends Controller
{
    public function show(): View
    {
        $user = auth()->user();
        $avatarUrl = UsuarioAvatar::resolve($user);

        return view('profile.show', compact('user', 'avatarUrl'));
    }

    public function update(ActualizarPerfilRequest $request, PerfilUsuarioService $perfiles): RedirectResponse
    {
        $perfiles->actualizar($request->user(), $request->validated());

        return redirect()
            ->route('profile.show')
            ->with('success', 'Perfil actualizado correctamente.');
    }

    public function marcarBienvenidaVista(): RedirectResponse
    {
        $user = auth()->user();
        $user->bienvenida_vista = true;
        $user->save();

        return redirect()->back()->with('success', '¡Bienvenido a AgroFusion!');
    }
}
