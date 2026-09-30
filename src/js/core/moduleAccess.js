// MICA module boundary. Effective server capabilities are the only authority.
import { MICA_MODULE_CONTRACT, MICA_IMPORT_CONTRACT, MICA_OCR_ACTIONS, MICA_ACTION_CONTRACT } from './micaPermissionContract.js';
export const MODULES = Object.freeze(Object.fromEntries(Object.entries(MICA_MODULE_CONTRACT).map(([id,entry])=>[id,entry.any])));
export function tenantCan(store, code) {
    return store.contextState === 'TENANT_READY' && !!store.activeOrganizationId &&
        store.hasCapability(code, { scope: 'ORGANIZATION', orgId: store.activeOrganizationId });
}
export function canVisitModule(store, id) {
    if (!['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState)) return false;
    if (id === 'tab-access') return true;
    if (id === 'tab-configuracion') return ['ORGANIZATION_CREATE', 'ORGANIZATION_UPDATE', 'ORGANIZATION_ARCHIVE',
        'GLOBAL_USER_MANAGE', 'PLATFORM_MANAGE', 'MICA_ADMIN_MANAGE'].some(c => store.hasCapability(c)) ||
        ['ORG_MEMBER_VIEW', 'ORG_MEMBER_MANAGE', 'ORG_MEMBER_PERMISSION_MANAGE'].some(c => tenantCan(store, c));
    if (id === 'tab-categorizacion' && !store.activeOrganizationId)
        return ['GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE', 'CATALOG_ASSIGN_ANY_ORG'].some(c => store.hasCapability(c));
    return (MODULES[id] || []).some(c => tenantCan(store, c));
}
export function canImport(store, type) {
    const rule = MICA_IMPORT_CONTRACT[type];
    return !!rule?.enabled && rule.all.every(code => tenantCan(store, code));
}
export function canOcr(store, action) {
    const code = MICA_OCR_ACTIONS[action];
    return !!code && tenantCan(store, code);
}
export function canOperationalAction(store, action) {
    const rule = MICA_ACTION_CONTRACT[action];
    return !!rule?.enabled && rule.all.every(code => tenantCan(store,code)) &&
        (rule.platformAll || []).every(code => store.hasCapability(code, {scope:'PLATFORM'}));
}
export function pruneDeniedDatasets(store) {
    // Pending switches retain the previously confirmed state until the server accepts.
    if (!['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState)) return;
    const clear = keys => { for (const key of keys) store[key] = []; };
    if (!tenantCan(store, 'RECORD_VIEW')) {
        store.clearOperationalDataCache?.();
        if (store.items.length || store.perceptions.length || store.bankTransactions.length || store.salariesList.length)
            for (const reset of store.tenantResetListeners || []) reset();
        clear(['items','perceptions','bankTransactions','salariesList','manualMovements']);
        store.salaries = null;
        store.currentFilter = store.currentBankFilter = store.currentJurisdiction = 'all';
        store.searchQuery = '';
    }
    if (!tenantCan(store, 'IMPORT_VIEW')) clear(['importIssues']);
    if (!tenantCan(store, 'ORG_VIEW') && !store.isCatalogPlatformContext())
        clear(['taxCategories','economicActivities','displayedEconomicActivities']);
    if (!tenantCan(store, 'CATALOG_ORG_VIEW')) clear(['iibbRates']);
    if (!Object.keys(MICA_OCR_ACTIONS).some(action => canOcr(store, action))) clear(['ocrHistory']);
}
export function renderModuleAccess(store, document, navigate) {
    for (const link of document.querySelectorAll('[onclick*="switchTab("], [data-tab]')) {
        const id = link.dataset?.tab || link.getAttribute('onclick')?.match(/switchTab\(['"]([^'"]+)['"]/ )?.[1];
        if (!id) continue;
        const caption = link.querySelector?.('.nav-text, .sheet-text strong');
        if (caption && MICA_MODULE_CONTRACT[id]) caption.textContent = MICA_MODULE_CONTRACT[id].label;
        const allowed = canVisitModule(store, id);
        link.hidden = !allowed; link.setAttribute('aria-disabled', String(!allowed));
    }
    const active = document.querySelector('.tab-content:not(.hidden)');
    if (['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState) && (!active || !canVisitModule(store, active.id))) {
        const target = [...Object.keys(MODULES), 'tab-configuracion', 'tab-access'].find(id => canVisitModule(store,id));
        navigate(target);
    }
    for (const section of document.querySelectorAll('.tab-content')) {
        if (!canVisitModule(store, section.id)) {
            // Keep the context/retry toolbar usable while loading or after an error.
            // The selector component separately blocks the module body in those states.
            section.inert = ['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState);
            if (['TENANT_READY', 'PLATFORM_READY'].includes(store.contextState)) section.classList.add('hidden');
        } else section.inert = false;
    }
}
