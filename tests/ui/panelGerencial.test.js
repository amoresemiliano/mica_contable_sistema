import { jest } from '@jest/globals';

const elements = {};
function createMockElement() {
    return {
        innerText: '',
        style: {},
        innerHTML: '',
        classList: { toggle: jest.fn(), add: jest.fn(), remove: jest.fn(), contains: jest.fn() },
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

describe('Panel Gerencial Integration Tests', () => {
    beforeEach(() => {
        appStore.items = [];
    });

    test('calcula correctamente Ventas Brutas, Egresos, Resultado Operativo, IVA e IIBB', () => {
        appStore.items = [
            { id: '1', tipo: 'emitido', total: 10000.00, categoria: 'Ventas Software' },
            { id: '2', tipo: 'recibido', total: 2000.00, categoria: 'Servicios Públicos' },
            { id: '3', tipo: 'recibido', total: 1000.00, categoria: 'Servicios Públicos' }
        ];

        renderClientDashboard();

        const salesEl = document.getElementById('client-sales-val');
        const purchasesEl = document.getElementById('client-purchases-val');
        const netEl = document.getElementById('client-net-val');
        const ivaEl = document.getElementById('client-iva-val');
        const iibbEl = document.getElementById('client-iibb-val');

        expect(salesEl.innerText).toContain('10.000,00');
        expect(purchasesEl.innerText).toContain('3.000,00');
        expect(netEl.innerText).toContain('7.000,00');
        
        // IVA Estimado: (10000 * 0.21) - (3000 * 0.21) = 2100 - 630 = 1470
        expect(ivaEl.innerText).toContain('1.470,00');

        // IIBB Estimado: 10000 * 0.03 = 300
        expect(iibbEl.innerText).toContain('300,00');
    });

    test('renderiza adecuadamente el resumen de Top Categorías de Gasto', () => {
        appStore.items = [
            { id: '1', tipo: 'recibido', total: 3000.00, categoria: 'Servicios Públicos' },
            { id: '2', tipo: 'recibido', total: 1000.00, categoria: 'Alquileres' }
        ];

        renderClientDashboard();

        const categoryChart = document.getElementById('client-category-chart');
        expect(categoryChart.innerHTML).toContain('Servicios Públicos');
        expect(categoryChart.innerHTML).toContain('Alquileres');
        expect(categoryChart.innerHTML).toContain('75%'); // 3000 / 4000
        expect(categoryChart.innerHTML).toContain('25%'); // 1000 / 4000
    });
});
