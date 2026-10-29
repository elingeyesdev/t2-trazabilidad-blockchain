import { Modal, bootstrap } from '@tabler/core';
import $ from 'jquery';
import L from 'leaflet';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

window.jQuery = window.$ = $;
window.L = L;
window.bootstrap = bootstrap;
L.Icon.Default.mergeOptions({ iconUrl: markerIcon, iconRetinaUrl: markerIcon2x, shadowUrl: markerShadow });
// Existing operational scripts use the modal API, backed exclusively by Tabler's Bootstrap 5.
$.fn.modal = function (option) {
    return this.each(function () {
        const modal = Modal.getOrCreateInstance(this, typeof option === 'object' ? option : {});
        if (typeof option === 'string') modal[option]();
    });
};

document.querySelectorAll('[data-lotes-view]').forEach(button => {
    button.addEventListener('click', () => {
        document.querySelectorAll('[data-lotes-view]').forEach(item => {
            const active = item === button;
            item.classList.toggle('active', active);
            item.setAttribute('aria-pressed', String(active));
        });
        document.getElementById('tableView').hidden = button.dataset.lotesView !== 'table';
        document.getElementById('cardView').hidden = button.dataset.lotesView !== 'cards';
    });
});
document.querySelectorAll('[data-confirm-delete]').forEach(form => {
    form.addEventListener('submit', event => {
        if (!window.confirm('¿Eliminar lote? No podrás revertir esto.')) event.preventDefault();
    });
});

const created = document.getElementById('modalLoteCreado');
if (created) Modal.getOrCreateInstance(created).show();

const modalEl = document.getElementById('catalogoModal');
if (modalEl) {
    const modal = Modal.getOrCreateInstance(modalEl);
    const search = document.getElementById('catalogoBuscar');
    const results = document.getElementById('catalogoResultados');
    const previous = document.getElementById('catalogoAnterior');
    const next = document.getElementById('catalogoSiguiente');
    const pageLabel = document.getElementById('catalogoPagina');
    let active, page = 1, controller, timer, opener, parentModal;
    const load = async () => {
        controller?.abort();
        const request = new AbortController();
        controller = request;
        previous.disabled = next.disabled = true;
        results.textContent = 'Cargando…';
        const url = new URL(active.dataset.endpoint, window.location.origin);
        Object.entries(JSON.parse(active.dataset.params)).forEach(([key, value]) => url.searchParams.set(key, value));
        url.searchParams.set('q', search.value);
        url.searchParams.set('page', page);
        try {
            const response = await fetch(url, { headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' }, signal: request.signal });
            if (!response.ok) throw new Error('No se pudo cargar el catálogo.');
            const json = await response.json();
            if (request.signal.aborted) return;
            results.replaceChildren();
            const choose = (id, label) => {
                active.querySelector('input[type=hidden]').value = id;
                active.querySelector('[data-catalogo-label]').textContent = label;
                modal.hide();
            };
            const empty = document.createElement('button');
            empty.type = 'button';
            empty.className = 'list-group-item list-group-item-action';
            empty.textContent = 'Todos';
            empty.addEventListener('click', () => choose('', 'Todos'));
            results.append(empty);
            json.data.forEach(item => {
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'list-group-item list-group-item-action';
                button.textContent = item.label;
                if (item.meta) {
                    const detail = document.createElement('small');
                    detail.className = 'd-block text-secondary';
                    detail.textContent = typeof item.meta === 'string' ? item.meta : '';
                    button.append(detail);
                }
                button.addEventListener('click', () => choose(item.id, item.label));
                results.append(button);
            });
            if (!json.data.length) results.append(document.createTextNode('No hay coincidencias.'));
            const last = json.meta?.last_page ?? 1;
            previous.disabled = page <= 1;
            next.disabled = page >= last;
            pageLabel.textContent = `${page} de ${last}`;
        } catch (error) {
            if (error.name !== 'AbortError') {
                results.textContent = 'No se pudo cargar el catálogo. Reintenta la búsqueda o vuelve a iniciar sesión.';
                pageLabel.textContent = '';
            }
        }
    };
    document.querySelectorAll('[data-catalogo-filter]').forEach(field => {
        field.querySelector('[data-catalogo-open]').addEventListener('click', event => {
            active = field;
            opener = event.currentTarget;
            page = 1;
            search.value = '';
            document.getElementById('catalogoTitulo').textContent = field.dataset.title;
            parentModal = opener.closest('.modal');
            const open = () => { modal.show(); load(); };
            if (parentModal?.classList.contains('show')) {
                parentModal.addEventListener('hidden.bs.modal', open, { once: true });
                Modal.getOrCreateInstance(parentModal).hide();
            } else open();
        });
        field.querySelector('[data-catalogo-clear]').addEventListener('click', () => {
            field.querySelector('input[type=hidden]').value = '';
            field.querySelector('[data-catalogo-label]').textContent = 'Todos';
        });
    });
    modalEl.addEventListener('shown.bs.modal', () => search.focus());
    modalEl.addEventListener('hidden.bs.modal', () => {
        controller?.abort();
        clearTimeout(timer);
        if (parentModal) {
            parentModal.addEventListener('shown.bs.modal', () => opener?.focus(), { once: true });
            Modal.getOrCreateInstance(parentModal).show();
        } else opener?.focus();
    });
    search.addEventListener('input', () => {
        controller?.abort();
        clearTimeout(timer);
        timer = setTimeout(() => { page = 1; load(); }, 300);
    });
    search.addEventListener('keydown', event => { if (event.key === 'Enter') event.preventDefault(); });
    previous.addEventListener('click', () => { page--; load(); });
    next.addEventListener('click', () => { page++; load(); });
}

document.querySelectorAll('[data-lote-map]').forEach(element => {
    const lat = Number(element.dataset.lat), lng = Number(element.dataset.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    const map = L.map(element).setView([lat, lng], 15);
    const accent = getComputedStyle(element).getPropertyValue('--tblr-primary').trim() || '#23754b';
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', { attribution: '© OpenStreetMap' }).addTo(map);
    const marker = L.circleMarker([lat, lng], { radius: 7, color: '#ffffff', weight: 2, fillColor: accent, fillOpacity: 1 }).addTo(map);
    const popup = document.createElement('strong');
    popup.textContent = element.dataset.name;
    marker.bindPopup(popup).openPopup();
    const area = Number(element.dataset.area);
    if (area > 0) L.circle([lat, lng], { radius: Math.sqrt(area * 10000 / Math.PI), color: accent, fillOpacity: .08, weight: 1 }).addTo(map);
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(element);
});
