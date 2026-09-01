/**
 * Reusable Operational Grid System Controller
 * Handles sorting, filtering, period filtering, search, column visibility, and row selection.
 */
export class OperationalGrid {
    constructor({ moduleId, defaultColumns = [], searchFields = [], dateField = 'fecha', amountField = 'total' }) {
        this.moduleId = moduleId; // 'comprobantes', 'percepciones', 'extractos'
        this.defaultColumns = defaultColumns; // ['fecha', 'comprobante', ...]
        this.searchFields = searchFields;
        this.dateField = dateField;
        this.amountField = amountField;

        this.searchQuery = '';
        this.dateMode = 'month'; // 'month' o 'custom'
        this.periodFilter = ''; // 'YYYY-MM'
        this.startDate = ''; // 'YYYY-MM-DD'
        this.endDate = ''; // 'YYYY-MM-DD'
        this.primaryFilter = 'all'; // 'all', 'emitidos', 'recibidos', 'pending', 'debitos', 'creditos', or jurisdiction name
        
        this.sortColumn = null;
        this.sortDirection = null; // 'asc', 'desc', null

        this.selectedRowIds = new Set();

        this.visibleColumns = this.loadColumnPreferences();
    }

    // --- Persistencia de Columnas ---
    loadColumnPreferences() {
        try {
            if (typeof localStorage !== 'undefined') {
                const stored = localStorage.getItem(`mica_view_columns_${this.moduleId}`);
                if (stored) {
                    const parsed = JSON.parse(stored);
                    if (Array.isArray(parsed) && parsed.length > 0) {
                        return new Set(parsed);
                    }
                }
            }
        } catch (e) {
            console.warn(`Error al cargar columnas para ${this.moduleId}`, e);
        }
        return new Set(this.defaultColumns);
    }

    saveColumnPreferences() {
        try {
            if (typeof localStorage !== 'undefined') {
                localStorage.setItem(
                    `mica_view_columns_${this.moduleId}`,
                    JSON.stringify(Array.from(this.visibleColumns))
                );
            }
        } catch (e) {
            console.warn(`Error al guardar columnas para ${this.moduleId}`, e);
        }
    }

    toggleColumnVisibility(columnKey) {
        if (this.visibleColumns.has(columnKey)) {
            this.visibleColumns.delete(columnKey);
        } else {
            this.visibleColumns.add(columnKey);
        }
        this.saveColumnPreferences();
    }

    resetColumns() {
        this.visibleColumns = new Set(this.defaultColumns);
        this.saveColumnPreferences();
    }

    isColumnVisible(columnKey) {
        return this.visibleColumns.has(columnKey);
    }

    // --- Búsqueda ---
    setSearch(query) {
        this.searchQuery = (query || '').toLowerCase().trim();
    }

    clearSearch() {
        this.searchQuery = '';
    }

    // --- Período y Rango de Fechas ---
    setDateMode(mode) {
        this.dateMode = mode === 'custom' ? 'custom' : 'month';
    }

    setPeriod(periodStr) {
        this.dateMode = 'month';
        this.periodFilter = periodStr || ''; // 'YYYY-MM'
    }

    setCustomRange(startStr, endStr) {
        this.dateMode = 'custom';
        this.startDate = startStr || '';
        this.endDate = endStr || '';
    }

    clearPeriod() {
        this.periodFilter = '';
        this.startDate = '';
        this.endDate = '';
    }

    // --- Filtro Principal ---
    setPrimaryFilter(filterVal) {
        this.primaryFilter = filterVal || 'all';
    }

    // --- Ordenamiento ---
    toggleSort(columnKey, dataType = 'text') {
        if (this.sortColumn !== columnKey) {
            this.sortColumn = columnKey;
            this.sortDirection = 'asc';
            this.sortDataType = dataType;
        } else if (this.sortDirection === 'asc') {
            this.sortDirection = 'desc';
        } else {
            this.sortColumn = null;
            this.sortDirection = null;
            this.sortDataType = 'text';
        }
    }

    // --- Selección de Filas Visibles ---
    toggleSelectAllVisible(visibleItems) {
        const visibleIds = visibleItems.map(item => item.id).filter(Boolean);
        const allSelected = visibleIds.every(id => this.selectedRowIds.has(id));

        if (allSelected) {
            visibleIds.forEach(id => this.selectedRowIds.delete(id));
        } else {
            visibleIds.forEach(id => this.selectedRowIds.add(id));
        }
    }

    toggleRowSelection(itemId) {
        if (this.selectedRowIds.has(itemId)) {
            this.selectedRowIds.delete(itemId);
        } else {
            this.selectedRowIds.add(itemId);
        }
    }

