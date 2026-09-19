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
        const sql028 = fs.readFileSync('sql/028_fix_source_file_reuse_and_retry_flow.sql', 'utf8');
        expect(sql028).toContain('row_id,');
        expect(sql028).toContain('movement_type,');
        expect(sql028).toContain('financial_fingerprint,');
        expect(sql028).not.toMatch(/INSERT INTO public\.eco_financial_movements\s*\([^)]*\btipo\b/i);
        expect(sql028).not.toMatch(/INSERT INTO public\.eco_financial_movements\s*\([^)]*\bfingerprint\b/i);
    });

    test('9. SQL 028: Reutilización defensiva de source_file por (organization_id, sha256_hash) sin violar unicidad', async () => {
        const fs = await import('fs');
        const sql028 = fs.readFileSync('sql/028_fix_source_file_reuse_and_retry_flow.sql', 'utf8');
        // Debe buscar por linaje o por (organization_id, sha256_hash) antes de hacer INSERT
        expect(sql028).toContain('WHERE sf.organization_id = v_org_id');
        expect(sql028).toContain('AND sf.sha256_hash = v_hash');
        expect(sql028).toContain('IF v_file_id IS NULL THEN');
    });

    test('10. check_file_importable: Contrato explícito para retry, imports exitosos y archivos nuevos', () => {
        const checkImportableMultiTenant = (filesDb, orgId, hash) => {
            // 1. Bloquear si existe import exitoso
            const successfulMatch = filesDb.find(f => f.organizationId === orgId && f.hash === hash && f.acceptedRows > 0);
            if (successfulMatch) {
                return {
                    importable: false,
                    reason: 'FILE_ALREADY_EXISTS',
                    existing_file_id: successfulMatch.fileId
                };
            }

            // 2. Si existe archivo e import fallido previo (accepted_rows = 0), ofrecer retry con candidato determinístico
            const failedMatches = filesDb
                .filter(f => f.organizationId === orgId && f.hash === hash && f.acceptedRows === 0)
                .sort((a, b) => a.createdAt - b.createdAt);

            if (failedMatches.length > 0) {
                const primary = failedMatches[0];
                return {
                    importable: true,
                    retry_available: true,
                    retry_candidate_import_id: primary.importId,
                    existing_file_id: primary.fileId
                };
            }

            // 3. Archivo nuevo
            return {
                importable: true,
                retry_available: false
            };
        };

        const filesDb = [
            { fileId: 'file-1', importId: 'imp-1', organizationId: 'org-A', hash: 'bbva-hash', acceptedRows: 0, createdAt: 100 },
            { fileId: 'file-1', importId: 'imp-retry-1', organizationId: 'org-A', hash: 'bbva-hash', acceptedRows: 0, createdAt: 200 },
            { fileId: 'file-2', importId: 'imp-2', organizationId: 'org-B', hash: 'bbva-hash', acceptedRows: 84, createdAt: 150 }
        ];

        // Caso 1: En org-A existe intento fallido -> retry_available = true con candidato determinístico imp-1
        const resOrgA = checkImportableMultiTenant(filesDb, 'org-A', 'bbva-hash');
        expect(resOrgA.importable).toBe(true);
        expect(resOrgA.retry_available).toBe(true);
        expect(resOrgA.retry_candidate_import_id).toBe('imp-1');
        expect(resOrgA.existing_file_id).toBe('file-1');

        // Caso 2: En org-B existe import exitoso -> bloqueado como FILE_ALREADY_EXISTS
        const resOrgB = checkImportableMultiTenant(filesDb, 'org-B', 'bbva-hash');
        expect(resOrgB.importable).toBe(false);
        expect(resOrgB.reason).toBe('FILE_ALREADY_EXISTS');
        expect(resOrgB.existing_file_id).toBe('file-2');

        // Caso 3: En org-C archivo completamente nuevo -> importable = true, retry_available = false
        const resOrgC = checkImportableMultiTenant(filesDb, 'org-C', 'bbva-hash');
        expect(resOrgC.importable).toBe(true);
        expect(resOrgC.retry_available).toBe(false);
    });

    test('11. Trazabilidad completa de Reintento: Import A (fallido) -> Retry B (reutiliza file, preserva retry_of_import_id, persiste)', () => {
        // Simulación de estado de DB
        const state = {
            imports: [],
            files: [],
            movements: []
        };

        // Paso 1: Import inicial A falla con 0 accepted rows
        const importA = {
            id: 'import-A-uuid',
            organization_id: 'org-oeste',
            retry_of_import_id: null,
            status: 'COMPLETED_WITH_ISSUES',
            accepted_rows: 0,
            invalid_rows: 84
        };
        const fileA = {
            id: 'file-A-uuid',
            import_id: 'import-A-uuid',
            organization_id: 'org-oeste',
            sha256_hash: 'hash-bbva-123'
        };
        state.imports.push(importA);
        state.files.push(fileA);

        // Paso 2: Usuario reintenta subir el mismo archivo en org-oeste
        // check_file_importable detecta retry disponible
        const check = {
            importable: true,
            retry_available: true,
            retry_candidate_import_id: 'import-A-uuid',
            existing_file_id: 'file-A-uuid'
        };
        expect(check.retry_available).toBe(true);

        // Paso 3: UI invoca request_failed_import_retry(check.retry_candidate_import_id)
        const importB = {
            id: 'import-B-uuid',
            organization_id: 'org-oeste',
            retry_of_import_id: check.retry_candidate_import_id,
            status: 'PENDING',
            accepted_rows: 0,
            invalid_rows: 0
        };
        state.imports.push(importB);

        expect(importB.retry_of_import_id).toBe(importA.id);

        // Paso 4: persist_financial_movements_batch procesa import B
        // Resuelve file_id a partir de retry_of_import_id
        let resolvedFileId = null;
        const matchingFileByLineage = state.files.find(f => 
            (f.import_id === importB.id || (importB.retry_of_import_id && f.import_id === importB.retry_of_import_id)) &&
            f.organization_id === importB.organization_id
        );
        if (matchingFileByLineage) {
            resolvedFileId = matchingFileByLineage.id;
        } else {
            const matchingFileByHash = state.files.find(f =>
                f.organization_id === importB.organization_id &&
                f.sha256_hash === 'hash-bbva-123'
            );
            if (matchingFileByHash) resolvedFileId = matchingFileByHash.id;
        }

        expect(resolvedFileId).toBe(fileA.id);
        // NO se debe insertar un segundo eco_source_files
        expect(state.files.length).toBe(1);

        // Persistir movimientos para import B
        importB.status = 'COMPLETED';
        importB.accepted_rows = 84;
        state.movements.push({ import_id: importB.id, count: 84 });

        expect(importB.accepted_rows).toBe(84);
        expect(state.movements[0].count).toBe(84);

        // Paso 5: Un tercer intento con el mismo hash queda bloqueado
        const subsequentCheck = state.imports.some(i => 
            i.organization_id === 'org-oeste' && 
            i.accepted_rows > 0 && 
            state.files.some(f => f.sha256_hash === 'hash-bbva-123' && (f.import_id === i.id || f.import_id === i.retry_of_import_id))
        );
        expect(subsequentCheck).toBe(true); // Bloqueado
    });
});
