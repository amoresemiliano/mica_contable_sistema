import { MICA_PERMISSION_CATALOG } from './micaPermissionContract.js';
// Product boundary only. A proposal is never authority, even if received from a stale server.
export const MICA_PLATFORM_CAPABILITIES = Object.freeze(MICA_PERMISSION_CATALOG.filter(c => c.scope === 'PLATFORM' && c.status !== 'PROPOSED').map(c => c.code));
export const MICA_ORGANIZATION_CAPABILITIES = Object.freeze(MICA_PERMISSION_CATALOG.filter(c => c.scope === 'ORGANIZATION' && c.status !== 'PROPOSED').map(c => c.code));
export function isMicaCapability(code, scope) {
    return (scope === 'PLATFORM' ? MICA_PLATFORM_CAPABILITIES : scope === 'ORGANIZATION' ? MICA_ORGANIZATION_CAPABILITIES : []).includes(code);
}
