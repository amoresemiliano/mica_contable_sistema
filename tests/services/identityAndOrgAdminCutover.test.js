import { jest } from '@jest/globals';
import fs from 'fs';
import path from 'path';

describe('WP-A3.2.1 Identity, Profiles & Organization Administration Cutover', () => {

    test('Verification: Migration 022 SQL files and DB test harness exist and are well-formed', () => {
        const preflightPath = path.join(process.cwd(), 'sql', '022_identity_and_org_admin_preflight.sql');
        const upPath = path.join(process.cwd(), 'sql', '022_identity_and_org_admin.sql');
        const downPath = path.join(process.cwd(), 'sql', '022_identity_and_org_admin_down.sql');
        const postcheckPath = path.join(process.cwd(), 'sql', '022_identity_and_org_admin_postcheck.sql');
        const dbTestPath = path.join(process.cwd(), 'tests', 'db', '022_identity_and_org_admin.sql');

        expect(fs.existsSync(preflightPath)).toBe(true);
        expect(fs.existsSync(upPath)).toBe(true);
        expect(fs.existsSync(downPath)).toBe(true);
        expect(fs.existsSync(postcheckPath)).toBe(true);
        expect(fs.existsSync(dbTestPath)).toBe(true);

        const upContent = fs.readFileSync(upPath, 'utf8');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.change_user_role');
        expect(upContent).toContain('ORG_MEMBER_PERMISSION_MANAGE');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.set_user_active');
        expect(upContent).toContain('ORG_MEMBER_MANAGE');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context');
        expect(upContent).toContain('SUPPORT_IMPERSONATE');
        expect(upContent).toContain('authorized_orgs_for_capability(\'ORG_VIEW\')');
        expect(upContent).toContain('authorized_orgs_for_capability(\'ORG_MEMBER_VIEW\')');
        expect(upContent).toContain('authorized_orgs_for_capability(\'AUDIT_VIEW_ORG\')');

        // Forward migration must NOT use legacy func_role() checks
        expect(upContent).not.toContain('func_role()');

        const downContent = fs.readFileSync(downPath, 'utf8');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.change_user_role');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.set_user_active');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context');
        expect(downContent).toContain('private.func_role() <> \'ADMIN\'');
        expect(downContent).toContain('v_caller_role != \'SUPERADMIN\'');
        expect(downContent).not.toContain('DROP TABLE');

        const dbTestContent = fs.readFileSync(dbTestPath, 'utf8');
        expect(dbTestContent).toContain('BEGIN;');
        expect(dbTestContent).toContain('ROLLBACK;');
        expect(dbTestContent).toContain('sql/022_identity_and_org_admin.sql');
        expect(dbTestContent).toContain('SELF_ROLE_CHANGE_NOT_ALLOWED');
        expect(dbTestContent).toContain('SELF_DEACTIVATION_NOT_ALLOWED');
    });

    test('Identity, Profile & Org Admin Capability Decision Model', () => {
        // Semantic simulator for MICA authorization
        const NORTE = '38419581-8163-482c-9813-616fa6214d71';
        const SUR = 'c7af5a5c-1aac-4add-9873-8073044bf979';
        const OESTE = '1f5d071f-a09e-4825-9f12-88533383599e';

        const templates = {
            PLATFORM_SUPERADMIN: {
                platformCaps: ['PLATFORM_MANAGE', 'SUPPORT_IMPERSONATE', 'ACCESS_ANY_ORG', 'AUDIT_PLATFORM_VIEW'],
                orgCaps: []
            },
            ACCOUNTING_SUPERADMIN: {
                platformCaps: ['GLOBAL_CATALOG_VIEW', 'CATALOG_ASSIGN_ANY_ORG', 'RATE_MANAGE_ANY_ORG', 'REPORT_COMPARE_SCOPED_ORGS'],
                bridgeOrgCaps: ['ORG_VIEW', 'RECORD_VIEW', 'AUDIT_VIEW_ORG', 'REPORT_VIEW']
            },
            TENANT_ADMIN: {
                platformCaps: [],
                orgCaps: [
                    'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'ORG_SETTINGS_MANAGE', 'ORG_MEMBER_VIEW',
                    'ORG_MEMBER_INVITE', 'ORG_MEMBER_MANAGE', 'ORG_MEMBER_PERMISSION_MANAGE',
                    'IMPORT_VIEW', 'IMPORT_CREATE', 'RECORD_VIEW', 'AUDIT_VIEW_ORG'
                ]
            },
            UPLOADER: {
                platformCaps: [],
                orgCaps: ['ORG_VIEW', 'IMPORT_VIEW', 'IMPORT_CREATE', 'RECORD_VIEW']
            }
        };

        const users = {
            VEGEN: {
                profile: { id: 'prof-vegen', is_active: true },
                platformRole: 'PLATFORM_SUPERADMIN',
                memberships: []
            },
            Marianela: {
                profile: { id: 'prof-marianela', is_active: true },
                platformRole: 'ACCOUNTING_SUPERADMIN',
                memberships: [
                    { org_id: NORTE, is_active: true },
                    { org_id: SUR, is_active: true },
                    { org_id: OESTE, is_active: true }
                ]
            },
            Emiliano: {
                profile: { id: 'prof-emiliano', is_active: true },
                platformRole: null,
                memberships: [{ org_id: NORTE, template: 'TENANT_ADMIN', is_active: true }]
            },
            SynthUploader: {
                profile: { id: 'prof-uploader', is_active: true },
                platformRole: null,
                memberships: [{ org_id: NORTE, template: 'UPLOADER', is_active: true }]
            },
            InactiveUser: {
                profile: { id: 'prof-inactive', is_active: false },
                platformRole: null,
                memberships: [{ org_id: NORTE, template: 'TENANT_ADMIN', is_active: true }]
            }
        };

        const evaluateCanOrg = (user, orgId, capability, override = null) => {
            if (!user.profile.is_active) return false;
            const membership = user.memberships.find(m => m.org_id === orgId && m.is_active);
            if (!membership) return false;

            if (override === 'DENY') return false;
            if (override === 'ALLOW') return true;

            // Platform bridge check (Accounting Superadmin)
            if (user.platformRole === 'ACCOUNTING_SUPERADMIN') {
                const tpl = templates.ACCOUNTING_SUPERADMIN;
                if (tpl.bridgeOrgCaps.includes(capability)) return true;
            }

            // Tenant template check
            if (membership.template && templates[membership.template]) {
                const tpl = templates[membership.template];
                if (tpl.orgCaps.includes(capability)) return true;
            }

            return false;
        };

        const evaluateCanPlatform = (user, capability) => {
            if (!user.profile.is_active) return false;
            if (!user.platformRole) return false;
            const tpl = templates[user.platformRole];
            return tpl ? tpl.platformCaps.includes(capability) : false;
        };

        // 1. Role modification authorization
        expect(evaluateCanOrg(users.Emiliano, NORTE, 'ORG_MEMBER_PERMISSION_MANAGE')).toBe(true);
        expect(evaluateCanOrg(users.Emiliano, SUR, 'ORG_MEMBER_PERMISSION_MANAGE')).toBe(false); // Tenant isolation
        expect(evaluateCanOrg(users.SynthUploader, NORTE, 'ORG_MEMBER_PERMISSION_MANAGE')).toBe(false); // Base deny
        expect(evaluateCanOrg(users.SynthUploader, NORTE, 'ORG_MEMBER_PERMISSION_MANAGE', 'ALLOW')).toBe(true); // Override allow
        expect(evaluateCanOrg(users.Emiliano, NORTE, 'ORG_MEMBER_PERMISSION_MANAGE', 'DENY')).toBe(false); // Override deny
        expect(evaluateCanOrg(users.InactiveUser, NORTE, 'ORG_MEMBER_PERMISSION_MANAGE')).toBe(false); // Inactive fail-closed

        // 2. Member status management authorization
        expect(evaluateCanOrg(users.Emiliano, NORTE, 'ORG_MEMBER_MANAGE')).toBe(true);
        expect(evaluateCanOrg(users.Emiliano, SUR, 'ORG_MEMBER_MANAGE')).toBe(false);
        expect(evaluateCanOrg(users.SynthUploader, NORTE, 'ORG_MEMBER_MANAGE')).toBe(false);

        // 3. Superadmin context switching authorization
        expect(evaluateCanPlatform(users.VEGEN, 'SUPPORT_IMPERSONATE')).toBe(true);
        expect(evaluateCanPlatform(users.Marianela, 'SUPPORT_IMPERSONATE')).toBe(false);
        expect(evaluateCanPlatform(users.Emiliano, 'SUPPORT_IMPERSONATE')).toBe(false);

        // 4. Audit log visibility
        expect(evaluateCanOrg(users.Emiliano, NORTE, 'AUDIT_VIEW_ORG')).toBe(true);
        expect(evaluateCanOrg(users.Emiliano, SUR, 'AUDIT_VIEW_ORG')).toBe(false);
        expect(evaluateCanOrg(users.Marianela, NORTE, 'AUDIT_VIEW_ORG')).toBe(true);
        expect(evaluateCanOrg(users.Marianela, SUR, 'AUDIT_VIEW_ORG')).toBe(true);
        expect(evaluateCanOrg(users.SynthUploader, NORTE, 'AUDIT_VIEW_ORG')).toBe(false);
    });
});
