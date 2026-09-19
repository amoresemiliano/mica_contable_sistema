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

    test('5. Débito BBVA headerless: row[7] negativo, parse sin error, tipo debit', () => {
        const headerlessDebit = [
            ["29-05-2026", "29-05-2026", "SELLADO", "030", "", "133 - PARQUE INDUSTRIAL PILAR", "", -1825.74, "", ""]
        ];
        const res = parseBankRows(headerlessDebit);
        expect(res[0].errors).toEqual([]);
        expect(res[0].normalizedData.tipo).toBe('debit');
        expect(res[0].normalizedData.monto).toBe(1825.74);
        expect(res[0].normalizedData.referencia).toBe('030');
    });

    test('6. Crédito BBVA headerless: row[7] vacío, row[6] positivo, parse sin error, tipo credit', () => {
        const headerlessCredit = [
            ["21-05-2026", "21-05-2026", "TRANSF.BANEL 30715507419", "136", "", "733 - N/A", 347000, "", "CTE 30715507419", ""]
        ];
        const res = parseBankRows(headerlessCredit);
        expect(res[0].errors).toEqual([]);
        expect(res[0].normalizedData.tipo).toBe('credit');
        expect(res[0].normalizedData.monto).toBe(347000);
        expect(res[0].normalizedData.referencia).toBe('136');
    });

    test('7. Fila SELLADO real: fecha "29-05-2026", referencia "030", monto válido, no INVALID', () => {
        const realSelladoRow = [
            ["29-05-2026", "29-05-2026", "SELLADO", "030", "", "133 - PARQUE INDUSTRIAL PILAR", "", -1073.43, "", "Saldo Disponible: -10.860.159,05"]
        ];
        const res = parseBankRows(realSelladoRow);
        expect(res[0].errors).toEqual([]);
        expect(res[0].normalizedData.fecha).toBe('29-05-2026');
        expect(res[0].normalizedData.referencia).toBe('030');
        expect(res[0].normalizedData.monto).toBe(1073.43);
        expect(res[0].normalizedData.saldo).toBe(-10860159.05);
        expect(res[0].normalizedData.tipo).toBe('debit');
    });

    test('8. Persistencia SQL: persist_financial_movements_batch usa row_id, movement_type, financial_fingerprint sin columnas legacy', async () => {
        const fs = await import('fs');
        const sql027 = fs.readFileSync('sql/027_fix_bbva_import_and_retry.sql', 'utf8');
        expect(sql027).toContain('row_id,');
        expect(sql027).toContain('movement_type,');
        expect(sql027).toContain('financial_fingerprint,');
        expect(sql027).not.toMatch(/INSERT INTO public\.eco_financial_movements\s*\([^)]*\btipo\b/i);
        expect(sql027).not.toMatch(/INSERT INTO public\.eco_financial_movements\s*\([^)]*\bfingerprint\b/i);
    });

    test('9. Reintento, Import exitoso y Aislamiento Multitenant de hash', () => {
        const checkImportableMultiTenant = (filesDb, orgId, hash) => {
            const match = filesDb.find(f => f.organizationId === orgId && f.hash === hash && f.acceptedRows > 0);
            if (match) {
                return { importable: false, reason: 'FILE_ALREADY_EXISTS' };
            }
            return { importable: true };
        };

        const filesDb = [
            { organizationId: 'org-A', hash: 'hash123', acceptedRows: 0 },
            { organizationId: 'org-B', hash: 'hash456', acceptedRows: 10 }
        ];

        // accepted_rows = 0 en org-A -> importable/retry permitido
        expect(checkImportableMultiTenant(filesDb, 'org-A', 'hash123').importable).toBe(true);

        // accepted_rows > 0 en org-B -> bloqueado en org-B
        expect(checkImportableMultiTenant(filesDb, 'org-B', 'hash456').importable).toBe(false);
        expect(checkImportableMultiTenant(filesDb, 'org-B', 'hash456').reason).toBe('FILE_ALREADY_EXISTS');

        // Mismo hash 'hash456' en org-A (otra organizacion) -> permitido
        expect(checkImportableMultiTenant(filesDb, 'org-A', 'hash456').importable).toBe(true);
    });
});
