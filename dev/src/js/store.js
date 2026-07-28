import { categorizer } from './categorizer.js';

// 3. STORE GLOBAL DE LA APP (SOLID: Single Responsibility / Decoupled via Observer Pattern)
export class AppStore {
    constructor() {
        this.items = []; // Comprobantes ARCA (Compras y Ventas)
        this.perceptions = []; // Tabla_Percepciones_Provinciales (CUIT, Fecha/Periodo, Monto, Jurisdiccion)
        this.bankTransactions = []; // Extracto bancario normalizado (Fecha, Descripcion, Monto, CuentaSugerida, Estado)
        this.salaries = null; // Sueldos Acompy (SueldoBruto, Anticipos, SindicatoAporte, SueldoNeto, f931Total, sindicatoContribucion)
        this.manualMovements = []; // Movimientos REGINFO e internos
        this.ocrHistory = [];
        
        // Motor de Keywords Bancarias cargado en LocalStorage o por defecto
        this.bankRules = JSON.parse(localStorage.getItem('mica_bank_rules')) || {
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

        this.bankTemplates = JSON.parse(localStorage.getItem('mica_bank_templates')) || {};
        this.currentFilter = 'all';
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

    // Cargar Percepciones Provinciales
    addPerceptions(newPerceptions) {
        newPerceptions.forEach(percep => {
            // Normalizar CUIT (limpiar guiones y espacios)
            percep.cuit = percep.cuit.toString().replace(/\D/g, '');
            this.perceptions.push(percep);
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
        this.salaries = salaryData;
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
        document.querySelectorAll('.btn-filter').forEach(btn => {
            btn.classList.toggle('active', btn.innerText.toLowerCase().includes(
                filter === 'recibidos' ? 'compras' : 
                filter === 'emitidos' ? 'ventas' : 
                filter === 'pending' ? 'sin' : 'todos'
            ));
        });
        this.notify();
    }

    setSearch(query) {
        this.searchQuery = query.toLowerCase();
        this.notify();
    }

    updateCategory(id, categoryVal) {
        const item = this.items.find(i => i.id === id);
        if (item) {
            item.categoria = categoryVal;
            item.sugerida = false;
            this.notify();
        }
    }

    confirmItem(id) {
        const item = this.items.find(i => i.id === id);
        if (item && item.categoria) {
            item.confirmada = true;
            categorizer.saveMapping(item.cuit, item.categoria);
            
            // Inteligencia en tiempo real
            this.items.forEach(other => {
                if (other.cuit === item.cuit && !other.confirmada) {
                    other.categoria = item.categoria;
                    other.sugerida = true;
                }
            });

            this.notify();
        }
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
