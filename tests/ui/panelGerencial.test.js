import { jest } from '@jest/globals';

const elements = {};
function createMockElement() {
    return {
        innerText: '',
        style: {},
        innerHTML: '',
        classList: { 
            toggle: jest.fn(), 
            add: jest.fn(), 
            remove: jest.fn(), 
            contains: jest.fn() 
        },
        addEventListener: jest.fn()
    };
}

if (typeof global.window === 'undefined') {
    global.window = global;
}
if (typeof global.window.location === 'undefined') {
    global.window.location = { origin: 'http://localhost', pathname: '/' };
}

if (typeof global.document === 'undefined') {
    global.document = {
        getElementById: (id) => {
            if (!elements[id]) elements[id] = createMockElement();
            return elements[id];
        },
        querySelectorAll: () => [],
        querySelector: () => createMockElement(),
        addEventListener: jest.fn()
    };
}

// Mock Supabase client
jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: jest.fn(),
        auth: {
            onAuthStateChange: jest.fn(),
            getSession: jest.fn().mockResolvedValue({ data: { session: null } })
        }
    }
}));

const { appStore } = await import('../../src/js/store.js');
const { renderClientDashboard } = await import('../../src/js/ui.js');

describe('Panel Gerencial Complete Restoration & Strict Fiscal Determination Tests', () => {
    beforeEach(() => {
        appStore.items = [];
        appStore.salaries = null;
        appStore.manualMovements = [];

        // Reset innerText for all mock elements
        ['client-sales-val', 'client-purchases-val', 'client-net-val', 'client-labor-val', 'client-iva-val', 'client-iibb-val'].forEach(id => {
            elements[id] = createMockElement();
        });
        elements['alert-unresolved-taxes'] = createMockElement();
        elements['alert-no-issues'] = createMockElement();
        elements['client-category-chart'] = createMockElement();
    });

    test('todos los elementos históricos del dashboard existen (incluyendo client-labor-val y alert-unresolved-taxes)', () => {
        const laborEl = document.getElementById('client-labor-val');
        const alertEl = document.getElementById('alert-unresolved-taxes');
        const salesEl = document.getElementById('client-sales-val');
        const purchasesEl = document.getElementById('client-purchases-val');
        const netEl = document.getElementById('client-net-val');
        const ivaEl = document.getElementById('client-iva-val');
        const iibbEl = document.getElementById('client-iibb-val');

        expect(laborEl).toBeDefined();
        expect(alertEl).toBeDefined();
        expect(salesEl).toBeDefined();
        expect(purchasesEl).toBeDefined();
        expect(netEl).toBeDefined();
        expect(ivaEl).toBeDefined();
        expect(iibbEl).toBeDefined();
    });

    test('NO calcula IVA con total * 0.21 ni IIBB con alícuota hardcodeada 0.03', () => {
        appStore.items = [
            { id: '1', tipo: 'emitido', total: 10000.00, iva: 0 },
            { id: '2', tipo: 'recibido', total: 5000.00, iva: 0 }
        ];

        renderClientDashboard();

        const ivaEl = document.getElementById('client-iva-val');
        const iibbEl = document.getElementById('client-iibb-val');

        // IVA no debe ser 1050 (10000*0.21 - 5000*0.21) sino neutro/pendiente
        expect(ivaEl.innerText).not.toContain('1.050');
        expect(ivaEl.innerText).toBe('Pendiente de determinación');

        // IIBB no debe ser 300 (10000*0.03) sino pendiente de determinación
        expect(iibbEl.innerText).not.toContain('300');
        expect(iibbEl.innerText).toBe('Pendiente de determinación');
    });

    test('utiliza campos IVA fiscales reales si existen en los comprobantes importados', () => {
        appStore.items = [
            { id: '1', tipo: 'emitido', total: 12100.00, iva: 2100.00 },
            { id: '2', tipo: 'recibido', total: 6050.00, iva: 1050.00 }
        ];

        renderClientDashboard();

        const ivaEl = document.getElementById('client-iva-val');
        // Débito (2100) - Crédito (1050) = 1050
        expect(ivaEl.innerText).toContain('1.050,00');
    });

    test('la tarjeta de Costo Laboral utiliza el modelo validado actual de Sueldos', () => {
        appStore.salaries = {
            sueldoBrutoCalculado: 500000.00,
            noRemunerativo: 50000.00
        };

        renderClientDashboard();

        const laborEl = document.getElementById('client-labor-val');
        expect(laborEl.innerText).toContain('550.000,00');
    });

    test('gestiona adecuadamente las alertas de comprobantes no explicados / no categorizados', () => {
        appStore.items = [
            { id: '1', tipo: 'recibido', total: 2000.00, saldoAExplicar: 2000.00, confirmada: false }
        ];

        renderClientDashboard();

        const alertEl = document.getElementById('alert-unresolved-taxes');
        expect(alertEl.innerHTML).toContain('Tenés 1 comprobantes de compras sin categorizar');
    });
});
