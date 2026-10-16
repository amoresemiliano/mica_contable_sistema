import { categoryNameKey } from './categoryNames.js';

export function classificationValues(store, row) {
    const category = store.taxCategories?.find(c => c.id === row.category_id);
    const activity = store.economicActivities?.find(a => a.id === row.activity_id);
    return {
        categoria: category?.name || row.categoria || '',
        actividad: activity ? `${activity.arca_code || activity.arca_activity_code || ''} - ${activity.name}` : '',
        estado: row.confirmada ? 'Categorizado' : 'Pendiente'
    };
}
export function semanticExtractors(store, base = {}) {
    return {...base, cuenta:row=>classificationValues(store,row).categoria, origen:row=>row.tipo==='recibido'?'Compra':'Venta',neto:row=>row.netoGravado || 0,exentas:row=>row.exento || 0,
        percIva:row=>row.percepcionIva || 0,percIibb:row=>row.percepcionIibb || 0,
        ...Object.fromEntries(['categoria','actividad','estado'].map(key =>
        [key, row => classificationValues(store,row)[key]]))};
}
// Identity deduplication only. Similar names with different IDs are distinct definitions.
export function canonicalCatalog(rows) {
    return [...new Map((rows || []).map(row => [row.id,row])).values()];
}
export function duplicateDefinitions(rows) {
    const groups = new Map();
    for (const row of canonicalCatalog(rows)) {
        const key = `${row.category_type}|${categoryNameKey(row.name)}`;
        if (!groups.has(key)) groups.set(key,[]);
        groups.get(key).push(row.id);
    }
    return [...groups.values()].filter(ids => ids.length > 1);
}
