export function renderGridPagination(grid, rows, tbody, render, document = globalThis.document) {
    const result = grid.paginate(rows);
    if (!tbody?.closest) return result.rows;
    const table = tbody.closest('table');
    if (!table) return result.rows;
    // Rows are recreated on render; discard the old page's bulk-action state too.
    for (const checkbox of table.querySelectorAll?.('thead input[type="checkbox"]') || []) {
        checkbox.checked = false; checkbox.indeterminate = false;
    }
    const bulkBar = { comprobantes: 'bulk-actions-bar', percepciones: 'percepciones-bulk-actions-bar',
        extractos: 'bank-bulk-actions-bar' }[grid.moduleId];
    if (bulkBar) document.getElementById(bulkBar)?.classList.add('hidden');
    let controls = document.getElementById(`pagination-${grid.moduleId}`);
    if (!controls) {
        controls = document.createElement('nav'); controls.id = `pagination-${grid.moduleId}`;
        controls.className = 'grid-pagination'; controls.setAttribute('aria-label', 'Paginación');
        table.after(controls);
    }
    controls.replaceChildren();
    const prev = document.createElement('button'), next = document.createElement('button');
    prev.type = next.type = 'button'; prev.textContent = 'Anterior'; next.textContent = 'Siguiente';
    prev.disabled = result.page === 1; next.disabled = result.page === result.pages;
    prev.onclick = () => { grid.setPage(result.page - 1); render(); };
    next.onclick = () => { grid.setPage(result.page + 1); render(); };
    const label = document.createElement('span');
    label.textContent = `Página ${result.page} / ${result.pages} · ${result.total} registros`;
    const size = document.createElement('select'); size.setAttribute('aria-label', 'Filas por página');
    for (const value of [25,50,100]) {
        const option = document.createElement('option'); option.value = String(value); option.textContent = String(value); size.append(option);
    }
    size.value = String(result.pageSize);
    size.onchange = () => { grid.setPageSize(size.value); render(); };
    controls.append(prev,label,next,size);
    return result.rows;
}