    clearSelection() {
        this.selectedRowIds.clear();
    }

    // --- Procesamiento de Colección (Filtrar + Ordenar) ---
    filterAndSort(items, customFieldExtractor = {}) {
        if (!Array.isArray(items)) return [];

        let filtered = items.filter(item => {
            // 1. Filtro por búsqueda
            if (this.searchQuery) {
                const matches = this.searchFields.some(field => {
                    const rawVal = customFieldExtractor[field] ? customFieldExtractor[field](item) : item[field];
                    if (rawVal === undefined || rawVal === null) return false;
                    const strVal = String(rawVal).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
                    const cleanQuery = this.searchQuery.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
                    return strVal.includes(cleanQuery);
                });
                if (!matches) return false;
            }

            // 2. Filtro por Fecha (Modo Mes YYYY-MM o Rango Personalizado YYYY-MM-DD)
            const rawDate = customFieldExtractor[this.dateField] ? customFieldExtractor[this.dateField](item) : item[this.dateField];
            if (rawDate) {
                let isoDate = '';
                if (rawDate.includes('-')) {
                    isoDate = rawDate.substring(0, 10);
                } else if (rawDate.includes('/')) {
                    const parts = rawDate.split('/');
                    if (parts.length === 3) {
                        isoDate = `${parts[2]}-${parts[1].padStart(2, '0')}-${parts[0].padStart(2, '0')}`;
                    }
                }

                if (this.dateMode === 'custom') {
                    if (this.startDate && isoDate < this.startDate) return false;
                    if (this.endDate && isoDate > this.endDate) return false;
                } else if (this.periodFilter) {
                    const ym = isoDate ? isoDate.substring(0, 7) : '';
                    if (ym && ym !== this.periodFilter) return false;
                }
            } else if (this.periodFilter || (this.dateMode === 'custom' && (this.startDate || this.endDate))) {
                return false;
            }

            // 3. Filtro Principal
            if (this.primaryFilter && this.primaryFilter !== 'all') {
                if (this.primaryFilter === 'emitidos') {
                    if (item.tipo !== 'emitido' && item.type !== 'emitido') return false;
                } else if (this.primaryFilter === 'recibidos') {
                    if (item.tipo !== 'recibido' && item.type !== 'recibido') return false;
                } else if (this.primaryFilter === 'pending' || this.primaryFilter === 'uncategorized') {
                    if (item.confirmada || item.category_id || (item.categoria && item.categoria !== 'Sin Categorizar')) {
                        return false;
                    }
                } else if (this.primaryFilter === 'debitos') {
                    const amount = item.importe !== undefined ? item.importe : item.total;
                    if (amount >= 0 && item.tipo !== 'DEBITO') return false;
                } else if (this.primaryFilter === 'creditos') {
                    const amount = item.importe !== undefined ? item.importe : item.total;
                    if (amount < 0 && item.tipo !== 'CREDITO') return false;
                } else {
                    // Para Percepciones, filtro por Origen/Jurisdicción
                    const origen = item.fuente || item.jurisdiction || item.origen || '';
                    if (origen.toLowerCase() !== this.primaryFilter.toLowerCase()) return false;
                }
            }

            return true;
        });

        // 4. Ordenamiento
        if (this.sortColumn && this.sortDirection) {
            const col = this.sortColumn;
            const dir = this.sortDirection === 'asc' ? 1 : -1;
            const type = this.sortDataType || 'text';

            filtered.sort((a, b) => {
                let valA = customFieldExtractor[col] ? customFieldExtractor[col](a) : a[col];
                let valB = customFieldExtractor[col] ? customFieldExtractor[col](b) : b[col];

                if (valA === undefined || valA === null) valA = '';
                if (valB === undefined || valB === null) valB = '';

                if (type === 'numeric' || type === 'currency') {
                    const numA = typeof valA === 'number' ? valA : parseFloat(String(valA).replace(/[^0-9.-]+/g, "")) || 0;
                    const numB = typeof valB === 'number' ? valB : parseFloat(String(valB).replace(/[^0-9.-]+/g, "")) || 0;
                    return (numA - numB) * dir;
                } else if (type === 'date') {
                    const dateA = new Date(valA).getTime() || 0;
                    const dateB = new Date(valB).getTime() || 0;
                    return (dateA - dateB) * dir;
                } else {
                    return String(valA).localeCompare(String(valB), 'es', { sensitivity: 'base' }) * dir;
                }
            });
        }

        return filtered;
    }
}
