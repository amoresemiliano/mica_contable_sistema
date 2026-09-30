import { supabase } from './supabaseClient.js';
import { permissionByCode } from '../micaPermissionContract.js';

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

export function editableCapabilities(rows, scope, target = 'STANDARD') {
    return rows.filter(c => {
        const entry = permissionByCode(c.code);
        return entry?.scope === scope && c.scope === scope && entry.assignable && entry.visibleInEditor &&
            entry.delegationTargets.includes(target) && c.delegation_class !== 'OWNER_RESERVED' && c.is_active !== false;
    }).sort((a,b) => permissionByCode(a.code).order - permissionByCode(b.code).order);
}
// Server denies and grants remain authoritative. Preview describes the selected assignment,
// not permission to execute an action outside a confirmed active tenant context.
export function permissionPreview({ inherited = false, overrides = [], active = true }) {
    const effect = overrides.includes('DENY') ? 'DENY' : overrides.includes('ALLOW') ? 'ALLOW' : 'INHERITED';
    return { inherited, effect, effective: active && effect !== 'DENY' && (effect === 'ALLOW' || inherited) };
}

// Read-only explanation of the snapshot. Execution always uses server authorization.
export function assignmentPermissionPreview(data, userId, orgId, capability) {
    const user = data.users.find(u => u.id === userId);
    const platform = data.platform_roles.find(r => r.user_profile_id === userId);
    const platformPreset = data.presets.find(p => p.id === platform?.role_template_id);
    const platformActive = !!platform?.is_active && !!platformPreset?.is_active;
    const effects = data.overrides.filter(o => o.user_profile_id === userId && o.capability === capability.code);
    if (capability.scope === 'PLATFORM') return permissionPreview({
        inherited: platformActive && platformPreset.capabilities.includes(capability.code),
        overrides: effects.filter(o => o.kind === 'platform').map(o => o.effect),
        active: !!user?.is_active && !user.pending
    });
    const member = data.memberships.find(m => m.user_profile_id === userId && m.organization_id === orgId && m.is_active);
    const memberPreset = data.presets.find(p => p.id === member?.role_template_id);
    const scoped = platformActive && data.scopes.some(s => s.user_profile_id === userId && s.organization_id === orgId && s.is_active);
    const orgEffects = effects.filter(o => o.organization_id === orgId);
    const memberEffects = member ? orgEffects.filter(o => o.kind === 'membership').map(o => o.effect) : [];
    const platformEffects = platformActive ? orgEffects.filter(o => o.kind === 'platform_org').map(o => o.effect) : [];
    const inherited = (!!memberPreset?.is_active && memberPreset.capabilities.includes(capability.code)) ||
        (platformActive && (!!member || scoped) && platformPreset.bridge.includes(capability.code));
    // A platform DENY applies even after its scope is revoked; an ALLOW requires scope.
    const overrides = [...memberEffects, ...platformEffects.filter(e => e === 'DENY' || scoped)];
    const active = !!user?.is_active && !user.pending && !!orgId &&
        data.organizations.some(o => o.id === orgId && o.is_active) &&
        data.contexts?.some(c => c.user_profile_id === userId && c.organization_id === orgId) && (!!member || scoped);
    const unknownPreset = (member && !memberPreset) || (platform?.is_active && !platformPreset);
    return { ...permissionPreview({ inherited, overrides, active: !!active }), unknown: !!unknownPreset };
}
