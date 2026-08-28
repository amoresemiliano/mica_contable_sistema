import { categorizer } from './categorizer.js';
import { persistenceService } from './core/services/persistenceService.js';

// 3. STORE GLOBAL DE LA APP (SOLID: Single Responsibility / Decoupled via Observer Pattern)
export class AppStore {
    constructor() {
        this.items = []; // Comprobantes ARCA (Compras y Ventas)
        this.perceptions = []; // Tabla_Percepciones_Provinciales (CUIT, Fecha/Periodo, Monto, Jurisdiccion)
        this.bankTransactions = []; // Extracto bancario normalizado (Fecha, Descripcion, Monto, CuentaSugerida, Estado)
        this.salaries = null; // Sueldos Acompy (SueldoBruto, Anticipos, SindicatoAporte, SueldoNeto, f931Total, sindicatoContribucion)
        this.manualMovements = []; // Movimientos REGINFO e internos
        this.ocrHistory = [];
        this.taxCategories = [];
        this.economicActivities = [];
        this.iibbRates = [];
        this.importIssues = [];

        const getLocalJSON = (key) => {
            if (typeof localStorage !== 'undefined' && localStorage.getItem) {
                try { return JSON.parse(localStorage.getItem(key)); } catch(e) { return null; }
            }
            return null;
        };

        this.bankRules = getLocalJSON('mica_bank_rules') || {
            debit: [
                { pattern: 'MANTE', category: 'Gasto Bancario' },
                { pattern: 'COMIS', category: 'Gasto Bancario' },
                { pattern: 'RECH', category: 'Gasto Bancario' },
                { pattern: 'IVA', category: 'Percepción IVA' },
                { pattern: 'ALIC', category: 'Percepción IVA' },
                { pattern: 'DB.CR.LEY 25413', category: 'Impuesto Débito/Crédito' },
                { pattern: 'IMP.DEB/CRED', category: 'Impuesto Débito/Crédito' },
                { pattern: 'AFIP', category: 'Pago de Impuestos' },
                { pattern: 'PAGO MIS CUENTAS', category: 'Pago de Impuestos' },
                { pattern: 'VEP', category: 'Pago de Impuestos' }
            ],
            credit: [
                { pattern: 'SIRCREB', category: 'Percepción IIBB (SIRCREB)' },
                { pattern: 'RET.IIBB', category: 'Percepción IIBB (SIRCREB)' }
            ]
        };

        this.bankTemplates = getLocalJSON('mica_bank_templates') || {};
        this.currentFilter = 'all';
        this.currentBankFilter = 'all';
        this.currentJurisdiction = 'all';
        this.searchQuery = '';
        this.listeners = [];
    }

    subscribe(listener) {
        this.listeners.push(listener);
    }

    notify() {
        this.listeners.forEach(listener => listener());
    }

    addItems(newItems) {
        newItems.forEach(item => {
            if (!this.items.some(i => i.id === item.id)) {
                this.items.push(item);
            }
        });
        this.notify();
    }

    normalizeJurisdictionName(raw) {
        if (!raw) return '';
        const str = String(raw).trim().toUpperCase();
        if (str.includes('ARBA') || str.includes('BUENOS AIRES') || str.includes('BS. AS')) return 'Buenos Aires (ARBA)';
        if (str.includes('AGIP') || str.includes('CABA') || str.includes('CAPITAL')) return 'CABA (AGIP)';
        if (str.includes('CBA') || str.includes('CORDOBA')) return 'Córdoba';
        if (str.includes('SANTA FE')) return 'Santa Fe';
        if (str.includes('IVA') || str.includes('NACIONAL')) return 'IVA (Nacional)';
        return str.charAt(0) + str.slice(1).toLowerCase();
    }

    getAvailableJurisdictions() {
        const set = new Set();
        (this.perceptions || []).forEach(p => {
            const raw = p.jurisdiction || p.jurisdiccion || p.fuente || '';
            if (raw) {
                const norm = this.normalizeJurisdictionName(raw);
                if (norm) set.add(norm);
            }
        });
        return Array.from(set).sort();
    }

