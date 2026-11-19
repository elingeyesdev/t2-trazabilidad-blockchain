@php($partidasAnteriores = old('detalles', []))
<script>
document.addEventListener('DOMContentLoaded', function () {
    const partidas = @json($partidasAgricolas ?? []);
    const anteriores = @json($partidasAnteriores);
    function actualizar() {
        document.querySelectorAll('input[name$="[producto_ref]"]').forEach(function (producto) {
            const nombre = producto.name.replace('[producto_ref]', '[materiaprimaloteid]');
            const id = producto.value.startsWith('insumo:') ? producto.value.substring(7) : null;
            const envoltura = producto.closest('.selector-catalogo-wrapper') || producto;
            let caja = envoltura.parentElement.querySelector(':scope > .pedido-partida-material');
            const huella = producto.name + '|' + producto.value;
            if (caja && caja.dataset.origen === huella) return;
            const seleccionado = caja?.dataset.producto === producto.value ? caja.querySelector('select')?.value : null;
            if (caja) caja.remove();
            if (id === null || !Object.prototype.hasOwnProperty.call(partidas, id)) return;
            caja = document.createElement('div');
            caja.className = 'pedido-partida-material mt-2';
            caja.dataset.origen = huella;
            caja.dataset.producto = producto.value;
            const label = document.createElement('label');
            label.className = 'small text-muted mb-1';
            label.textContent = 'Partida de material de origen';
            const select = document.createElement('select');
            select.className = 'form-control form-control-sm';
            select.name = nombre;
            select.required = true;
            const indice = producto.name.match(/detalles\[(\d+)\]/)?.[1];
            const anterior = seleccionado || anteriores[indice]?.materiaprimaloteid;
            select.append(new Option(partidas[id].length ? 'Seleccione una partida' : 'Sin partidas utilizables', ''));
            partidas[id].forEach(function (p) { select.append(new Option(p.label, String(p.id))); });
            if (anterior) select.value = String(anterior);
            label.append(select);
            caja.append(label);
            envoltura.insertAdjacentElement('afterend', caja);
        });
    }
    actualizar();
    new MutationObserver(actualizar).observe(document.body, {childList: true, subtree: true});
    document.addEventListener('change', actualizar);
});
</script>
