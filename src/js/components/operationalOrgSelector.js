// One implementation, mounted in every module. The store owns all context transitions.
export function mountOperationalOrgSelectors(store, document) {
    const views = [];
    for (const section of document.querySelectorAll('.tab-content')) {
        const toolbar = document.createElement('div');
        toolbar.className = 'operational-context-toolbar';
        const label = document.createElement('label');
        label.textContent = 'Organización ';
        const select = document.createElement('select');
        select.className = 'form-control operational-org-select';
        select.setAttribute('aria-label', 'Contexto operacional');
        label.append(select);
        const status = document.createElement('span');
        status.setAttribute('role', 'status');
        const retry = document.createElement('button');
        retry.className = 'btn-secondary';
        retry.textContent = 'Reintentar carga';
        retry.onclick = () => store.reloadOperationalContext().catch(() => {});
        select.onchange = () => store.switchOrganizationContext(select.value).catch(() => {});
        toolbar.append(label, status, retry);
        const body = document.createElement('div');
        body.className = 'operational-module-body';
        while (section.firstChild) body.append(section.firstChild);
        section.append(toolbar, body);
        views.push({ section, label, select, status, retry, body });
    }
    const render = () => {
        const ready = ['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState);
        const busy = ['SWITCHING', 'LOADING'].includes(store.contextState);
        for (const view of views) {
            view.label.hidden = !store.hasCapability('ACCESS_ANY_ORG');
            view.select.disabled = busy;
            view.select.replaceChildren();
            const choices = [{ organization_id: '', organization_name: 'MICA / Plataforma' }, ...store.operationalOrgTargets];
            if (store.activeOrganizationId && !choices.some(o => o.organization_id === store.activeOrganizationId)) {
                choices.push({ organization_id: store.activeOrganizationId, organization_name: store.getActiveOrganizationName() });
            }
            for (const choice of choices) {
                const option = document.createElement('option');
                option.value = choice.organization_id;
                option.textContent = choice.organization_name;
                view.select.append(option);
            }
            view.select.value = store.activeOrganizationId || '';
            view.status.textContent = store.contextError || (busy ? 'Cargando contexto…' : '');
            view.retry.hidden = store.contextState !== 'ERROR';
            const platformPage = ['tab-categorizacion', 'tab-configuracion'].includes(view.section.id);
            const blocked = !ready || (!store.activeOrganizationId && !platformPage);
            view.body.hidden = blocked;
            view.body.inert = blocked;
            if (ready && !store.activeOrganizationId && !platformPage) view.status.textContent = 'Seleccioná una organización para revisar este módulo.';
        }
    };
    store.subscribe(render);
    render();
    return render;
}

export function renderOperationalImportControls(store, document) {
    const types = { recibidos: 'recibido', emitidos: 'emitido', percepciones: 'percepcion', bancos: 'banco', sueldos: 'sueldo' };
    for (const [name, type] of Object.entries(types)) {
        const allowed = store.canImportOperational(type);
        const zone = document.getElementById(`zone-${name}`);
        const input = document.getElementById(`file-${name}`);
        if (zone) { zone.hidden = !allowed; zone.inert = !allowed; }
        if (input) input.disabled = !allowed;
    }
    // Phase 1: local-only manual/OCR simulators have no safe rehydration contract.
    for (const id of ['form-internal-movement', 'form-purchase-reginfo', 'ocr-dropzone']) {
        const control = document.getElementById(id);
        if (control) { control.inert = true; control.hidden = true; }
    }
}

export function renderOperationalHeader(store, document) {
    const header = document.getElementById('user-header-info');
    const entity = document.getElementById('current-entity-label');
    const orgName = store.getActiveOrganizationName();
    if (entity) entity.innerText = `Organización: ${orgName}`;
    if (header) header.innerText = store.sessionUserId
        ? `${store.sessionEmail} · ${orgName} · ${store.effectiveProfileName || 'Permisos personalizados'}` : '';
}