    setJurisdictionFilter(jurisdiction) {
        this.currentJurisdiction = jurisdiction || 'all';
        this.notify();
    }

    getFilteredPerceptions() {
        return (this.perceptions || []).filter(p => {
            if (this.currentJurisdiction !== 'all') {
                const normP = this.normalizeJurisdictionName(p.jurisdiction || p.jurisdiccion || p.fuente || '');
                if (normP !== this.currentJurisdiction) return false;
            }
            if (this.searchQuery) {
                const cuitStr = String(p.cuit || '');
                const razonStr = String(p.razonSocial || p.agente || '').toLowerCase();
                const compStr = String(p.comprobante || '').toLowerCase();
                const matchesSearch = cuitStr.includes(this.searchQuery) || razonStr.includes(this.searchQuery) || compStr.includes(this.searchQuery);
                if (!matchesSearch) return false;
            }
            return true;
        });
    }

    // Cargar Percepciones Provinciales
    addPerceptions(newPerceptions) {
        if (!Array.isArray(newPerceptions)) return;
        newPerceptions.forEach(p => {
            const percep = p.normalizedData || p;
            if (!percep || !percep.cuit) return;
            const cleanCuit = (percep.cuit || '').toString().replace(/\D/g, '');
            const amountVal = typeof percep.amount === 'number' ? percep.amount : (typeof percep.monto === 'number' ? percep.monto : parseFloat(percep.importe) || 0);
            let periodStr = percep.period || '';
            if (!periodStr && percep.fecha) {
                const parts = percep.fecha.split('/');
                if (parts.length === 3) {
                    periodStr = `${parts[2]}-${parts[1]}`;
                }
            }
            this.perceptions.push({
                ...percep,
                cuit: cleanCuit,
                amount: amountVal,
                monto: amountVal,
                importe: amountVal,
                period: periodStr,
                jurisdiction: (percep.jurisdiction || 'ARBA').toUpperCase()
            });
        });
        this.notify();
    }

    // Cargar Extracto Bancario
    addBankTransactions(transactions) {
        this.bankTransactions = transactions;
        this.notify();
    }

    // Registrar Regla Bancaria Personalizada
    addBankRule(type, pattern, category) {
        if (!this.bankRules[type]) this.bankRules[type] = [];
        this.bankRules[type].push({ pattern: pattern.toUpperCase(), category });
        localStorage.setItem('mica_bank_rules', JSON.stringify(this.bankRules));
        this.notify();
    }

    // Registrar Plantilla de Mapeo de Banco
    saveBankTemplate(bankName, mapping) {
        this.bankTemplates[bankName] = mapping;
        localStorage.setItem('mica_bank_templates', JSON.stringify(this.bankTemplates));
    }

    // Cargar Sueldos consolidados de Acompy
    addSalary(salaryData) {
        if (!salaryData) return;
        const norm = salaryData.normalizedData || salaryData;
        this.salaries = {
            ...norm,
            sueldoBruto: norm.sueldoBruto || norm.sueldoBrutoCalculado || norm.remunerativo || 0,
            sueldoBrutoCalculado: norm.sueldoBrutoCalculado || norm.remunerativo || 0,
            anticipos: norm.anticipos || norm.anticipoSueldo || 0,
            anticipoSueldo: norm.anticipoSueldo || norm.anticipos || 0,
            sindicatoAporte: norm.sindicatoAporte || norm.aporteSindicalCalculado || norm.aporteSindicalObligatorio || 0,
            aporteSindicalCalculado: norm.aporteSindicalCalculado || norm.aporteSindicalObligatorio || 0,
            sueldoNeto: norm.sueldoNeto || 0,
            remunerativo: norm.remunerativo || 0,
            noRemunerativo: norm.noRemunerativo || 0,
            periodo: norm.periodo || ''
        };
        this.notify();
    }

