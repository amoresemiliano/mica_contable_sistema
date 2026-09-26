import { categorizer } from './categorizer.js';
import { persistenceService } from './core/services/persistenceService.js';

// 3. STORE GLOBAL DE LA APP (SOLID: Single Responsibility / Decoupled via Observer Pattern)
export class AppStore {
    constructor() {
        this.items = []; // Comprobantes ARCA (Compras y Ventas)
        this.perceptions = []; // Tabla_Percepciones_Provinciales (CUIT, Fecha/Periodo, Monto, Jurisdiccion)
        this.bankTransactions = []; // Extracto bancario normalizado (Fecha, Descripcion, Monto, CuentaSugerida, Estado)
        this.salaries = null; // Sueldos Acompy (SueldoBruto, Anticipos, SindicatoAporte, SueldoNeto, f931Total, sindicatoContribucion)
        this.salariesList = []; // Vector de sueldos por período
        this.manualMovements = []; // Movimientos REGINFO e internos
        this.ocrHistory = [];
        this.taxCategories = [];
        this.economicActivities = []; // Actividades asignadas a la organización
        this.globalEconomicActivities = []; // Catálogo global ARCA (F883)
        this.displayedEconomicActivities = []; // Lista mostrada según rol (global para SUPERADMIN, org para usuario)
        this.iibbRates = [];
        this.importIssues = [];
        const savedRole = (typeof sessionStorage !== 'undefined' && sessionStorage.getItem('mica_user_role')) || 'USER';
        this.currentUserRole = savedRole; // 'SUPERADMIN', 'ADMIN', 'REVIEWER', 'UPLOADER', 'USER'
        
        const savedOrgId = (typeof sessionStorage !== 'undefined' && sessionStorage.getItem('mica_active_org_id')) || null;
        this.activeOrganizationId = savedOrgId; // null para GLOBAL MICA MODE, o UUID de DEMO NORTE / SUR / OESTE
        
        this.organizations = [];
        this.operationalOrgTargets = [];
        this.contextState = 'SIGNED_OUT';
        this.contextError = '';
        this.contextGeneration = 0;
        this.sessionUserId = null;
        this.sessionEmail = '';
        this.effectiveProfileName = '';
        this.confirmedOrganizationName = '';
        this.tenantResetListeners = [];
        this.resetCatalogCapabilities();

        this.bankRules = {
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

        this.bankTemplates = {};
        this.defaultBankRules = { debit: this.bankRules.debit.slice(), credit: this.bankRules.credit.slice() };
        this.currentFilter = 'all';
        this.currentBankFilter = 'all';
        this.currentJurisdiction = 'all';
        this.searchQuery = '';
        this.listeners = [];
        this.pendingOperations = 0;
        // Keep the whole operation (including follow-up reloads) inside the switch barrier.
        for (const name of ['confirmItem', 'bulkSoftDeleteSelected', 'promptBulkClassification',
            'bulkSoftDeleteSelectedPercepciones', 'bulkSoftDeleteBankMovements', 'promptBankBulkClassification',
            'setTaxCategoriesActive', 'setEconomicActivitiesActive', 'createTaxCategory', 'updateTaxCategory',
            'assignTaxCategoryToOrg', 'bulkAssignTaxCategories', 'unassignTaxCategoryFromOrg', 'bulkUnassignTaxCategories',
            'assignEconomicActivityToOrg', 'unassignEconomicActivityFromOrg', 'bulkAssignEconomicActivitiesToOrg',
            'bulkUnassignEconomicActivitiesFromOrg', 'upsertArcaCatalog', 'createIibbRate', 'updateIibbRate',
            'bulkToggleIibbRates', 'bulkDeleteIibbRates']) {
            const operation = this[name];
            this[name] = async (...args) => {
                if (this.sessionUserId && !['TENANT_READY', 'PLATFORM_READY'].includes(this.contextState)) {
                    throw new Error('Esperá a que el contexto esté listo.');
                }
                ++this.pendingOperations;
                try { return await operation.apply(this, args); }
                finally { --this.pendingOperations; }
            };
        }
    }

    isSuperAdmin() {
        return this.currentUserRole === 'SUPERADMIN';
    }

    resetCatalogCapabilities() {
        this.permissions = { platform: { loaded: false, codes: [] }, organization: { loaded: false, orgId: null, codes: [] } };
        this.catalogAssignmentTargets = [];
        this.catalogCapabilities = { loaded: false, globalCatalogManage: false, catalogAssignAnyOrg: false, accessAnyOrg: false };
    }

    hasCapability(code, { scope = 'PLATFORM', orgId = null } = {}) {
        const p = this.permissions;
        if (scope === 'PLATFORM') return p.platform.loaded && p.platform.codes.includes(code);
        return scope === 'ORGANIZATION' && !!orgId && orgId === this.activeOrganizationId &&
            p.organization.loaded && p.organization.orgId === orgId && p.organization.codes.includes(code);
    }

    async loadMyCatalogCapabilities() {
        this.resetCatalogCapabilities();
        const pending = this.permissions;
        const orgId = this.activeOrganizationId;
        this.notify();
        try {
            const rows = await persistenceService.loadMyEffectiveCapabilities(orgId);
            if (this.permissions !== pending || this.activeOrganizationId !== orgId) return;
            this.permissions = {
                platform: { loaded: true, codes: rows.filter(r => r.scope === 'PLATFORM').map(r => r.code) },
                organization: { loaded: true, orgId, codes: rows.filter(r => r.scope === 'ORGANIZATION' && r.organization_id === orgId).map(r => r.code) }
            };
            this.catalogCapabilities = { loaded: true,
                globalCatalogManage: this.canManageGlobalCatalog(), catalogAssignAnyOrg: this.canAssignCatalog(),
                accessAnyOrg: this.hasCapability('ACCESS_ANY_ORG') };
            if (this.canAssignCatalog()) {
                const current = this.permissions;
                const targets = await persistenceService.listCatalogAssignmentTargets();
                if (this.permissions === current) this.catalogAssignmentTargets = targets;
            }
        } catch (error) {
            if (this.strictLoads) throw error;
            console.error('Could not load catalog capabilities:', error);
        }
        this.notify();
    }

    canManageGlobalCatalog() { return this.hasCapability('GLOBAL_CATALOG_MANAGE'); }
    canAssignCatalog() { return this.hasCapability('CATALOG_ASSIGN_ANY_ORG'); }
    canActivateCatalog(kind) {
        return this.hasCapability(kind === 'activity' ? 'CATALOG_ACTIVITY_MANAGE' : 'CATALOG_CATEGORY_MANAGE',
            { scope: 'ORGANIZATION', orgId: this.activeOrganizationId });
    }
    isCatalogPlatformContext() {
        return !this.activeOrganizationId && (this.hasCapability('GLOBAL_CATALOG_VIEW') || this.canManageGlobalCatalog() || this.canAssignCatalog());
    }
    // Compatibility display only. Catalog authorization uses hasCapability().
    isGlobalMicaMode() { return !this.activeOrganizationId; }

    getActiveOrganizationName() {
        if (this.isGlobalMicaMode()) return 'MICA / Plataforma';
        if (this.confirmedOrganizationName) return this.confirmedOrganizationName;
        const org = this.organizations.find(o => o.id === this.activeOrganizationId);
        return org ? org.name : (this.activeOrganizationId ? 'Nombre de organización no disponible' : 'Organización');
    }

    setUserRole(role) {
        this.resetCatalogCapabilities();
        this.currentUserRole = role;
        if (typeof sessionStorage !== 'undefined') {
            sessionStorage.setItem('mica_user_role', role);
        }
        this.notify();
    }

    async switchOrganizationContext(orgId) {
        if (!this.hasCapability('ACCESS_ANY_ORG')) throw new Error('ACCESS_ANY_ORG requerido.');
        if (this.pendingOperations) throw new Error('Esperá a que termine la operación en curso.');
        if (['SWITCHING', 'LOADING'].includes(this.contextState)) throw new Error('Hay un cambio de organización en curso.');
        const targetId = orgId || null;
        const previousState = this.contextState;
        const generation = ++this.contextGeneration;
        this.contextState = 'SWITCHING';
        this.contextError = '';
        this.notify();
        try {
            await persistenceService.switchSuperadminOrgContext(targetId);
        } catch (error) {
            if (generation !== this.contextGeneration) return;
            // A transport failure can occur after commit. Reconcile before displaying old data.
            try {
                const context = await persistenceService.getOperationalContext();
                if (generation !== this.contextGeneration) return;
                if (context.organization_id !== this.activeOrganizationId) {
                    this.clearTenantState();
                    await this.hydrateConfirmedContext(context, generation);
                    return;
                }
                this.contextState = previousState;
            } catch {
                if (generation !== this.contextGeneration) return;
                this.clearTenantState();
                this.contextState = 'ERROR';
            }
            this.contextError = error.message;
            this.notify();
            throw error;
        }
        if (generation !== this.contextGeneration) return;
        this.clearTenantState();
        this.contextState = 'LOADING';
        try {
            const context = await persistenceService.getOperationalContext();
            if (generation !== this.contextGeneration) return;
            if (context.organization_id !== targetId) throw new Error('El contexto cambió en otra sesión. Volvé a cargarlo.');
            await this.hydrateConfirmedContext(context, generation);
        } catch (error) {
            if (generation !== this.contextGeneration) return;
            this.clearTenantState();
            this.contextState = 'ERROR';
            this.contextError = error.message;
            this.notify();
            throw error;
        }
    }

    clearTenantState() {
        for (const key of ['items', 'perceptions', 'bankTransactions', 'salariesList', 'manualMovements',
            'ocrHistory', 'importIssues', 'taxCategories', 'economicActivities', 'displayedEconomicActivities',
            'globalEconomicActivities', 'iibbRates']) this[key] = [];
        this.salaries = null;
        this.currentFilter = this.currentBankFilter = this.currentJurisdiction = 'all';
        this.searchQuery = '';
        this.bankTemplates = {};
        this.bankRules = { debit: [], credit: [] };
        categorizer.setContext(null, null);
        for (const reset of this.tenantResetListeners) reset();
    }

    endSession() {
        ++this.contextGeneration;
        this.clearTenantState();
        this.resetCatalogCapabilities();
        this.activeOrganizationId = null;
        this.sessionUserId = null;
        this.sessionEmail = this.effectiveProfileName = this.confirmedOrganizationName = '';
        this.organizations = this.operationalOrgTargets = [];
        this.contextState = 'SIGNED_OUT';
        this.contextError = '';
        if (typeof sessionStorage !== 'undefined') sessionStorage.removeItem('mica_active_org_id');
        this.notify();
    }

    async initializeSession(user) {
        this.endSession();
        this.sessionUserId = user.id;
        this.sessionEmail = user.email || 'Email no disponible';
        return this.reloadOperationalContext();
    }

    async reloadOperationalContext() {
        const generation = ++this.contextGeneration;
        this.contextState = 'LOADING';
        this.contextError = '';
        this.clearTenantState();
        this.notify();
        try {
            const context = await persistenceService.getOperationalContext();
            if (generation !== this.contextGeneration) return;
            await this.hydrateConfirmedContext(context, generation);
        } catch (error) {
            if (generation !== this.contextGeneration) return;
            this.contextState = 'ERROR';
            this.contextError = error.message;
            this.notify();
            throw error;
        }
    }

    async hydrateConfirmedContext(context, generation) {
        if (generation !== this.contextGeneration) return;
        this.activeOrganizationId = context.organization_id;
        this.confirmedOrganizationName = context.organization_name || '';
        this.effectiveProfileName = context.profile_name || 'Permisos personalizados';
        this.contextState = 'LOADING';
        this.resetCatalogCapabilities();
        this.notify();
        const draft = new AppStore();
        draft.strictLoads = true;
        draft.activeOrganizationId = context.organization_id;
        await draft.loadMyCatalogCapabilities();
        if (generation !== this.contextGeneration) return;
        // Retain only freshly verified platform authority so a failed tenant load can return to Platform.
        // Organization permissions and datasets remain unpublished until hydration completes.
        this.permissions.platform = draft.permissions.platform;
        const targets = draft.hasCapability('ACCESS_ANY_ORG') ? await persistenceService.listOperationalOrgTargets() : [];
        if (generation !== this.contextGeneration) return;
        this.operationalOrgTargets = targets;
        if (context.organization_id) {
            Object.assign(draft, await persistenceService.loadOperationalSnapshot(context.organization_id));
            draft.salaries = draft.salariesList[0] || null;
        } else {
            await draft.loadTaxCategories();
            await draft.loadEconomicActivities();
        }
        // Also catches a context change made elsewhere while this snapshot was loading.
        const latest = await persistenceService.getOperationalContext();
        if (generation !== this.contextGeneration) return;
        if (latest.organization_id !== context.organization_id) throw new Error('El contexto del servidor cambió. Reintentá la carga.');
        for (const key of ['items', 'perceptions', 'bankTransactions', 'salaries', 'salariesList',
            'taxCategories', 'economicActivities', 'displayedEconomicActivities', 'globalEconomicActivities',
            'iibbRates', 'permissions', 'catalogCapabilities', 'catalogAssignmentTargets']) this[key] = draft[key];
        this.operationalOrgTargets = targets;
        this.organizations = targets.map(o => ({ id: o.organization_id, name: o.organization_name }));
        if (context.organization_id && !this.organizations.some(o => o.id === context.organization_id)) {
            this.organizations.push({ id: context.organization_id, name: context.organization_name });
        }
        this.loadTenantPreferences();
        this.contextState = context.organization_id ? 'TENANT_READY' : 'PLATFORM_READY';
        this.contextError = '';
        this.notify();
    }

    tenantStorageKey(resource) { return `mica:v2:${this.sessionUserId}:${this.activeOrganizationId}:${resource}`; }

    loadTenantPreferences() {
        const read = (key, fallback) => {
            try { return JSON.parse(localStorage.getItem(this.tenantStorageKey(key))) || fallback; }
            catch { return fallback; }
        };
        this.bankRules = read('bank_rules', structuredClone(this.defaultBankRules));
        this.bankTemplates = read('bank_templates', {});
        categorizer.setContext(this.sessionUserId, this.activeOrganizationId);
    }

    canImportOperational(type) {
        if (this.contextState !== 'TENANT_READY' || this.hasCapability('ACCESS_ANY_ORG')) return false;
        const options = { scope: 'ORGANIZATION', orgId: this.activeOrganizationId };
        const extra = { percepcion: 'PERCEPTION_IMPORT', banco: 'BANK_IMPORT', sueldo: 'PAYROLL_IMPORT' }[type];
        return ['recibido', 'emitido', 'percepcion', 'banco', 'sueldo'].includes(type) &&
            this.hasCapability('IMPORT_CREATE', options) && (!extra || this.hasCapability(extra, options));
    }

    async refreshOperationalCatalogs() {
        const generation = this.contextGeneration;
        const orgId = this.activeOrganizationId;
        const snapshot = await persistenceService.loadOperationalSnapshot(orgId, { catalogOnly: true });
        if (generation !== this.contextGeneration || orgId !== this.activeOrganizationId) return;
        for (const key of ['taxCategories', 'economicActivities', 'displayedEconomicActivities', 'iibbRates']) this[key] = snapshot[key];
        this.notify();
    }

    async loadOrganizations() {
        this.organizations = [];
        if (this.hasCapability('ACCESS_ANY_ORG')) {
            this.operationalOrgTargets = await persistenceService.listOperationalOrgTargets();
            this.organizations = this.operationalOrgTargets.map(o => ({ id: o.organization_id, name: o.organization_name }));
        } else if (this.activeOrganizationId) {
            this.organizations = await persistenceService.loadOrganizations(this.activeOrganizationId);
        }
    }

    requireGlobalCatalogContext() {
        if (!this.canManageGlobalCatalog()) throw new Error('GLOBAL_CATALOG_MANAGE capability required.');
    }

    requireAssignmentAccess(ids, rows, targetOrgId) {
        if (!this.canAssignCatalog()) throw new Error('CATALOG_ASSIGN_ANY_ORG capability required.');
        if (!targetOrgId || !this.catalogAssignmentTargets.some(o => o.organization_id === targetOrgId)) {
            throw new Error('Selecciona una organización destino válida.');
        }
    }

    requireActivationAccess(ids, rows, kind) {
        if (!this.canActivateCatalog(kind) || !this.activeOrganizationId ||
            ids.some(id => !rows.some(row => row.id === id && row.is_assigned === true &&
                row.organization_id === this.activeOrganizationId))) {
            throw new Error('Permiso requerido para activar/desactivar asignaciones propias.');
        }
    }

    async setTaxCategoriesActive(ids, active) {
        this.requireActivationAccess(ids, this.taxCategories, 'category');
        for (const id of ids) {
            if (active) await persistenceService.activateTaxCategory(id);
            else await persistenceService.deactivateTaxCategory(id);
        }
        await this.loadTaxCategories();
    }

    async setEconomicActivitiesActive(ids, active) {
        this.requireActivationAccess(ids, this.displayedEconomicActivities, 'activity');
        for (const id of ids) {
            if (active) await persistenceService.activateEconomicActivity(id);
            else await persistenceService.deactivateEconomicActivity(id);
        }
        await this.loadEconomicActivities();
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
        localStorage.setItem(this.tenantStorageKey('bank_rules'), JSON.stringify(this.bankRules));
        this.notify();
    }

    // Registrar Plantilla de Mapeo de Banco
    saveBankTemplate(bankName, mapping) {
        this.bankTemplates[bankName] = mapping;
        localStorage.setItem(this.tenantStorageKey('bank_templates'), JSON.stringify(this.bankTemplates));
    }

    // Cargar Sueldos consolidados de Acompy
    addSalary(salaryData) {
        if (!salaryData) return;
        const list = Array.isArray(salaryData) ? salaryData : [salaryData];
        list.forEach(item => {
            const norm = item.normalizedData || item;
            if (!norm) return;
            const entry = {
                ...norm,
                id: item.id || norm.id || `sal-${Date.now()}-${Math.random()}`,
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
            const existingIdx = this.salariesList.findIndex(s => (entry.periodo && s.periodo === entry.periodo) || s.id === entry.id);
            if (existingIdx !== -1) {
                this.salariesList[existingIdx] = entry;
            } else {
                this.salariesList.push(entry);
            }
        });
        if (this.salariesList.length > 0) {
            this.salaries = this.salariesList[this.salariesList.length - 1];
        }
        this.notify();
    }

    // Cargar Catálogos Impositivos y Tributarios
    async loadTaxCategories() {
        try {
            const cats = await persistenceService.loadActiveTaxCategories();
            this.taxCategories = cats || [];
            this.notify();
        } catch (e) {
            console.warn("Error cargando categorías tributarias:", e.message);
        }
    }

    async loadEconomicActivities() {
        try {
            const acts = await persistenceService.loadActiveEconomicActivities();
            this.economicActivities = acts || [];
            this.notify();
        } catch (e) {
            console.warn("Error cargando actividades económicas de la organización:", e.message);
        }
    }

    async loadGlobalEconomicActivities() {
        const generation = this.contextGeneration;
        try {
            const globalActs = this.isCatalogPlatformContext() ? await persistenceService.loadGlobalEconomicActivities() : [];
            if (generation !== this.contextGeneration) return;
            this.globalEconomicActivities = globalActs || [];
            this.notify();
        } catch (e) {
            console.warn("Error cargando catálogo global ARCA F883:", e.message);
        }
    }

    async loadIibbRates() {
        try {
            const rates = await persistenceService.loadActiveIibbRates();
            this.iibbRates = rates || [];
            this.notify();
        } catch (e) {
            console.warn("Error cargando tasas IIBB:", e.message);
        }
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
        this.searchQuery = (query || '').toLowerCase();
        this.notify();
    }

    getFilteredItems() {
        return (this.items || []).filter(item => {
            if (this.currentFilter !== 'all') {
                if (this.currentFilter === 'recibidos' && item.tipo !== 'recibido') return false;
                if (this.currentFilter === 'emitidos' && item.tipo !== 'emitido') return false;
                if (this.currentFilter === 'pending' && (item.confirmada || item.category_id)) return false;
            }
            if (this.searchQuery) {
                const q = this.searchQuery;
                const matches = (item.razonSocial || '').toLowerCase().includes(q) ||
                                (item.cuit || '').includes(q) ||
                                (item.comprobante || '').toLowerCase().includes(q);
                if (!matches) return false;
            }
            return true;
        });
    }

    async promptUpsertArcaCatalog() {
        this.requireGlobalCatalogContext();
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
        const generation = this.contextGeneration;
        const item = this.items.find(i => i.id === id);
        if (item && item.category_id) {
            item.confirmada = true;
            try {
                await persistenceService.bulkUpdateRecordClassification([item.id], item.cuit, item.category_id, item.activity_id);
                if (generation !== this.contextGeneration) return;
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
        const generation = this.contextGeneration;
        const checkboxes = document.querySelectorAll('.comprobante-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        if (confirm(`¿Estás seguro de enviar ${ids.length} registro(s) a la papelera?`)) {
            try {
                await persistenceService.bulkSoftDeleteRecords(ids);
                if (generation !== this.contextGeneration) return;
                this.items = this.items.filter(i => !ids.includes(i.id));
                this.updateBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al eliminar: " + e.message);
            }
        }
    }

    async promptBulkClassification() {
        const generation = this.contextGeneration;
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
                if (generation !== this.contextGeneration) return;
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
        // Phase 1: do not reintroduce an unscoped direct-table reader after a safe snapshot.
        this.importIssues = [];
        this.notify();
    }

    async resolveAllImportIssues() {
        throw new Error('La revisión de incidencias requiere un contrato por organización.');
    }

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

    updatePercepcionesBulkSelectionBar() {
        const checkboxes = document.querySelectorAll('.percepcion-checkbox:checked');
        const count = checkboxes.length;
        const bar = document.getElementById('percepciones-bulk-actions-bar');
        const countText = document.getElementById('percepciones-bulk-selection-count');
        
        if (bar) {
            if (count > 0) {
                bar.classList.remove('hidden');
                if (countText) {
                    countText.innerText = `${count} seleccionada${count > 1 ? 's' : ''}`;
                }
            } else {
                bar.classList.add('hidden');
            }
        }
    }

    toggleSelectAllPercepciones(checkbox) {
        const checkboxes = document.querySelectorAll('.percepcion-checkbox');
        checkboxes.forEach(cb => {
            if (!cb.disabled) cb.checked = checkbox.checked;
        });
        this.updatePercepcionesBulkSelectionBar();
    }

    async bulkSoftDeleteSelectedPercepciones() {
        const generation = this.contextGeneration;
        const checkboxes = document.querySelectorAll('.percepcion-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        if (confirm(`¿Estás seguro de enviar ${ids.length} percepción(es) a la papelera?`)) {
            try {
                await persistenceService.bulkSoftDeleteRecords(ids);
                if (generation !== this.contextGeneration) return;
                this.perceptions = (this.perceptions || []).filter(i => !ids.includes(i.id));
                this.updatePercepcionesBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al eliminar percepciones: " + e.message);
            }
        }
    }

    async bulkSoftDeleteBankMovements() {
        const generation = this.contextGeneration;
        const checkboxes = document.querySelectorAll('.banco-checkbox:checked');
        const ids = Array.from(checkboxes).map(cb => cb.value);
        if (ids.length === 0) return;

        if (confirm(`¿Enviar ${ids.length} extractos bancarios a la papelera?`)) {
            try {
                await persistenceService.bulkSoftDeleteFinancialMovements(ids);
                if (generation !== this.contextGeneration) return;
                this.bankTransactions = this.bankTransactions.filter(i => !ids.includes(i.id));
                this.updateBankBulkSelectionBar();
                this.notify();
            } catch (e) {
                alert("Error al eliminar: " + e.message);
            }
        }
    }

    async promptBankBulkClassification() {
        const generation = this.contextGeneration;
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
                    if (generation !== this.contextGeneration) return;
                
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

    // --- MÓDULO CATEGORIZACIÓN & ROLES ---
    // --- MÓDULO CATEGORIZACIÓN & ROLES ---
    async loadTaxCategories() {
        if (this.activeOrganizationId && this.contextState === 'TENANT_READY') return this.refreshOperationalCatalogs();
        if (!this.strictLoads && !['PLATFORM_READY', 'TENANT_READY'].includes(this.contextState)) return;
        const generation = this.contextGeneration;
        this.taxCategories = [];
        try {
            if (!persistenceService.supabase?.from) return;

            if (this.isCatalogPlatformContext()) {
                // MODO GLOBAL MICA: muestra todo el catálogo global y estado de asignación multi-organización
                const { data: globalCats, error: gErr } = await persistenceService.supabase
                    .from('eco_tax_categories')
                    .select('*')
                    .order('name', { ascending: true });
            if (generation !== this.contextGeneration) return;
                if (gErr) throw gErr;

                const assignmentRows = this.canAssignCatalog()
                    ? await persistenceService.listCatalogAssignmentState('category') : [];
            if (generation !== this.contextGeneration) return;
                const orgCats = assignmentRows.map(row => ({ ...row, category_id: row.item_id }));

                const categoryOrgMap = new Map();
                (orgCats || []).forEach(row => {
                    if (row && row.is_assigned && row.category_id) {
                        const orgName = this.catalogAssignmentTargets.find(org => org.organization_id === row.organization_id)?.organization_name;
                        if (orgName) {
                            if (!categoryOrgMap.has(row.category_id)) {
                                categoryOrgMap.set(row.category_id, []);
                            }
                            const list = categoryOrgMap.get(row.category_id);
                            if (!list.includes(orgName)) {
                                list.push(orgName);
                            }
                        }
                    }
                });

                this.taxCategories = (globalCats || []).map(c => {
                    const orgNames = categoryOrgMap.get(c.id) || [];
                    return {
                        ...c,
                        assignedOrganizationIds: (orgCats || []).filter(r => r.category_id === c.id && r.is_assigned).map(r => r.organization_id),
                        assignedState: orgNames.join(', '),
                        isAssignedToOrg: orgNames.length > 0
                    };
                });
            } else if (this.activeOrganizationId) {
                // MODO ORGANIZACIÓN (DEMO NORTE / SUR / OESTE):
                // Muestra ÚNICAMENTE las categorías asignadas a esta organización (Activas o Inactivas)
                const { data: orgAssigned, error: aErr } = await persistenceService.supabase
                    .from('eco_org_tax_categories')
                    .select('id, organization_id, category_id, is_assigned, is_active, custom_name, category:eco_tax_categories(id, name, description, category_type)')
                    .eq('organization_id', this.activeOrganizationId)
                    .eq('is_assigned', true);
            if (generation !== this.contextGeneration) return;
                
                if (aErr) throw aErr;

                this.taxCategories = (orgAssigned || []).filter(row => row.category && row.is_assigned === true).map(row => ({
                    id: row.category.id,
                    org_assignment_id: row.id,
                    organization_id: row.organization_id,
                    name: row.custom_name || row.category.name,
                    description: row.category.description,
                    category_type: row.category.category_type,
                    is_active: row.is_active, // true = Activas, false = Inactivas
                    is_assigned: row.is_assigned,
                    isAssignedToOrg: row.is_assigned,
                    assignedState: ''
                }));
            } else {
                const activeOrgCats = [];
                this.taxCategories = (activeOrgCats || []).map(c => ({
                    ...c,
                    assignedState: '',
                    isAssignedToOrg: true
                }));
            }
            this.notify();
        } catch (e) {
            if (this.strictLoads) throw e;
            console.error("Failed to load tax categories:", e);
        }
    }

    async loadEconomicActivities() {
        if (this.activeOrganizationId && this.contextState === 'TENANT_READY') return this.refreshOperationalCatalogs();
        if (!this.strictLoads && !['PLATFORM_READY', 'TENANT_READY'].includes(this.contextState)) return;
        const generation = this.contextGeneration;
        this.economicActivities = [];
        this.displayedEconomicActivities = [];
        this.globalEconomicActivities = [];
        try {
            if (!persistenceService.supabase?.from) return;

            const globalActs = this.isCatalogPlatformContext() ? await persistenceService.loadGlobalEconomicActivities() : [];
            if (generation !== this.contextGeneration) return;
            this.globalEconomicActivities = globalActs || [];

            if (this.isCatalogPlatformContext()) {
                // MODO GLOBAL MICA: Muestra las 958 actividades y sus asignaciones
                const assignmentRows = this.canAssignCatalog()
                    ? await persistenceService.listCatalogAssignmentState('activity') : [];
            if (generation !== this.contextGeneration) return;
                const orgActs = assignmentRows.map(row => ({ ...row, activity_id: row.item_id }));

                const activityOrgMap = new Map();
                (orgActs || []).forEach(row => {
                    if (row && row.is_assigned && row.activity_id) {
                        const orgName = this.catalogAssignmentTargets.find(org => org.organization_id === row.organization_id)?.organization_name;
                        if (orgName) {
                            if (!activityOrgMap.has(row.activity_id)) {
                                activityOrgMap.set(row.activity_id, []);
                            }
                            const list = activityOrgMap.get(row.activity_id);
                            if (!list.includes(orgName)) {
                                list.push(orgName);
                            }
                        }
                    }
                });

                this.displayedEconomicActivities = (globalActs || []).map(a => {
                    const orgNames = activityOrgMap.get(a.id) || [];
                    return {
                        ...a,
                        assignedOrganizationIds: (orgActs || []).filter(r => r.activity_id === a.id && r.is_assigned).map(r => r.organization_id),
                        assignedState: orgNames.join(', '),
                        isAssignedToOrg: orgNames.length > 0
                    };
                });
                this.economicActivities = [];
            } else if (this.activeOrganizationId) {
                // MODO ORGANIZACIÓN: Muestra ÚNICAMENTE las actividades asignadas a esta organización
                const { data: orgAssigned, error: aErr } = await persistenceService.supabase
                    .from('eco_org_economic_activities')
                    .select('id, organization_id, activity_id, is_assigned, is_active, activity:eco_economic_activities(id, name, arca_code, description)')
                    .eq('organization_id', this.activeOrganizationId)
                    .eq('is_assigned', true);
            if (generation !== this.contextGeneration) return;
                if (aErr) throw aErr;

                const assignedList = (orgAssigned || []).filter(row => row.activity && row.is_assigned === true).map(row => ({
                    id: row.activity.id,
                    organization_id: row.organization_id,
                    name: row.activity.name,
                    arca_code: row.activity.arca_code,
                    description: row.activity.description,
                    is_active: row.is_active,
                    is_assigned: row.is_assigned,
                    isAssignedToOrg: row.is_assigned,
                    assignedState: ''
                }));

                this.economicActivities = assignedList.filter(a => a.is_active);
                this.displayedEconomicActivities = assignedList;
            } else {
                const activeOrgActs = [];
                this.economicActivities = activeOrgActs || [];
                this.displayedEconomicActivities = (activeOrgActs || []).map(a => ({
                    ...a,
                    assignedState: '',
                    isAssignedToOrg: true
                }));
            }
            this.notify();
        } catch (e) {
            if (this.strictLoads) throw e;
            console.error("Failed to load economic activities:", e);
        }
    }

    async loadIibbRates() {
        if (this.activeOrganizationId && this.contextState === 'TENANT_READY') return this.refreshOperationalCatalogs();
        if (!this.strictLoads && !['PLATFORM_READY', 'TENANT_READY'].includes(this.contextState)) return;
        const generation = this.contextGeneration;
        try {
            if (this.isGlobalMicaMode()) {
                this.iibbRates = [];
                this.notify();
                return;
            }

            const rates = await persistenceService.loadActiveIibbRates();
            if (generation !== this.contextGeneration) return;
            const activitiesMap = new Map();
            (this.globalEconomicActivities || []).forEach(a => {
                activitiesMap.set(a.id, a.name || a.arca_code || a.code);
            });
            (this.economicActivities || []).forEach(a => {
                activitiesMap.set(a.id, a.name || a.arca_code);
            });

            this.iibbRates = (rates || []).map(r => ({
                ...r,
                rate_percent: r.rate !== undefined ? r.rate : r.rate_percent,
                activity_name: activitiesMap.get(r.activity_id) || r.activity_name || (r.activity_id ? String(r.activity_id).substring(0, 8) : 'Desconocida')
            }));
            this.notify();
        } catch (e) {
            if (this.strictLoads) throw e;
            console.error("Failed to load IIBB rates:", e);
        }
    }

    async loadIibbData() {
        await this.loadEconomicActivities();
        await this.loadIibbRates();
    }

    async createTaxCategory(payload, targetOrgId = null) {
        this.requireGlobalCatalogContext();
        if (targetOrgId) this.requireAssignmentAccess([], [], targetOrgId);
        const activeOrgId = targetOrgId || this.activeOrganizationId;
        if (!activeOrgId && !this.isGlobalMicaMode()) {
            throw new Error('No hay una organización activa seleccionada.');
        }

        // Crear en el catálogo global; la asignación requiere un destino explícito.
        const res = await persistenceService.createTaxCategory(payload, targetOrgId);
        await this.loadTaxCategories();

        if (activeOrgId && res && res.id) {
            const found = (this.taxCategories || []).some(c => c.id === res.id || c.org_assignment_id === res.id);
            if (!found) {
                throw new Error(`La categoría "${payload.name}" fue creada pero no se pudo confirmar su asignación en la organización activa.`);
            }
        }
        return res;
    }

    async updateTaxCategory(categoryId, payload) {
        this.requireGlobalCatalogContext();
        await persistenceService.updateTaxCategory(categoryId, payload);
        await this.loadTaxCategories();
    }

    async assignTaxCategoryToOrg(categoryId, targetOrgId = null) {
        this.requireAssignmentAccess([categoryId], this.taxCategories, targetOrgId);
        await persistenceService.assignTaxCategoryToOrg(categoryId, targetOrgId);
        await this.loadTaxCategories();
    }

    async bulkAssignTaxCategories(categoryIds, targetOrgId = null) {
        this.requireAssignmentAccess(categoryIds, this.taxCategories, targetOrgId);
        if (!Array.isArray(categoryIds) || categoryIds.length === 0) return;
        for (const id of categoryIds) {
            await persistenceService.assignTaxCategoryToOrg(id, targetOrgId);
        }
        await this.loadTaxCategories();
    }

    async unassignTaxCategoryFromOrg(categoryId, targetOrgId = null) {
        this.requireAssignmentAccess([categoryId], this.taxCategories, targetOrgId);
        await persistenceService.unassignTaxCategoryFromOrg(categoryId, targetOrgId);
        await this.loadTaxCategories();
    }

    async bulkUnassignTaxCategories(categoryIds, targetOrgId = null) {
        this.requireAssignmentAccess(categoryIds, this.taxCategories, targetOrgId);
        if (!Array.isArray(categoryIds) || categoryIds.length === 0) return;
        for (const id of categoryIds) {
            await persistenceService.unassignTaxCategoryFromOrg(id, targetOrgId);
        }
        await this.loadTaxCategories();
    }

    async assignEconomicActivityToOrg(activityId, targetOrgId = null) {
        this.requireAssignmentAccess([activityId], this.displayedEconomicActivities, targetOrgId);
        await persistenceService.assignEconomicActivityToOrg(activityId, targetOrgId);
        await this.loadEconomicActivities();
    }

    async unassignEconomicActivityFromOrg(activityId, targetOrgId = null) {
        this.requireAssignmentAccess([activityId], this.displayedEconomicActivities, targetOrgId);
        await persistenceService.unassignEconomicActivityFromOrg(activityId, targetOrgId);
        await this.loadEconomicActivities();
    }

    async bulkAssignEconomicActivitiesToOrg(activityIds, targetOrgId = null) {
        this.requireAssignmentAccess(activityIds, this.displayedEconomicActivities, targetOrgId);
        if (!Array.isArray(activityIds) || activityIds.length === 0) return;
        for (const id of activityIds) {
            await persistenceService.assignEconomicActivityToOrg(id, targetOrgId);
        }
        await this.loadEconomicActivities();
    }

    async bulkUnassignEconomicActivitiesFromOrg(activityIds, targetOrgId = null) {
        this.requireAssignmentAccess(activityIds, this.displayedEconomicActivities, targetOrgId);
        if (!Array.isArray(activityIds) || activityIds.length === 0) return;
        for (const id of activityIds) {
            await persistenceService.unassignEconomicActivityFromOrg(id, targetOrgId);
        }
        await this.loadEconomicActivities();
    }

    async upsertArcaCatalog(activitiesJson) {
        this.requireGlobalCatalogContext();
        const count = await persistenceService.upsertArcaCatalog(activitiesJson);
        await this.loadEconomicActivities();
        return count;
    }

    async createIibbRate(payload) {
        if (!payload.activity_id || String(payload.activity_id).trim() === '') {
            throw new Error('La Actividad Económica es obligatoria para la tasa IIBB.');
        }

        const validAssignedIds = new Set((this.economicActivities || []).map(a => a.id));
        if (!validAssignedIds.has(payload.activity_id)) {
            throw new Error('Activity ID is not assigned to this organization or is inactive');
        }

        const res = await persistenceService.createIibbRate(payload);
        await this.loadIibbRates();
        return res;
    }

    async updateIibbRate(rateId, payload) {
        const res = await persistenceService.updateIibbRate(rateId, payload);
        await this.loadIibbRates();
        return res;
    }

    async bulkToggleIibbRates(rateIds) {
        if (!Array.isArray(rateIds) || rateIds.length === 0) return;
        for (const id of rateIds) {
            const current = (this.iibbRates || []).find(r => r.id === id);
            const nextActive = current ? !current.is_active : false;
            await persistenceService.updateIibbRate(id, {
                rate_percent: current ? current.rate_percent : 0,
                valid_from: current ? current.valid_from : null,
                valid_to: current ? current.valid_to : null,
                is_active: nextActive
            });
        }
        await this.loadIibbRates();
    }

    async bulkDeleteIibbRates(rateIds) {
        if (!Array.isArray(rateIds) || rateIds.length === 0) return;
        for (const id of rateIds) {
            const current = (this.iibbRates || []).find(r => r.id === id);
            await persistenceService.updateIibbRate(id, {
                rate_percent: current ? current.rate_percent : 0,
                valid_from: current ? current.valid_from : null,
                valid_to: current ? current.valid_to : null,
                is_active: false
            });
        }
        await this.loadIibbRates();
    }
}

export const appStore = new AppStore();
