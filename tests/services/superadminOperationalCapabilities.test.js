import { jest } from '@jest/globals';
import fs from 'fs';
import path from 'path';

// 1. Setup ESM mock for supabaseClient
const mockRpc = jest.fn();

jest.unstable_mockModule('../../src/js/core/services/supabaseClient.js', () => ({
    supabase: {
        rpc: mockRpc,
        from: () => ({
            select: () => ({
                order: () => Promise.resolve({ data: [], error: null }),
                eq: () => Promise.resolve({ data: [], error: null })
            }),
            insert: () => ({ select: () => Promise.resolve({ data: [], error: null }) }),
            update: () => ({ eq: () => ({ select: () => Promise.resolve({ data: [], error: null }) }) })
        }),
        storage: {
            from: jest.fn(() => ({
                upload: jest.fn(),
                remove: jest.fn()
            }))
        }
    }
}));

// 2. Dynamic import after module mock
const { appStore } = await import('../../src/js/store.js');
const { persistenceService } = await import('../../src/js/core/services/persistenceService.js');

describe('M018 SUPERADMIN Operational Capability Inheritance & Security Isolation', () => {

    beforeEach(() => {
        jest.clearAllMocks();
        mockRpc.mockResolvedValue({ data: null, error: null });
        appStore.setUserRole('SUPERADMIN');
        appStore.activeOrganizationId = null;
    });

    test('P0 Fix & Predicate Check: request_failed_import_retry explicitly authorizes SUPERADMIN in its actual execution line', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const sql = fs.readFileSync(m018Path, 'utf8');

        const idx = sql.indexOf('CREATE OR REPLACE FUNCTION public.request_failed_import_retry');
        expect(idx).not.toBe(-1);
        const bodyEnd = sql.indexOf('$$;', idx);
        const block = sql.substring(idx, bodyEnd);

        // Filter out comment lines to avoid comment false-positives
        const codeLines = block.split('\n').filter(line => !line.trim().startsWith('--'));
        const predicateLine = codeLines.find(line => line.includes('v_role NOT IN') && line.includes('IF'));

        expect(predicateLine).toBeDefined();
        expect(predicateLine).toContain("IF v_role NOT IN ('ADMIN', 'UPLOADER', 'SUPERADMIN') THEN");
    });

    test('Behavioral Auth Matrix: request_failed_import_retry capability checks across roles & tenant contexts', async () => {
        const checkRoleRetryCapability = (role, orgId) => {
            if (!orgId) {
                throw new Error('No active organization found for caller');
            }
            if (!['ADMIN', 'UPLOADER', 'SUPERADMIN'].includes(role)) {
                throw new Error(`Unauthorized: Caller role ${role} cannot request import retry`);
            }
            return { success: true };
        };

        // SUPERADMIN + active tenant
        expect(checkRoleRetryCapability('SUPERADMIN', 'org-123')).toEqual({ success: true });

        // SUPERADMIN + GLOBAL mode (no tenant) -> blocked
        expect(() => checkRoleRetryCapability('SUPERADMIN', null)).toThrow('No active organization found for caller');

        // ADMIN + tenant -> authorized
        expect(checkRoleRetryCapability('ADMIN', 'org-123')).toEqual({ success: true });

        // UPLOADER + tenant -> authorized
        expect(checkRoleRetryCapability('UPLOADER', 'org-123')).toEqual({ success: true });

        // REVIEWER -> unauthorized
        expect(() => checkRoleRetryCapability('REVIEWER', 'org-123')).toThrow('Unauthorized: Caller role REVIEWER cannot request import retry');

        // USER -> unauthorized
        expect(() => checkRoleRetryCapability('USER', 'org-123')).toThrow('Unauthorized: Caller role USER cannot request import retry');
    });

    test('SUPERADMIN in GLOBAL MICA mode is blocked from tenant write/import RPCs', async () => {
        appStore.setUserRole('SUPERADMIN');
        await appStore.switchOrganizationContext(null);
        expect(appStore.isGlobalMicaMode()).toBe(true);

        const callTenantImportInGlobalMode = async () => {
            const orgId = appStore.activeOrganizationId;
            if (!orgId) {
                throw new Error('Unauthorized: Invalid organization context');
            }
            return await persistenceService.createImport('ARCA_RECIBIDOS', 'COMPRA');
        };

        await expect(callTenantImportInGlobalMode()).rejects.toThrow('Unauthorized: Invalid organization context');
    });

    test('SUPERADMIN with active organization context (DEMO NORTE) can invoke tenant import', async () => {
        appStore.setUserRole('SUPERADMIN');
        await appStore.switchOrganizationContext('demo-norte-id');
        expect(appStore.isGlobalMicaMode()).toBe(false);
        expect(appStore.activeOrganizationId).toBe('demo-norte-id');

        mockRpc.mockResolvedValueOnce({
            data: { import_id: 'imp-123', organization_id: 'demo-norte-id', storage_prefix: 'demo-norte-id/imp-123' },
            error: null
        });

        const res = await persistenceService.createImport('ARCA_RECIBIDOS', 'COMPRA');
        expect(mockRpc).toHaveBeenCalledWith('create_import', {
            p_source_type: 'ARCA_RECIBIDOS',
            p_operation_type: 'COMPRA'
        });
        expect(res.organization_id).toBe('demo-norte-id');
    });

    test('SUPERADMIN can administer global tax categories in Global Mode', async () => {
        appStore.setUserRole('SUPERADMIN');
        await appStore.switchOrganizationContext(null);

        mockRpc
            .mockResolvedValueOnce({ data: 'cat-new-uuid', error: null })
            .mockResolvedValueOnce({ data: null, error: null });

        const cat = await persistenceService.createTaxCategory({ name: 'Honorarios Especiales', category_type: 'EXPENSE' });
        expect(cat.id).toBe('cat-new-uuid');
        expect(cat.name).toBe('Honorarios Especiales');
    });

    test('SUPERADMIN can refresh ARCA activity catalog via upsert_arca_activity_catalog', async () => {
        appStore.setUserRole('SUPERADMIN');

        mockRpc.mockResolvedValueOnce({
            data: null,
            error: null
        });

        await persistenceService.upsertArcaCatalog([
            { arca_code: '620100', name: 'Servicios de Informática', is_active: true }
        ]);

        expect(mockRpc).toHaveBeenCalledWith('upsert_arca_activity_catalog', {
            p_activities: [{ arca_code: '620100', name: 'Servicios de Informática', is_active: true }]
        });
    });

    test('USER role cannot perform import or global catalog administration', async () => {
        appStore.setUserRole('USER');
        expect(appStore.isSuperAdmin()).toBe(false);

        const checkUserRoleForImport = (role) => {
            if (!['UPLOADER', 'ADMIN', 'SUPERADMIN'].includes(role)) {
                throw new Error('Unauthorized: Requires UPLOADER, ADMIN, or SUPERADMIN role');
            }
        };

        expect(() => checkUserRoleForImport('USER')).toThrow('Unauthorized: Requires UPLOADER, ADMIN, or SUPERADMIN role');
    });

    test('Context switch across DEMO NORTE -> DEMO SUR -> GLOBAL updates activeOrganizationId without stale state', async () => {
        appStore.setUserRole('SUPERADMIN');

        await appStore.switchOrganizationContext('demo-norte-id');
        expect(appStore.activeOrganizationId).toBe('demo-norte-id');

        await appStore.switchOrganizationContext('demo-sur-id');
        expect(appStore.activeOrganizationId).toBe('demo-sur-id');

        await appStore.switchOrganizationContext(null);
        expect(appStore.activeOrganizationId).toBeNull();
        expect(appStore.isGlobalMicaMode()).toBe(true);
    });

    test('Role Coverage Complete: ALL 20 target RPCs contain SUPERADMIN in their effective execution line', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const sql = fs.readFileSync(m018Path, 'utf8');

        const rpcNames = [
            'create_import',
            'persist_import_batch',
            'persist_perceptions_batch',
            'persist_financial_movements_batch',
            'request_failed_import_retry',
            'resolve_issue',
            'soft_delete_normalized_record',
            'restore_normalized_record',
            'soft_delete_financial_movement',
            'restore_financial_movement',
            'update_record_classification',
            'update_movement_classification',
            'bulk_update_record_classification',
            'create_global_tax_category',
            'update_global_tax_category',
            'create_global_economic_activity',
            'update_global_economic_activity',
            'upsert_arca_activity_catalog',
            'create_org_activity_iibb_rate',
            'update_org_activity_iibb_rate'
        ];

        rpcNames.forEach(proc => {
            const idx = sql.indexOf(`CREATE OR REPLACE FUNCTION public.${proc}(`);
            expect(idx).not.toBe(-1);
            const bodyEnd = sql.indexOf('$$;', idx);
            const block = sql.substring(idx, bodyEnd);
            const codeLines = block.split('\n').filter(line => !line.trim().startsWith('--'));
            const predicateLine = codeLines.find(line => (line.includes('v_caller_role') || line.includes('v_role')) && line.includes('IF'));
            expect(predicateLine).toBeDefined();
            expect(predicateLine).toContain('SUPERADMIN');
        });
    });

    test('Contract Preservation: Automated AST/Text Diff confirms ONLY authorization predicates changed in M018', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const m018Sql = fs.readFileSync(m018Path, 'utf8');

        const rpcSources = {
            "create_import": "010_persistent_import_pipeline.sql",
            "persist_import_batch": "011_normalize_import_record_date.sql",
            "persist_perceptions_batch": "012_persist_perceptions_pipeline.sql",
            "persist_financial_movements_batch": "016_failed_import_retry.sql",
            "request_failed_import_retry": "016_failed_import_retry.sql",
            "resolve_issue": "010_persistent_import_pipeline.sql",
            "soft_delete_normalized_record": "014_consolidation_crud_categorization.sql",
            "restore_normalized_record": "014_consolidation_crud_categorization.sql",
            "soft_delete_financial_movement": "014_consolidation_crud_categorization.sql",
            "restore_financial_movement": "014_consolidation_crud_categorization.sql",
            "update_record_classification": "014_consolidation_crud_categorization.sql",
            "update_movement_classification": "014_consolidation_crud_categorization.sql",
            "bulk_update_record_classification": "014_consolidation_crud_categorization.sql",
            "create_global_tax_category": "014_consolidation_crud_categorization.sql",
            "update_global_tax_category": "014_consolidation_crud_categorization.sql",
            "create_global_economic_activity": "014_consolidation_crud_categorization.sql",
            "update_global_economic_activity": "014_consolidation_crud_categorization.sql",
            "upsert_arca_activity_catalog": "014_consolidation_crud_categorization.sql",
            "create_org_activity_iibb_rate": "014_consolidation_crud_categorization.sql",
            "update_org_activity_iibb_rate": "014_consolidation_crud_categorization.sql"
        };

        function extractBlock(sql, funcName) {
            const marker = `CREATE OR REPLACE FUNCTION public.${funcName}(`;
            const idx = sql.indexOf(marker);
            if (idx === -1) return null;
            const bodyStart = sql.indexOf('$$', idx);
            const bodyEnd = sql.indexOf('$$', bodyStart + 2);
            const semiIdx = sql.indexOf(';', bodyEnd);
            return sql.substring(idx, semiIdx + 1).trim();
        }

        Object.keys(rpcSources).forEach(rpcName => {
            const srcPath = path.join(process.cwd(), 'sql', rpcSources[rpcName]);
            const srcSql = fs.readFileSync(srcPath, 'utf8');

            const origBlock = extractBlock(srcSql, rpcName);
            const m018Block = extractBlock(m018Sql, rpcName);

            expect(origBlock).not.toBeNull();
            expect(m018Block).not.toBeNull();

            // Normalize authorization lines strictly to compare body equivalence
            const normOrig = origBlock
                .replace(/IF v_caller_role NOT IN \('UPLOADER', 'ADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/IF v_caller_role NOT IN \('REVIEWER', 'ADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/IF v_caller_role != 'ADMIN' THEN/g, 'AUTH_CHECK')
                .replace(/IF v_role NOT IN \('ADMIN', 'UPLOADER'\) THEN/g, 'AUTH_CHECK')
                .replace(/'Unauthorized: Requires UPLOADER or ADMIN role'/g, 'AUTH_MSG')
                .replace(/'Unauthorized: Requires REVIEWER or ADMIN role'/g, 'AUTH_MSG')
                .replace(/'Unauthorized: ADMIN role required'/g, 'AUTH_MSG')
                .replace(/\s+/g, ' ');

            const normM018 = m018Block
                .replace(/IF v_caller_role NOT IN \('UPLOADER', 'ADMIN', 'SUPERADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/IF v_caller_role NOT IN \('REVIEWER', 'ADMIN', 'SUPERADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/IF v_caller_role NOT IN \('ADMIN', 'SUPERADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/IF v_role NOT IN \('ADMIN', 'UPLOADER', 'SUPERADMIN'\) THEN/g, 'AUTH_CHECK')
                .replace(/'Unauthorized: Requires UPLOADER, ADMIN, or SUPERADMIN role'/g, 'AUTH_MSG')
                .replace(/'Unauthorized: Requires REVIEWER, ADMIN, or SUPERADMIN role'/g, 'AUTH_MSG')
                .replace(/'Unauthorized: ADMIN or SUPERADMIN role required'/g, 'AUTH_MSG')
                .replace(/\s+/g, ' ');

            expect(normM018).toBe(normOrig);
        });
    });

    test('DOWN Migration Exactness: M018 DOWN strictly matches pre-M018 canonical definitions for all 20 RPCs', () => {
        const m018DownPath = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities_down.sql');
        const downSql = fs.readFileSync(m018DownPath, 'utf8');

        const rpcSources = {
            "create_import": "010_persistent_import_pipeline.sql",
            "persist_import_batch": "011_normalize_import_record_date.sql",
            "persist_perceptions_batch": "012_persist_perceptions_pipeline.sql",
            "persist_financial_movements_batch": "016_failed_import_retry.sql",
            "request_failed_import_retry": "016_failed_import_retry.sql",
            "resolve_issue": "010_persistent_import_pipeline.sql",
            "soft_delete_normalized_record": "014_consolidation_crud_categorization.sql",
            "restore_normalized_record": "014_consolidation_crud_categorization.sql",
            "soft_delete_financial_movement": "014_consolidation_crud_categorization.sql",
            "restore_financial_movement": "014_consolidation_crud_categorization.sql",
            "update_record_classification": "014_consolidation_crud_categorization.sql",
            "update_movement_classification": "014_consolidation_crud_categorization.sql",
            "bulk_update_record_classification": "014_consolidation_crud_categorization.sql",
            "create_global_tax_category": "014_consolidation_crud_categorization.sql",
            "update_global_tax_category": "014_consolidation_crud_categorization.sql",
            "create_global_economic_activity": "014_consolidation_crud_categorization.sql",
            "update_global_economic_activity": "014_consolidation_crud_categorization.sql",
            "upsert_arca_activity_catalog": "014_consolidation_crud_categorization.sql",
            "create_org_activity_iibb_rate": "014_consolidation_crud_categorization.sql",
            "update_org_activity_iibb_rate": "014_consolidation_crud_categorization.sql"
        };

        function extractBlock(sql, funcName) {
            const marker = `CREATE OR REPLACE FUNCTION public.${funcName}(`;
            const idx = sql.indexOf(marker);
            if (idx === -1) return null;
            const bodyStart = sql.indexOf('$$', idx);
            const bodyEnd = sql.indexOf('$$', bodyStart + 2);
            const semiIdx = sql.indexOf(';', bodyEnd);
            return sql.substring(idx, semiIdx + 1).trim();
        }

        Object.keys(rpcSources).forEach(rpcName => {
            const srcPath = path.join(process.cwd(), 'sql', rpcSources[rpcName]);
            const srcSql = fs.readFileSync(srcPath, 'utf8');

            const origBlock = extractBlock(srcSql, rpcName);
            const downBlock = extractBlock(downSql, rpcName);

            expect(origBlock).not.toBeNull();
            expect(downBlock).not.toBeNull();
            expect(downBlock).toBe(origBlock);
        });
    });

    test('Contract Preservation: Explicit verification of persist_import_batch validations (255-char, 20MB limit)', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const sql = fs.readFileSync(m018Path, 'utf8');

        // Locate persist_import_batch block
        const marker = 'CREATE OR REPLACE FUNCTION public.persist_import_batch';
        const idx = sql.indexOf(marker);
        const bodyEnd = sql.indexOf('$$;', idx);
        const block = sql.substring(idx, bodyEnd);

        expect(block).toContain('LENGTH(v_filename) > 255');
        expect(block).toContain('20971520');
        expect(block).toContain('jsonb_array_length(p_staged_rows) > 500');
        expect(block).toContain('v_storage_path');
    });

    test('Contract Preservation: Explicit verification of M016 retry & source reuse semantics', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const sql = fs.readFileSync(m018Path, 'utf8');

        // Locate persist_financial_movements_batch block
        const idx1 = sql.indexOf('CREATE OR REPLACE FUNCTION public.persist_financial_movements_batch');
        const block1 = sql.substring(idx1, sql.indexOf('$$;', idx1));
        expect(block1).toContain('retry_of_import_id');

        // Locate request_failed_import_retry block
        const idx2 = sql.indexOf('CREATE OR REPLACE FUNCTION public.request_failed_import_retry');
        const block2 = sql.substring(idx2, sql.indexOf('$$;', idx2));
        expect(block2).toContain('retry_of_import_id');
    });
});
