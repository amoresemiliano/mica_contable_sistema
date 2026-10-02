import { permissionByCode, PERMISSION_GROUPS } from './micaPermissionContract.js';
export function capabilityPresentation(capability) {
    const entry = permissionByCode(capability.code);
    return entry ? { ...entry, group: PERMISSION_GROUPS[entry.group] } :
        { label: 'Permiso no disponible en MICA', description: '', group: 'No disponible', order: Infinity };
}