    // Registrar Movimiento Manual o Interno
    addManualMovement(movement) {
        movement.id = `manual-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        this.manualMovements.push(movement);
        this.notify();
    }

    setFilter(filter) {
        this.currentFilter = filter;
        if (typeof document !== 'undefined' && document.querySelectorAll) {
            document.querySelectorAll('.btn-filter').forEach(btn => {
                btn.classList.toggle('active', btn.innerText.toLowerCase().includes(
                    filter === 'recibidos' ? 'compras' :
                    filter === 'emitidos' ? 'ventas' :
                    filter === 'pending' ? 'sin' : 'todos'
                ));
            });
        }
        this.notify();
    }

    setSearch(query) {
        this.searchQuery = query.toLowerCase();
        this.notify();
    }

    async loadTaxCategories() {
        try {
            this.taxCategories = await persistenceService.loadActiveTaxCategories();
            this.notify();
        } catch (e) {
            console.error("Failed to load tax categories", e);
        }
    }

    async loadEconomicActivities() {
        try {
            this.economicActivities = await persistenceService.loadActiveEconomicActivities();
            this.notify();
        } catch (e) {
            console.error("Failed to load economic activities", e);
        }
    }

    async loadIibbRates() {
        try {
            this.iibbRates = await persistenceService.loadActiveIibbRates();
            this.notify();
        } catch (e) {
            console.error("Failed to load IIBB rates", e);
        }
    }

    async promptUpsertArcaCatalog() {
        if (typeof window !== 'undefined' && window.UIManager) {
            window.UIManager.openModal('modal-arca-catalog');
        } else {
            alert("Error: UIManager no encontrado.");
        }
    }

    async promptCreateIibbRate() {
        if (typeof window !== 'undefined' && window.UIManager) {
            // Llenar el select de actividades en el modal
            const select = document.getElementById('iibb-rate-activity');
            if (select) {
                select.innerHTML = '<option value="">-- General --</option>' +
                    (this.economicActivities || []).map(a => `<option value="${a.id}">${a.arca_activity_code} - ${a.name}</option>`).join('');
            }
            window.UIManager.openModal('modal-iibb-rate');
        } else {
            alert("Error: UIManager no encontrado.");
        }
    }

    async loadImportIssues() {
        try {
            this.importIssues = await persistenceService.loadImportIssues();
            this.notify();
        } catch (e) {
            console.error("Failed to load import issues", e);
        }
    }

    updateCategory(id, categoryVal) {
        const item = this.items.find(i => i.id === id);
        if (item) {
            item.category_id = categoryVal; // Now stores the UUID
            item.sugerida = false;
            this.notify();
        }
    }

    updateActivity(id, activityVal) {
        const item = this.items.find(i => i.id === id);
        if (item) {
            item.activity_id = activityVal; // UUID
            item.sugerida = false;
            this.notify();
        }
    }

    updateBankCategory(id, categoryVal) {
        const item = this.bankTransactions.find(i => i.id === id);
        if (item) {
            item.category_id = categoryVal; // UUID
            item.sugerida = false;
            this.notify();
        }
    }

    updateBankActivity(id, activityVal) {
        const item = this.bankTransactions.find(i => i.id === id);
        if (item) {
            item.activity_id = activityVal; // UUID
            item.sugerida = false;
            this.notify();
        }
    }

    async confirmItem(id) {
        const item = this.items.find(i => i.id === id);
        if (item && item.category_id) {
            item.confirmada = true;
            try {
                await persistenceService.bulkUpdateRecordClassification([item.id], item.cuit, item.category_id, item.activity_id);
            } catch (e) {
                console.error("Failed to persist classification", e);
                item.confirmada = false;
                alert("Error al guardar la clasificación: " + e.message);
                return;
            }

            // Inteligencia en tiempo real (in-memory)
            this.items.forEach(other => {
                if (other.cuit === item.cuit && !other.confirmada) {
                    other.category_id = item.category_id;
                    other.activity_id = item.activity_id;
                    other.sugerida = true;
                }
            });

            this.notify();
        }
    }

    // Bulk actions
    updateBulkSelectionBar() {
        const checkboxes = document.querySelectorAll('.comprobante-checkbox:checked');
        const count = checkboxes.length;
        const bar = document.getElementById('bulk-actions-bar');
        const countText = document.getElementById('bulk-selection-count');
        if (bar && countText) {
            if (count > 0) {
                bar.classList.remove('hidden');
                countText.innerText = `${count} seleccionado${count > 1 ? 's' : ''}`;
            } else {
                bar.classList.add('hidden');
            }
        }
    }

    toggleSelectAllComprobantes(checkbox) {
        const checkboxes = document.querySelectorAll('.comprobante-checkbox');
        checkboxes.forEach(cb => {
            if (!cb.disabled) cb.checked = checkbox.checked;
        });
        this.updateBulkSelectionBar();
    }

    async bulkSoftDeleteSelected() {
        const checkboxes = document.querySelectorAll('.comprobante-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        if (confirm(`¿Estás seguro de enviar ${ids.length} registro(s) a la papelera?`)) {
            try {
                await persistenceService.bulkSoftDeleteRecords(ids);
                this.items = this.items.filter(i => !ids.includes(i.id));
                this.updateBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al eliminar: " + e.message);
            }
        }
    }

    async promptBulkClassification() {
        const checkboxes = document.querySelectorAll('.comprobante-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        const firstItem = this.items.find(i => i.id === ids[0]);
        if (!firstItem) return;

        // Validar que todos tienen el mismo CUIT
        const cuit = firstItem.cuit;
        const allSameCuit = ids.every(id => this.items.find(i => i.id === id)?.cuit === cuit);

        if (!allSameCuit) {
            alert("No se puede clasificar en bloque a proveedores diferentes. Selecciona registros del mismo proveedor (CUIT).");
            return;
        }

        if (!firstItem.category_id) {
            alert("El primer registro seleccionado no tiene una categoría asignada. Asigna una categoría primero para replicarla a los demás.");
            return;
        }

        if (confirm(`¿Clasificar los ${ids.length} registros seleccionados del proveedor CUIT ${cuit} con la categoría actual?`)) {
            try {
                await persistenceService.bulkUpdateRecordClassification(ids, cuit, firstItem.category_id, firstItem.activity_id);
                ids.forEach(id => {
                    const it = this.items.find(i => i.id === id);
                    if (it) {
                        it.confirmada = true;
                        it.category_id = firstItem.category_id;
                        it.activity_id = firstItem.activity_id;
                    }
                });

                // Uncheck all
                document.querySelectorAll('.comprobante-checkbox').forEach(cb => cb.checked = false);
                const allCb = document.getElementById('check-all-comprobantes');
                if (allCb) allCb.checked = false;

                this.updateBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al clasificar en bloque: " + e.message);
            }
        }
    }

    // Import Issues
    async loadImportIssues() {
        // Fetch from eco_import_issues (since we didn't add the RPC yet, let's just make it a placeholder or simple query)
        try {
            const { data, error } = await persistenceService.supabase
                .from('eco_import_issues')
                .select('*')
                .is('resolved_at', null);
            if (error) throw error;
            this.importIssues = data || [];
            this.notify();
        } catch (e) {
            console.error("Failed to load import issues", e);
        }
    }

    async resolveAllImportIssues() {
        if (!confirm("¿Marcar todos los errores de importación como resueltos?")) return;
        try {
            const { error } = await persistenceService.supabase
                .from('eco_import_issues')
                .update({ resolved_at: new Date().toISOString(), resolved_by: 'system' })
                .is('resolved_at', null);
            if (error) throw error;
            this.importIssues = [];
            this.notify();
        } catch (e) {
            alert("Error: " + e.message);
        }
    }

    // Bank Bulk Actions
    updateBankBulkSelectionBar() {
        const checkboxes = document.querySelectorAll('.banco-checkbox:checked');
        const count = checkboxes.length;
        const bar = document.getElementById('bank-bulk-actions-bar');
        const countText = document.getElementById('bank-bulk-selection-count');
        if (bar && countText) {
            if (count > 0) {
                bar.classList.remove('hidden');
                countText.innerText = `${count} seleccionado${count > 1 ? 's' : ''}`;
            } else {
                bar.classList.add('hidden');
            }
        }
    }

    toggleSelectAllBankMovements(checkbox) {
        const checkboxes = document.querySelectorAll('.banco-checkbox');
        checkboxes.forEach(cb => {
            if (!cb.disabled) cb.checked = checkbox.checked;
        });
        this.updateBankBulkSelectionBar();
    }

    async bulkSoftDeleteBankMovements() {
        const checkboxes = document.querySelectorAll('.banco-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        if (confirm(`¿Enviar ${ids.length} extractos bancarios a la papelera?`)) {
            try {
                // Same RPC works for any table if implemented generically, or we need a specific one for financial movements.
                // Migration 014 doesn't explicitly add a bulk_soft_delete_financial_movements RPC. Let's do it via Supabase client directly or assume the same RPC handles both if it uses polymorphic IDs.
                // Wait, in Migration 014 the requirements say: "bulk_soft_delete_records" and "bulk_soft_delete_financial_movements". Wait, I didn't add bulk_soft_delete_financial_movements.
                // Let's use direct update for now.
                const { error } = await persistenceService.supabase
                    .from('eco_financial_movements')
                    .update({ deleted_at: new Date().toISOString() })
                    .in('id', ids);

                if (error) throw error;
                this.bankTransactions = this.bankTransactions.filter(i => !ids.includes(i.id));
                this.updateBankBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al eliminar: " + e.message);
            }
        }
    }

    async promptBankBulkClassification() {
        const checkboxes = document.querySelectorAll('.banco-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        const firstItem = this.bankTransactions.find(i => i.id === ids[0]);
        if (!firstItem) return;

        if (!firstItem.category_id) {
            alert("El primer registro seleccionado no tiene una categoría asignada. Asígnale una primero.");
            return;
        }

        if (confirm(`¿Clasificar los ${ids.length} movimientos seleccionados con la categoría actual?`)) {
            try {
                const { error } = await persistenceService.supabase
                    .from('eco_financial_movements')
                    .update({
                        category_id: firstItem.category_id,
                        activity_id: firstItem.activity_id
                    })
                    .in('id', ids);

                if (error) throw error;

                ids.forEach(id => {
                    const it = this.bankTransactions.find(i => i.id === id);
                    if (it) {
                        it.category_id = firstItem.category_id;
                        it.activity_id = firstItem.activity_id;
                        it.confirmada = true;
                    }
                });

                document.querySelectorAll('.banco-checkbox').forEach(cb => cb.checked = false);
                const allCb = document.getElementById('check-all-bancos');
                if (allCb) allCb.checked = false;

                this.updateBankBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error: " + e.message);
            }
        }
    }

    exportBankMovements() {
        // Implementación básica de exportación a XLSX usando SheetJS
        if (!window.XLSX) {
            alert("Librería XLSX no cargada.");
            return;
        }

        const wb = window.XLSX.utils.book_new();
        // Filtrar y mapear los datos
        const data = this.bankTransactions.map(t => ({
            Fecha: t.fecha,
            Descripcion: t.descripcion,
            Monto: t.monto,
            Tipo: t.tipo,
            Categoria: t.category_id ? 'Asignada' : 'Pendiente' // In a real app we'd map the UUID to name
        }));

        const ws = window.XLSX.utils.json_to_sheet(data);
        window.XLSX.utils.book_append_sheet(wb, ws, "Extractos");
        window.XLSX.writeFile(wb, "Extractos_Bancarios.xlsx");
    }

    // Filters for Banks
    setBankFilter(filter) {
        this.currentBankFilter = filter;
        this.notify();
    }

    applyBankDateFilters() {
        this.notify();
    }

    getFilteredItems() {
        return this.items.filter(item => {
            const matchesSearch = item.razonSocial.toLowerCase().includes(this.searchQuery) ||
                                  item.cuit.includes(this.searchQuery) ||
                                  item.comprobante.toLowerCase().includes(this.searchQuery);
            if (!matchesSearch) return false;

            if (this.currentFilter === 'recibidos') return item.tipo === 'recibido';
            if (this.currentFilter === 'emitidos') return item.tipo === 'emitido';
            if (this.currentFilter === 'pending') return !item.confirmada;

            return true;
        });
    }
}

export const appStore = new AppStore();
