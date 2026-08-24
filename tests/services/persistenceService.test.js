import { jest } from '@jest/globals';

// 1. Mock de Supabase Client antes de importar persistenceService
const mockRpc = jest.fn();
const mockUpload = jest.fn();
const mockRemove = jest.fn();

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: mockRpc,
        storage: {
            from: jest.fn(() => ({
                upload: mockUpload,
                remove: mockRemove
            }))
        }
    }
}));

// 2. Import dinámico de persistenceService con el module mock cargado
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');
const { supabase } = await import('../../src/js/core/services/supabaseClient.js');

describe('PersistenceService Unit Tests', () => {

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('should calculate SHA-256 hash in hex lowercase format of 64 characters', async () => {
        const dummyContent = 'Contenido de prueba para Hashing SHA-256';
        const dummyBlob = new Blob([dummyContent], { type: 'text/plain' });

        const hashHex = await persistenceService.sha256File(dummyBlob);

        expect(typeof hashHex).toBe('string');
        expect(hashHex).toHaveLength(64);
        expect(hashHex).toMatch(/^[0-9a-f]{64}$/);
    });

    it('should sanitize filename correctly using getSafeFilename', () => {
        const unsafeName = '1.1 Mis Comprobantes Recibidos (CUIT 30-68992077-9) #1!.xlsx';
        const safeName = persistenceService.getSafeFilename(unsafeName);

        expect(safeName).toBe('1.1_Mis_Comprobantes_Recibidos_CUIT_30-68992077-9_1_.xlsx');
        expect(safeName).not.toContain(' ');
        expect(safeName).not.toContain('(');
        expect(safeName).not.toContain('#');
    });

    it('should derive MIME fallback by extension when mimeType is empty', () => {
        expect(persistenceService.getMimeTypeFallback('report.xls', '')).toBe('application/vnd.ms-excel');
        expect(persistenceService.getMimeTypeFallback('data.xlsx', null)).toBe('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        expect(persistenceService.getMimeTypeFallback('list.csv', '  ')).toBe('text/csv');
        expect(persistenceService.getMimeTypeFallback('log.txt', '')).toBe('text/plain');
        expect(persistenceService.getMimeTypeFallback('doc.pdf', 'application/pdf')).toBe('application/pdf');
    });

    it('should call check_file_importable RPC and return normalized response when importable', async () => {
        mockRpc.mockResolvedValueOnce({
            data: { importable: true },
            error: null
        });

        const hash = 'a'.repeat(64);
        const result = await persistenceService.checkFileImportable(hash);

        expect(mockRpc).toHaveBeenCalledWith('check_file_importable', { p_sha256_hash: hash });
        expect(result.importable).toBe(true);
    });

    it('should handle check_file_importable duplicate response', async () => {
        mockRpc.mockResolvedValueOnce({
            data: { importable: false, reason: 'FILE_ALREADY_EXISTS', existing_file_id: 'uuid-123' },
            error: null
        });

        const hash = 'b'.repeat(64);
        const result = await persistenceService.checkFileImportable(hash);

        expect(result.importable).toBe(false);
        expect(result.reason).toBe('FILE_ALREADY_EXISTS');
        expect(result.existing_file_id).toBe('uuid-123');
    });

    it('should call create_import RPC and return import metadata', async () => {
        const mockReturn = {
            import_id: 'imp-111',
            organization_id: 'org-222',
            storage_prefix: 'org-222/imp-111'
        };

        mockRpc.mockResolvedValueOnce({
            data: mockReturn,
            error: null
        });

        const result = await persistenceService.createImport('ARCA_RECIBIDOS', 'COMPRA');

        expect(mockRpc).toHaveBeenCalledWith('create_import', {
            p_source_type: 'ARCA_RECIBIDOS',
            p_operation_type: 'COMPRA'
        });
        expect(result).toEqual(mockReturn);
    });

    it('should upload source file to private storage bucket', async () => {
        mockUpload.mockResolvedValueOnce({
            data: { path: 'org-222/imp-111/clean_file.xlsx' },
            error: null
        });

        const dummyFile = new File(['content'], 'test.xlsx', { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });

        const result = await persistenceService.uploadSourceFile({
            file: dummyFile,
            storagePrefix: 'org-222/imp-111',
            safeFilename: 'clean_file.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        });

        expect(supabase.storage.from).toHaveBeenCalledWith('eco-imports-private-staging');
        expect(mockUpload).toHaveBeenCalledWith(
            'org-222/imp-111/clean_file.xlsx',
            dummyFile,
            { contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', upsert: false }
        );
        expect(result.path).toBe('org-222/imp-111/clean_file.xlsx');
    });

    it('should call storage remove during cleanupStorageFile', async () => {
        mockRemove.mockResolvedValueOnce({ data: [], error: null });

        await persistenceService.cleanupStorageFile('org-222/imp-111/failed_file.xlsx');

        expect(supabase.storage.from).toHaveBeenCalledWith('eco-imports-private-staging');
        expect(mockRemove).toHaveBeenCalledWith(['org-222/imp-111/failed_file.xlsx']);
    });

    it('should call persist_import_batch RPC with exact expected payload', async () => {
        mockRpc.mockResolvedValueOnce({
            data: { import_id: 'imp-111', accepted_rows: 1, status: 'COMPLETED' },
            error: null
        });

        const fileInfo = {
            original_name: 'recibidos.xlsx',
            storage_path: 'org-222/imp-111/recibidos.xlsx',
            mime_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            size_bytes: 1024,
            sha256_hash: 'c'.repeat(64)
        };

        const stagedRows = [
            {
                sourceRowNumber: 1,
                rawRow: ['2026-05-01', 'Factura A', '20111111112', '1000'],
                normalizedData: { fecha: '2026-05-01', cuit: '20111111112', total: 1000 },
                errors: [],
                warnings: []
            }
        ];

        const result = await persistenceService.persistImportBatch({
            importId: 'imp-111',
            fileInfo,
            stagedRows
        });

        expect(mockRpc).toHaveBeenCalledWith('persist_import_batch', {
            p_import_id: 'imp-111',
            p_file_info: fileInfo,
            p_staged_rows: [
                {
                    sourceRowNumber: 1,
                    rawRow: ['2026-05-01', 'Factura A', '20111111112', '1000'],
                    normalizedData: { fecha: '2026-05-01', cuit: '20111111112', total: 1000 },
                    errors: [],
                    warnings: []
                }
            ]
        });
        expect(result.status).toBe('COMPLETED');
    });

    it('should load active fiscal records and map them to appStore format', async () => {
        const mockDbRecords = [
            {
                id: 'rec-1',
                organization_id: 'org-222',
                record_type: 'ARCA_RECIBIDOS',
                status: 'ACCEPTED',
                fecha: '2026-05-15',
                cuit: '30689920779',
                razon_social: 'Proveedor Test S.A.',
                comprobante: '1-1-100',
                total: 1210,
                tipo_operacion: 'COMPRA',
                confirmada: false,
                normalized_payload: {
                    fecha: '2026-05-15',
                    cuit: '30689920779',
                    tipo_cbte: 1,
                    pdv: 1,
                    nroDesde: 100,
                    total: 1210,
                    totalIva: 210,
                    netoGravado: 1000
                }
            }
        ];

        mockRpc.mockResolvedValueOnce({
            data: mockDbRecords,
            error: null
        });

        const items = await persistenceService.loadActiveFiscalRecords();

        expect(mockRpc).toHaveBeenCalledWith('get_active_normalized_records');
        expect(items).toHaveLength(1);
        expect(items[0].id).toBe('rec-1');
        expect(items[0].tipo).toBe('recibido');
        expect(items[0].tipoOperacion).toBe('COMPRA');
        expect(items[0].cuit).toBe('30689920779');
        expect(items[0].total).toBe(1210);
        expect(items[0].netoGravado).toBe(1000);
        expect(items[0].totalIva).toBe(210);
    });

    it('should call create_import RPC for ARCA_EMITIDOS / VENTA', async () => {
        const mockReturn = {
            import_id: 'imp-333',
            organization_id: 'org-222',
            storage_prefix: 'org-222/imp-333'
        };

        mockRpc.mockResolvedValueOnce({
            data: mockReturn,
            error: null
        });

        const result = await persistenceService.createImport('ARCA_EMITIDOS', 'VENTA');

        expect(mockRpc).toHaveBeenCalledWith('create_import', {
            p_source_type: 'ARCA_EMITIDOS',
            p_operation_type: 'VENTA'
        });
        expect(result).toEqual(mockReturn);
    });

    it('should load active fiscal records and discriminate ARCA_RECIBIDOS (COMPRA) vs ARCA_EMITIDOS (VENTA) while ignoring non-ARCA types', async () => {
        const mockDbRecords = [
            {
                id: 'rec-1',
                organization_id: 'org-222',
                record_type: 'ARCA_RECIBIDOS',
                status: 'ACCEPTED',
                fecha: '2026-05-15',
                cuit: '30689920779',
                razon_social: 'Proveedor Test S.A.',
                comprobante: '1-1-100',
                total: 1210,
                tipo_operacion: 'COMPRA',
                confirmada: false,
                normalized_payload: { fecha: '2026-05-15', cuit: '30689920779', razonSocial: 'Proveedor Test S.A.' }
            },
            {
                id: 'rec-2',
                organization_id: 'org-222',
                record_type: 'ARCA_EMITIDOS',
                status: 'ACCEPTED',
                fecha: '2026-05-16',
                cuit: '20333333339',
                razon_social: 'Cliente Receptor S.R.L.',
                comprobante: '6-1-50',
                total: 5000,
                tipo_operacion: 'VENTA',
                confirmada: true,
                normalized_payload: { fecha: '2026-05-16', cuit: '20333333339', razonSocial: 'Cliente Receptor S.R.L.' }
            },
            {
                id: 'rec-3',
                organization_id: 'org-222',
                record_type: 'PERCEPCIONES_ARBA',
                status: 'ACCEPTED',
                fecha: '2026-05-17',
                cuit: '30999999999',
                total: 300,
                tipo_operacion: 'PERCEPCION',
                normalized_payload: { fecha: '2026-05-17' }
            }
        ];

        mockRpc.mockResolvedValueOnce({
            data: mockDbRecords,
            error: null
        });

        const items = await persistenceService.loadActiveFiscalRecords();

        expect(mockRpc).toHaveBeenCalledWith('get_active_normalized_records');
        expect(items).toHaveLength(2); // PERCEPCIONES IGNORED FROM PERSISTENCE REHYDRATION
        
        expect(items[0].id).toBe('rec-1');
        expect(items[0].tipo).toBe('recibido');
        expect(items[0].tipoOperacion).toBe('COMPRA');
        expect(items[0].razonSocial).toBe('Proveedor Test S.A.');

        expect(items[1].id).toBe('rec-2');
        expect(items[1].tipo).toBe('emitido');
        expect(items[1].tipoOperacion).toBe('VENTA');
        expect(items[1].cuit).toBe('20333333339');
        expect(items[1].razonSocial).toBe('Cliente Receptor S.R.L.');
        expect(items[1].confirmada).toBe(true);
    });

    describe('Date Normalization Logic (Migration 011/013.3 SQL specification)', () => {
        function normalizeDateSql(dateRaw) {
            if (!dateRaw || typeof dateRaw !== 'string') {
                throw new Error('Invalid date format');
            }
            const trimmed = dateRaw.trim();
            if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
                const parts = trimmed.split('-').map(Number);
                const d = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2]));
                const year = d.getUTCFullYear();
                const month = String(d.getUTCMonth() + 1).padStart(2, '0');
                const day = String(d.getUTCDate()).padStart(2, '0');
                const reformat = `${year}-${month}-${day}`;
                if (reformat !== trimmed) throw new Error(`Invalid calendar date: ${trimmed}`);
                return reformat;
            } else if (/^\d{2}\/\d{2}\/\d{4}$/.test(trimmed)) {
                const parts = trimmed.split('/').map(Number);
                const d = new Date(Date.UTC(parts[2], parts[1] - 1, parts[0]));
                const year = d.getUTCFullYear();
                const month = String(d.getUTCMonth() + 1).padStart(2, '0');
                const day = String(d.getUTCDate()).padStart(2, '0');
                const reformat = `${day}/${month}/${year}`;
                if (reformat !== trimmed) throw new Error(`Invalid calendar date: ${trimmed}`);
                return `${year}-${month}-${day}`;
            } else if (/^\d{2}-\d{2}-\d{4}$/.test(trimmed)) {
                const parts = trimmed.split('-').map(Number);
                const d = new Date(Date.UTC(parts[2], parts[1] - 1, parts[0]));
                const year = d.getUTCFullYear();
                const month = String(d.getUTCMonth() + 1).padStart(2, '0');
                const day = String(d.getUTCDate()).padStart(2, '0');
                const reformat = `${day}-${month}-${year}`;
                if (reformat !== trimmed) throw new Error(`Invalid calendar date: ${trimmed}`);
                return `${year}-${month}-${day}`;
            } else {
                throw new Error(`Invalid date format: "${trimmed}". Expected YYYY-MM-DD, DD/MM/YYYY or DD-MM-YYYY`);
            }
        }

        it('should correctly normalize DD/MM/YYYY format to YYYY-MM-DD', () => {
            expect(normalizeDateSql('13/05/2026')).toBe('2026-05-13');
            expect(normalizeDateSql('01/05/2026')).toBe('2026-05-01');
            expect(normalizeDateSql('31/12/2025')).toBe('2025-12-31');
        });

        it('should correctly normalize DD-MM-YYYY format to YYYY-MM-DD (Migration 013.3)', () => {
            expect(normalizeDateSql('30-06-2026')).toBe('2026-06-30');
            expect(normalizeDateSql('29-06-2026')).toBe('2026-06-29');
            expect(normalizeDateSql('29-02-2028')).toBe('2028-02-29'); // Leap year valid
        });

        it('should correctly accept YYYY-MM-DD format', () => {
            expect(normalizeDateSql('2026-05-13')).toBe('2026-05-13');
            expect(normalizeDateSql('2026-01-01')).toBe('2026-01-01');
        });

        it('should reject invalid calendar dates such as 31/02/2026, 29-02-2026 or 31-04-2026', () => {
            expect(() => normalizeDateSql('31/02/2026')).toThrow(/Invalid calendar date/);
            expect(() => normalizeDateSql('2026-02-31')).toThrow(/Invalid calendar date/);
            expect(() => normalizeDateSql('29-02-2026')).toThrow(/Invalid calendar date/);
            expect(() => normalizeDateSql('31-04-2026')).toThrow(/Invalid calendar date/);
        });

        it('should reject empty or malformed date strings', () => {
            expect(() => normalizeDateSql('')).toThrow(/Invalid date/);
            expect(() => normalizeDateSql('fecha_invalida')).toThrow(/Invalid date/);
            expect(() => normalizeDateSql('13_05_2026')).toThrow(/Invalid date/);
        });
    });

    describe('persistPerceptionsBatch RPC Integration', () => {
        it('should invoke public.persist_perceptions_batch with formatted payload', async () => {
            const mockReturn = {
                import_id: 'import-percep-123',
                total_rows: 1,
                accepted_rows: 1,
                invalid_rows: 0,
                duplicate_rows: 0,
                issue_rows: 0,
                status: 'COMPLETED'
            };

            mockRpc.mockResolvedValueOnce({
                data: mockReturn,
                error: null
            });

            const result = await persistenceService.persistPerceptionsBatch({
                importId: 'import-percep-123',
                fileInfo: {
                    original_name: 'percepciones_arba.txt',
                    storage_path: 'org-1/import-percep-123/percepciones_arba.txt',
                    mime_type: 'text/plain',
                    size_bytes: 1024,
                    sha256_hash: 'a'.repeat(64)
                },
                stagedRows: [
                    {
                        sourceRowNumber: 1,
                        rawRow: '006230-68992077-9 15/05/2026000100000000000000000000010000000001000,00',
                        normalizedData: {
                            cuit: '30689920779',
                            fecha: '15/05/2026',
                            regimen: '0062',
                            sucursal: '0001',
                            comprobante: '000000000000000000000100',
                            monto: 1000
                        },
                        errors: [],
                        warnings: []
                    }
                ]
            });

            expect(mockRpc).toHaveBeenCalledWith('persist_perceptions_batch', {
                p_import_id: 'import-percep-123',
                p_file_info: {
                    original_name: 'percepciones_arba.txt',
                    storage_path: 'org-1/import-percep-123/percepciones_arba.txt',
                    mime_type: 'text/plain',
                    size_bytes: 1024,
                    sha256_hash: 'a'.repeat(64)
                },
                p_staged_rows: [
                    {
                        sourceRowNumber: 1,
                        rawRow: '006230-68992077-9 15/05/2026000100000000000000000000010000000001000,00',
                        normalizedData: {
                            cuit: '30689920779',
                            fecha: '15/05/2026',
                            regimen: '0062',
                            sucursal: '0001',
                            comprobante: '000000000000000000000100',
                            monto: 1000
                        },
                        errors: [],
                        warnings: []
                    }
                ]
            });

            expect(result).toEqual(mockReturn);
        });
    });
});
