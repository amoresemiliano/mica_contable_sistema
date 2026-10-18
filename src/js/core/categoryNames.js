// Keep aligned with public.mica_category_name_key introduced by migration 048.
export const cleanCategoryName = value => String(value ?? '').replace(/\s+/g,' ').trim();
export function categoryNameKey(value) {
    return cleanCategoryName(String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'')).toLowerCase();
}
export const equivalentCategory = (row,name,type) => row.category_type===type && categoryNameKey(row.name)===categoryNameKey(name);
export const duplicateCategoryMessage = 'Esta categoría ya existe en el catálogo global.';
