// Demand loading keeps Configuration/catalogs free of operational record downloads.
export function requestOperationalData(store, document, moduleId) {
    if (!moduleId || !store.deferOperationalData || !store.canVisitModule(moduleId)) return;
    store.ensureOperationalData(moduleId);
    const section = document.getElementById(moduleId);
    if (!section?.prepend) return;
    let status = document.getElementById(`data-status-${moduleId}`);
    if (!status) {
        status = document.createElement('div'); status.id = `data-status-${moduleId}`;
        status.className = 'operational-data-status'; status.setAttribute('role','status'); section.prepend(status);
    }
    const state = store.operationalDataStatus(moduleId);
    status.replaceChildren(); status.hidden = !state.loading && !state.error;
    if (state.loading) status.textContent = 'Cargando registros de esta organización…';
    else if (state.error) {
        const message = document.createElement('span'); message.textContent = state.error;
        const retry = document.createElement('button'); retry.type = 'button'; retry.textContent = 'Reintentar';
        retry.onclick = () => store.ensureOperationalData(moduleId,{retry:true}); status.append(message,retry);
    }
}
