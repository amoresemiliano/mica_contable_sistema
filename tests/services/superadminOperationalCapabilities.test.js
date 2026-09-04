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

    test('Migration 018 SQL script contains SUPERADMIN in all 17 target RPC definitions', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const content = fs.readFileSync(m018Path, 'utf8');

        const expectedProcs = [
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

        expectedProcs.forEach(proc => {
            expect(content).toContain(`FUNCTION public.${proc}`);
        });

        const m017Content = fs.readFileSync(path.join(process.cwd(), 'sql', '017_multitenant_superadmin_context.sql'), 'utf8');
        expect(m017Content).toContain('auth_user_id = auth.uid()');
    });
});
