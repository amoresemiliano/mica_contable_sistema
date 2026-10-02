export async function saveClassificationControl(store, control, method, id, render, reportError) {
    const generation = store.contextGeneration, org = store.activeOrganizationId;
    const value = control.value;
    control.disabled = true;
    control.setAttribute('aria-busy', 'true');
    try { await store[method](id, value); }
    catch (error) {
        if (generation === store.contextGeneration && org === store.activeOrganizationId) reportError(error.message);
    } finally {
        control.removeAttribute('aria-busy');
        if (generation === store.contextGeneration && org === store.activeOrganizationId) render();
    }
}
