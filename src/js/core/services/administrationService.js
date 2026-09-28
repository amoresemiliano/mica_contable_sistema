import { supabase } from './supabaseClient.js';
import { isMicaCapability } from '../micaCapabilities.js';

export function createAdministrationService(client = supabase) {
    async function rpc(name, args) {
        const { data, error } = await client.rpc(name, args);
        if (error) throw new Error(error.message || 'No se pudo completar la operación.');
        return data;
    }
    return {
        read: (org = null, search = '') => rpc('mica_admin_read', { p_org: org, p_search: search }),
        apply: (action, data) => rpc('mica_admin_apply', { p_action: action, p_data: data })
    };
}
export const administrationService = createAdministrationService();

export function editableCapabilities(rows, scope) {
    const reserved = ['PLATFORM_MANAGE', 'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'ACCESS_ANY_ORG',
        'SUPPORT_IMPERSONATE', 'HARD_DELETE_EXCEPTIONAL', 'ORGANIZATION_CREATE', 'ORGANIZATION_ARCHIVE',
        'PLATFORM_MIGRATIONS_APPLY', 'PLATFORM_TENANTS_PROVISION', 'PLATFORM_SYSTEM_MONITOR'];
    return rows.filter(c => c.scope === scope && isMicaCapability(c.code, scope) &&
        !reserved.includes(c.code) && c.delegation_class !== 'OWNER_RESERVED');
}
// Server denies and grants remain authoritative. Preview describes the selected assignment,
// not permission to execute an action outside a confirmed active tenant context.
export function permissionPreview({ inherited = false, overrides = [], active = true }) {
    const effect = overrides.includes('DENY') ? 'DENY' : overrides.includes('ALLOW') ? 'ALLOW' : 'INHERITED';
    return { inherited, effect, effective: active && effect !== 'DENY' && (effect === 'ALLOW' || inherited) };
}
