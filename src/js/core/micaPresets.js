import { MICA_PRESET_DEFINITIONS, presetCapabilities } from './micaPermissionContract.js';
export const MICA_TENANT_PRESETS = Object.freeze(Object.fromEntries(Object.entries(MICA_PRESET_DEFINITIONS)
    .filter(([,p]) => p.scope === 'ORGANIZATION').map(([code]) => [code,Object.freeze(presetCapabilities(code,'ORGANIZATION'))])));
export const MICA_ACCOUNTING_PLATFORM = Object.freeze(presetCapabilities('ACCOUNTING_SUPERADMIN','PLATFORM'));
