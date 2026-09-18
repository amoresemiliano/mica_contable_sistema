import { parseBankRows } from '../../src/js/core/parsers/bankParser.js';
import bbvaRealSample from '../fixtures/bbva_real_shape_sample.json' with { type: 'json' };

describe('WP-FUNC-3: Bank Statement Normalization & Retry Consistency', () => {
    test('1. Parser maps reference, balance, account, amount, type, fecha from real BBVA raw shape fixture', () => {
        const parsed = parseBankRows(bbvaRealSample);
        expect(parsed.length).toBe(2);

        const row1 = parsed[0];
        expect(row1.errors.length).toBe(0);
        expect(row1.normalizedData.fecha).toBe('29-05-2026');
        expect(row1.normalizedData.fechaValor).toBe('29-05-2026');
        expect(row1.normalizedData.descripcion).toBe('SELLADO');
        expect(row1.normalizedData.referencia).toBe('030');
        expect(row1.normalizedData.accountIdentifier).toBe('133 - PARQUE INDUSTRIAL PILAR');
        expect(row1.normalizedData.monto).toBe(1073.43);
        expect(row1.normalizedData.tipo).toBe('debit');
        expect(row1.normalizedData.saldo).toBe(-10860159.05);

        const row2 = parsed[1];
        expect(row2.errors.length).toBe(0);
        expect(row2.normalizedData.fecha).toBe('29-05-2026');
        expect(row2.normalizedData.descripcion).toBe('INT.COB.ACUE 021304003202605');
        expect(row2.normalizedData.referencia).toBe('122');
        expect(row2.normalizedData.accountIdentifier).toBe('133 - PARQUE INDUSTRIAL PILAR');
        expect(row2.normalizedData.monto).toBe(32285.88);
        expect(row2.normalizedData.tipo).toBe('debit');
        expect(row2.normalizedData.saldo).toBeNull();
    });

    test('2. Header-based parseBankRows handles structured rows with reference/saldo/accountIdentifier', () => {
        const rows = [
            ['Fecha', 'Concepto', 'Referencia', 'Suc. Origen', 'Importe', 'Saldo'],
            ['29-05-2026', 'COMISION BANCO', '08912', '001 - CENTRAL', '-500.00', '150000.50']
        ];
        const parsed = parseBankRows(rows);
        expect(parsed.length).toBe(1);
        const norm = parsed[0].normalizedData;
        expect(norm.referencia).toBe('08912');
        expect(norm.saldo).toBe(150000.50);
        expect(norm.accountIdentifier).toBe('001 - CENTRAL');
        expect(norm.monto).toBe(500);
        expect(norm.tipo).toBe('debit');
    });

    test('3. Balance text extraction handles complex strings safely', () => {
        const rawRows = [
            ["29-05-2026", "29-05-2026", "DEP EFFECTIVO", "991", "", "MAIN", "", 5000.00, "", "Saldo: 1.250.000,50"]
        ];
        const parsed = parseBankRows(rawRows);
        expect(parsed[0].normalizedData.saldo).toBe(1250000.50);
    });

    test('4. Retry rule semantic logic validation', () => {
        const simulateCheckFileImportable = (acceptedRows) => {
            const hasSuccessfulBusinessResult = (acceptedRows ?? 0) > 0;
            return {
                importable: !hasSuccessfulBusinessResult,
                reason: hasSuccessfulBusinessResult ? 'FILE_ALREADY_EXISTS' : null
            };
        };

        expect(simulateCheckFileImportable(0).importable).toBe(true);
        expect(simulateCheckFileImportable(null).importable).toBe(true);
        expect(simulateCheckFileImportable(15).importable).toBe(false);
        expect(simulateCheckFileImportable(15).reason).toBe('FILE_ALREADY_EXISTS');
    });
});
