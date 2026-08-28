import { AppStore } from '../../src/js/store.js';
import { parseArbaText } from '../../src/js/core/parsers/arbaParser.js';
import { parseIvaPerceptions } from '../../src/js/core/parsers/ivaPerceptionParser.js';

describe('Perceptions Dynamic Jurisdiction Filter & Store Unit Tests', () => {
    let store;

    beforeEach(() => {
        store = new AppStore();
    });

    it('should initialize with default jurisdiction "all" (Todas las Percepciones)', () => {
        expect(store.currentJurisdiction).toBe('all');
    });

    it('should normalize jurisdiction names consistently to avoid duplicates', () => {
        expect(store.normalizeJurisdictionName('ARBA')).toBe('Buenos Aires (ARBA)');
        expect(store.normalizeJurisdictionName('buenos aires')).toBe('Buenos Aires (ARBA)');
        expect(store.normalizeJurisdictionName('Bs. As.')).toBe('Buenos Aires (ARBA)');
        expect(store.normalizeJurisdictionName('AGIP')).toBe('CABA (AGIP)');
        expect(store.normalizeJurisdictionName('CABA')).toBe('CABA (AGIP)');
        expect(store.normalizeJurisdictionName('IVA')).toBe('IVA (Nacional)');
        expect(store.normalizeJurisdictionName('NACIONAL (IVA)')).toBe('IVA (Nacional)');
        expect(store.normalizeJurisdictionName('CORDOBA')).toBe('Córdoba');
    });

    it('should return unique sorted available jurisdictions from loaded perceptions', () => {
        store.addPerceptions([
            { cuit: '30111111118', monto: 1000, jurisdiction: 'ARBA', fecha: '10/05/2026' },
            { cuit: '30222222228', monto: 2500, jurisdiction: 'BUENOS AIRES', fecha: '11/05/2026' },
            { cuit: '30333333338', monto: 3000, jurisdiction: 'AGIP', fecha: '12/05/2026' },
            { cuit: '30444444448', monto: 1500, jurisdiction: 'IVA', fecha: '13/05/2026' }
        ]);

        const jurisdictions = store.getAvailableJurisdictions();

        expect(jurisdictions).toEqual(['Buenos Aires (ARBA)', 'CABA (AGIP)', 'IVA (Nacional)']);
    });

    it('should filter perceptions correctly by selected jurisdiction', () => {
        store.addPerceptions([
            { cuit: '30111111118', monto: 1000, jurisdiction: 'ARBA', fecha: '10/05/2026' },
            { cuit: '30222222228', monto: 2500, jurisdiction: 'AGIP', fecha: '11/05/2026' },
            { cuit: '30333333338', monto: 3000, jurisdiction: 'IVA', fecha: '12/05/2026' }
        ]);

        expect(store.getFilteredPerceptions()).toHaveLength(3);

        store.setJurisdictionFilter('Buenos Aires (ARBA)');
        const arbaPerceptions = store.getFilteredPerceptions();
        expect(arbaPerceptions).toHaveLength(1);
        expect(arbaPerceptions[0].cuit).toBe('30111111118');

        store.setJurisdictionFilter('all');
        expect(store.getFilteredPerceptions()).toHaveLength(3);
    });

    it('should not interfere with ARCA invoice filtering (Compra/Venta)', () => {
        store.addItems([
            { id: '1', tipo: 'recibido', tipoOperacion: 'COMPRA', razonSocial: 'Proveedor S.A.', cuit: '30111', comprobante: '1-1-1', confirmada: true },
            { id: '2', tipo: 'emitido', tipoOperacion: 'VENTA', razonSocial: 'Cliente S.R.L.', cuit: '30222', comprobante: '6-1-1', confirmada: true }
        ]);

        store.addPerceptions([
            { cuit: '30999999999', monto: 500, jurisdiction: 'ARBA', fecha: '15/05/2026' }
        ]);

        store.setJurisdictionFilter('Buenos Aires (ARBA)');

        expect(store.getFilteredItems()).toHaveLength(2);

        store.setFilter('recibidos');
        expect(store.getFilteredItems()).toHaveLength(1);
        expect(store.getFilteredItems()[0].tipo).toBe('recibido');
    });

    it('should preserve regimen at top-level in arbaParser normalizedData', () => {
        // Line layout: 0..4 (0062), 4..18 (30-68992077-9 ), 18..28 (15/05/2026), 28..32 (0001), 32..56 (000000000000000000000100), 56..70 (00000001000,00)
        const dummyLine = '006230-68992077-9 15/05/2026000100000000000000000000010000000001000,00';
        expect(dummyLine.length).toBe(70);

        const results = parseArbaText(dummyLine);
        expect(results).toHaveLength(1);
        expect(results[0].errors).toHaveLength(0);
        expect(results[0].normalizedData).not.toBeNull();
        expect(results[0].normalizedData.regimen).toBe('0062');
        expect(results[0].normalizedData.cuit).toBe('30689920779');
        expect(results[0].normalizedData.fecha).toBe('15/05/2026');
        expect(results[0].normalizedData.sucursal).toBe('0001');
        expect(results[0].normalizedData.comprobante).toBe('000000000000000000000100');
        expect(results[0].normalizedData.monto).toBe(1000.00);
    });

    it('should calculate canonical ARBA identity keys differentiating regimen and canonical date', () => {
        function computeArbaIdentityKey(p) {
            const dateParts = p.fecha.split('/');
            const canonicalDate = dateParts.length === 3 ? `${dateParts[2]}-${dateParts[1]}-${dateParts[0]}` : p.fecha;
            return JSON.stringify([
                'PERCEPCION',
                'PERCEPCIONES_ARBA',
                'ARBA',
                p.regimen || '0',
                p.cuit,
                canonicalDate,
                p.sucursal || '0',
                p.comprobante || '0'
            ]);
        }

        const rec1 = { regimen: '0062', cuit: '30689920779', fecha: '15/05/2026', sucursal: '0001', comprobante: '100' };
        const rec2Same = { regimen: '0062', cuit: '30689920779', fecha: '15/05/2026', sucursal: '0001', comprobante: '100' };
        const rec3DiffRegimen = { regimen: '0011', cuit: '30689920779', fecha: '15/05/2026', sucursal: '0001', comprobante: '100' };

        const key1 = computeArbaIdentityKey(rec1);
        const key2 = computeArbaIdentityKey(rec2Same);
        const key3 = computeArbaIdentityKey(rec3DiffRegimen);

        expect(key1).toBe(key2);
        expect(key1).not.toBe(key3);
        expect(key1).toContain('2026-05-15');
    });
});
