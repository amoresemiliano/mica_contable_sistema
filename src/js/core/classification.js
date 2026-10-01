// Typed database columns are authoritative; payload labels and suggestions are not grants or saves.
export function persistedClassification(row) {
    return {
        category_id: row.category_id || null,
        activity_id: row.activity_id || null,
        confirmada: !!row.category_id,
        sugerida: false
    };
}

export function unresolvedPurchases(items) {
    return items.filter(i => (i.tipo === 'recibido' || i.type === 'recibido') &&
        (i.saldoAExplicar > 0 || !i.category_id)).length;
}

export function purchaseCategoryTotals(items, categories) {
    const totals = new Map();
    for (const row of items.filter(i => i.tipo === 'recibido')) {
        const id = row.category_id || null;
        const group = totals.get(id) || { id, label: id ?
            categories.find(c => c.id === id)?.name || 'Categoría asignada (no disponible)' : 'Sin Categorizar', amount: 0 };
        group.amount += Number(row.total) || 0;
        totals.set(id, group);
    }
    return [...totals.values()];
}
