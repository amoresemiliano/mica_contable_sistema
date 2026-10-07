// Explicit Platform target, never an operational context. The RPC owns authorization.
export function renderPlatformRates(container, store, service, target, openEditor) {
    const doc = container.ownerDocument || globalThis.document;
    const el = (tag, text, props = {}) => { const n = doc.createElement(tag); n.textContent = text ?? ''; Object.assign(n, props); return n; };
    const status = el('p', 'Cargando definiciones IIBB…', { role: 'status' });
    const heading = el('header'); heading.append(el('h4', 'Tasas IIBB disponibles'));
    const body = el('div'); container.append(heading, status, body);
    const identity = () => [store.sessionUserId, store.contextGeneration, store.contextState, store.activeOrganizationId].join('|');
    const initialIdentity = identity();
    const current = () => identity() === initialIdentity && (!('isConnected' in container) || container.isConnected);
    let model, busy = false;
    function input(form, name, label, type = 'text', options = null) {
        const wrap = el('label', label), n = el(options ? 'select' : 'input', '', { name, ...(!options ? { type } : {}), required: !['valid_to'].includes(name) });
        if (options) for (const row of options) n.append(el('option', row.name, { value: row.id }));
        wrap.append(n); form.append(wrap); return n;
    }
    async function perform(action, payload) {
        if (busy || !current()) return;
        busy = true; status.textContent = 'Guardando…';
        try { await service.platformRates(action, ['assign','unassign'].includes(action) ? target : null, payload); if (current()) await load(); }
        catch (error) { if (current()) status.textContent = error.message; }
        finally { busy = false; }
    }
    function draw() {
        heading.replaceChildren(el('h4', 'Tasas IIBB disponibles'));
        const create = el('button', '+ Nueva definición IIBB', { type: 'button', className: 'btn-primary' });
        create.onclick = () => {
            const editor = openEditor('Nueva definición IIBB'), form = el('form', '', { className: 'mica-admin-form' });
            input(form, 'activity_id', 'Actividad', 'text', model.activities);
            input(form, 'jurisdiction', 'Jurisdicción').maxLength = 160;
            const rate = input(form, 'rate', 'Tasa %', 'number'); rate.min = 0; rate.max = 100; rate.step = '0.01';
            input(form, 'valid_from', 'Vigente desde', 'date'); input(form, 'valid_to', 'Vigente hasta', 'date');
            const feedback = el('p', '', { role: 'status' }), submit = el('button', 'Guardar', { type: 'submit' });
            form.append(el('p', 'Cada definición es una versión. Crear una nueva no cambia las asignaciones ni las tasas históricas.'), submit, feedback); editor.append(form);
            form.onsubmit = async event => {
                event.preventDefault(); if (busy || !current()) return; busy = true; submit.disabled = true;
                try { await service.platformRates('create', null, Object.fromEntries(new FormData(form))); feedback.textContent = 'Definición guardada.'; if (current()) await load(); }
                catch (error) { feedback.textContent = error.message; }
                finally { busy = false; submit.disabled = false; }
            };
        };
        heading.append(create); body.replaceChildren();
        if (!target) body.append(el('p', 'Seleccioná una empresa para asignar o quitar tasas.'));
        else if (!model.organizations.some(o => o.id === target)) { body.append(el('p', 'La empresa no está dentro de tu alcance para administrar tasas.')); return; }
        const table = el('table', '', { className: 'mica-admin-table' });
        const tr = el('tr'); for (const title of ['Actividad','Jurisdicción','Tasa %','Desde','Hasta','Estado','Empresa','Acciones']) tr.append(el('th', title, { scope: 'col' }));
        const head = el('thead'); head.append(tr); table.append(head);
        const tbody = el('tbody'); table.append(tbody);
        for (const rate of model.definitions) {
            const row = el('tr'); row.dataset ||= {}; row.dataset.definitionId = rate.id;
            for (const value of [rate.activity_name,rate.jurisdiction,rate.rate,rate.valid_from || 'Sin límite',rate.valid_to || 'Sin límite',rate.is_active ? 'Activa' : 'Inactiva', target ? rate.assigned ? 'Asignada' : 'Sin asignar' : 'Elegí empresa']) row.append(el('td', String(value)));
            const actions = el('td');
            if (target && (rate.is_active || rate.assigned)) {
                const assign = el('button', rate.assigned ? 'Quitar asignación' : 'Asignar', { type: 'button' });
                assign.onclick = () => perform(rate.assigned ? 'unassign' : 'assign', { id: rate.id }); actions.append(assign);
            }
            const toggle = el('button', rate.is_active ? 'Desactivar definición' : 'Activar definición', { type: 'button' });
            toggle.onclick = () => perform('set_active', { id: rate.id, is_active: !rate.is_active }); actions.append(toggle); row.append(actions); tbody.append(row);
        }
        if (!model.definitions.length) body.append(el('p', 'No hay definiciones IIBB disponibles.'));
        else { const scroll = el('div', '', { className: 'mica-admin-table-scroll' }); scroll.append(table); body.append(scroll); }
        body.append(el('p', 'Para asignar una tasa, la actividad debe estar asignada y no debe existir otra tasa con vigencia superpuesta. IVA se muestra como referencia general.'));
    }
    async function load() {
        try {
            if (!service.platformRates) throw Error('La administración global de tasas requiere la migración 041.');
            model = await service.platformRates('list', target || null);
            if (!current()) return; status.textContent = ''; draw();
        } catch (error) { if (current()) status.textContent = error.message; }
    }
    return load();
}
