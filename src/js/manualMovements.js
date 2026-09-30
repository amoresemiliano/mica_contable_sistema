import { appStore } from './store.js';
import { supabase } from './core/services/supabaseClient.js';
let renderEpoch = 0;
appStore.tenantResetListeners.push(() => {
    ++renderEpoch;
    globalThis.document?.getElementById?.('manual-records')?.replaceChildren?.();
});

export async function manualRequest(action, fields = {}, id = null, store = appStore, client = supabase) {
    const capability = { create:'manualCreate', edit:'manualEdit', delete:'manualSoftDelete' }[action];
    if (capability && !store.canOperationalAction(capability)) throw new Error('No tenés permiso para esta acción manual.');
    const org = store.activeOrganizationId, generation = store.contextGeneration;
    if (!org || store.contextState !== 'TENANT_READY') throw new Error('Seleccioná una organización.');
    ++store.pendingOperations;
    try {
        const { data, error } = await client.rpc('mica_manual_records', {
            p_action: action, p_expected_org: org, p_id: id, p_data: fields
        });
        if (error) throw new Error(error.message);
        if (generation !== store.contextGeneration || org !== store.activeOrganizationId) throw new Error('El contexto cambió. Recargá los movimientos.');
        return data;
    } finally { --store.pendingOperations; }
}

export class ManualMovements {
    static async save(kind, fields) {
        try {
            await manualRequest('create', { kind, fields });
            await renderManualRecords();
            return { success:true };
        } catch (error) { return { success:false, error:error.message }; }
    }
    static saveReginfoPurchase(fields) { return this.save('PURCHASE', fields); }
    static saveInternalMovement(fields) { return this.save('INTERNAL', fields); }
}

export async function renderManualRecords() {
    const root = document.getElementById('manual-records');
    if (!root?.replaceChildren) return;
    const generation = appStore.contextGeneration;
    const epoch = ++renderEpoch;
    root.replaceChildren();
    if (!appStore.hasCapability('MANUAL_MOVEMENT_VIEW', { scope:'ORGANIZATION', orgId:appStore.activeOrganizationId })) return;
    try {
        const rows = await manualRequest('list');
        if (generation !== appStore.contextGeneration || epoch !== renderEpoch) return;
        for (const row of rows) {
            const line = document.createElement('div'); line.className = 'manual-record-row';
            const caption = document.createElement('span');
            caption.textContent = `${row.payload.fields.fecha} · ${row.payload.fields.razonSocial || row.payload.fields.descripcion || row.payload.fields.tipo} · ${row.payload.fields.importeTotal || row.payload.fields.importe}`;
            line.append(caption);
            if (appStore.canOperationalAction('manualEdit')) {
                const edit = document.createElement('button'); edit.type = 'button'; edit.textContent = 'Editar';
                edit.onclick = () => {
                    const form = document.createElement('form');
                    for (const [name,value] of Object.entries(row.payload.fields)) {
                        const template = document.getElementById(row.payload.kind === 'PURCHASE' ? 'form-purchase-reginfo' : 'form-internal-movement');
                        const original = template?.querySelector(`[name="${name}"]`);
                        const label = document.createElement('label');
                        label.textContent = original?.closest('.form-group')?.querySelector('label')?.textContent || name;
                        const input = original && original.type !== 'radio' ? original.cloneNode(true) : document.createElement('input');
                        input.removeAttribute('id'); input.name = name; input.value = value; label.append(input); form.append(label);
                    }
                    const submit = document.createElement('button'); submit.textContent = 'Guardar cambios';
                    const status = document.createElement('p'); status.setAttribute('role','status'); form.append(submit,status);
                    form.onsubmit = async e => { e.preventDefault(); submit.disabled = true;
                        try { await manualRequest('edit',{kind:row.payload.kind,fields:Object.fromEntries(new FormData(form))},row.id); await renderManualRecords(); }
                        catch(error) { status.textContent = error.message; submit.disabled = false; }
                    }; line.append(form); edit.disabled = true;
                }; line.append(edit);
            }
            if (appStore.canOperationalAction('manualSoftDelete')) {
                const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = 'Eliminar';
                remove.onclick = async () => { remove.disabled = true;
                    try { await manualRequest('delete',{},row.id); await renderManualRecords(); }
                    catch(error) { remove.disabled = false; caption.textContent = error.message; }
                }; line.append(remove);
            }
            root.append(line);
        }
        if (!rows.length) root.textContent = 'Sin movimientos manuales guardados.';
    } catch(error) { if (generation === appStore.contextGeneration && epoch === renderEpoch) root.textContent = error.message; }
}
