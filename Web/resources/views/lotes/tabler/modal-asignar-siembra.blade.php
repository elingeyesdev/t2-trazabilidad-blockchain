<div class="modal fade" id="modalAsignarSiembra" tabindex="-1" role="dialog" aria-labelledby="modalAsignarSiembraLabel" aria-hidden="true">

    <div class="modal-dialog modal-dialog-centered" role="document">

        <div class="modal-content border-0 " style="border-radius: 14px; overflow: hidden;">

            <form method="POST" action="{{ route('lotes.siembra.asignar', $lote) }}" id="formAsignarSiembra">

                @csrf

                <div class="modal-header py-3 px-4" >

                    <h5 class="modal-title fw-semibold mb-0" id="modalAsignarSiembraLabel">

                        <i class="ti ti-plant-2 me-2"></i>Asignar siembra

                    </h5>

                    <button type="button" class="btn-close text-body" data-bs-dismiss="modal" aria-label="Cerrar">

                    </button>

                </div>

                <div class="modal-body px-4 py-4">

                    <p class="mb-3">

                        Indique quién va a sembrar el lote <strong>{{ $lote->nombre }}</strong>.

                        Cuando lo realice, el agricultor asignado podrá marcarla como completada con una foto.

                    </p>

                    @if($puede_designar_responsable_siembra ?? false)

                        <label class="small fw-semibold text-secondary d-block mb-2">Quién va a sembrar <span class="text-danger">*</span></label>

                        <x-tabler.catalogo-filter name="usuarioid" label="Agricultor responsable" :value="old('usuarioid', $responsable_siembra_inicial ?? '')" :selected-label="$responsable_siembra_label ?? ''" :endpoint="route('catalogo-selector.usuarios')" :params="$responsable_siembra_params ?? ['roles' => 'agricultor']" />

                        @error('usuarioid')<small class="text-danger d-block mt-1">{{ $message }}</small>@enderror

                    @else

                        <input type="hidden" name="usuarioid" value="{{ $responsable_siembra_inicial }}">

                        <div class="alert alert-light border small mb-0 py-2">

                            <i class="ti ti-user-check text-primary me-1"></i>

                            Responsable: <strong>{{ $responsable_siembra_label ?: 'Usted' }}</strong>

                        </div>

                    @endif

                    @error('siembra')<small class="text-danger d-block mt-2">{{ $message }}</small>@enderror

                </div>

                <div class="modal-footer border-0 bg-light px-4 py-3">

                    <button type="button" class="btn btn-outline-secondary" data-bs-dismiss="modal">Cancelar</button>

                    <button type="submit" class="btn btn-primary fw-semibold px-4">

                        <i class="ti ti-user-plus me-1"></i> Asignar siembra

                    </button>

                </div>

            </form>

        </div>

    </div>

</div>

