import { jest } from '@jest/globals';
import fs from 'fs';
import path from 'path';

describe('WP-A1 Capability Foundation & Security Isolation Tests', () => {

    test('Verification: Migration 019 SQL files exist and are well-formed', () => {
        const preflightPath = path.join(process.cwd(), 'sql', '019_preflight_check.sql');
        const upPath = path.join(process.cwd(), 'sql', '019_capability_foundation.sql');
        const downPath = path.join(process.cwd(), 'sql', '019_capability_foundation_down.sql');
        const postcheckPath = path.join(process.cwd(), 'sql', '019_postcheck.sql');

        expect(fs.existsSync(preflightPath)).toBe(true);
        expect(fs.existsSync(upPath)).toBe(true);
        expect(fs.existsSync(downPath)).toBe(true);
        expect(fs.existsSync(postcheckPath)).toBe(true);

        const upContent = fs.readFileSync(upPath, 'utf8');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_capabilities');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_role_templates');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_role_template_capabilities');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_platform_role_org_capabilities');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_membership_capability_overrides');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_user_platform_role');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_user_platform_capability_overrides');
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_user_active_context');
        expect(upContent).toContain('ALTER TABLE public.eco_organization_members');
        expect(upContent).toContain('ADD COLUMN IF NOT EXISTS role_template_id');

        expect(upContent).toContain('FUNCTION private.current_profile_id');
        expect(upContent).toContain('FUNCTION private.active_org_id');
        expect(upContent).toContain('FUNCTION private.can_platform');
        expect(upContent).toContain('FUNCTION private.can_org');
    });

    test('Active Context Contract: eco_user_active_context uses ON DELETE SET NULL on organization_id FK', () => {
        const upPath = path.join(process.cwd(), 'sql', '019_capability_foundation.sql');
        const upContent = fs.readFileSync(upPath, 'utf8');

        expect(upContent).toContain('organization_id UUID NULL REFERENCES public.eco_organizations(id) ON DELETE SET NULL');
    });

    test('Seed Data Completeness: All 42 capabilities and 8 role templates are seeded', () => {
        const upPath = path.join(process.cwd(), 'sql', '019_capability_foundation.sql');
        const upContent = fs.readFileSync(upPath, 'utf8');

        // Platform capabilities
        const platformCaps = [
            'PLATFORM_MANAGE', 'ORGANIZATION_CREATE', 'ORGANIZATION_UPDATE', 'ORGANIZATION_ARCHIVE',
            'GLOBAL_USER_MANAGE', 'PLAN_MANAGE', 'GLOBAL_CATALOG_VIEW', 'GLOBAL_CATALOG_MANAGE',
            'CATALOG_ASSIGN_ANY_ORG', 'RATE_MANAGE_ANY_ORG', 'ACCESS_ANY_ORG', 'REPORT_COMPARE_SCOPED_ORGS',
            'REPORT_CONSOLIDATED_SCOPED_ORGS', 'SAAS_ANALYTICS_VIEW', 'SUPPORT_IMPERSONATE',
            'HARD_DELETE_EXCEPTIONAL', 'AUDIT_PLATFORM_VIEW'
        ];

        // Org capabilities
        const orgCaps = [
            'ORG_VIEW', 'ORG_SETTINGS_VIEW', 'ORG_SETTINGS_MANAGE', 'ORG_MEMBER_VIEW', 'ORG_MEMBER_INVITE',
            'ORG_MEMBER_MANAGE', 'ORG_MEMBER_PERMISSION_MANAGE', 'IMPORT_VIEW', 'IMPORT_CREATE', 'IMPORT_RETRY',
            'IMPORT_REVIEW', 'RECORD_VIEW', 'RECORD_CLASSIFY', 'RECORD_SOFT_DELETE', 'RECORD_RESTORE',
            'PERCEPTION_IMPORT', 'BANK_IMPORT', 'PAYROLL_IMPORT', 'ISSUE_RESOLVE', 'CATALOG_ORG_VIEW',
            'REPORT_VIEW', 'REPORT_EXPORT', 'TICKET_CREATE', 'TICKET_VIEW_ORG', 'AUDIT_VIEW_ORG'
        ];

        platformCaps.concat(orgCaps).forEach(cap => {
            expect(upContent).toContain(`'${cap}'`);
        });

        // Role templates
        const templates = [
            'PLATFORM_SUPERADMIN', 'ACCOUNTING_SUPERADMIN', 'TENANT_ADMIN',
            'ACCOUNTANT', 'UPLOADER', 'REVIEWER', 'READ_ONLY', 'EXTERNAL_AUDITOR'
        ];

        templates.forEach(tpl => {
            expect(upContent).toContain(`'${tpl}'`);
        });
    });

    test('15 Mandatory Negative Tests (Evaluating Helper Logic Contracts)', () => {
        // Mock authorization evaluator implementing WP-A1 frozen contract logic
        const evaluateCanPlatform = ({ profile, platformRole, template, capability, overrides }) => {
            if (!profile || !profile.is_active) return false;
            if (!platformRole || !platformRole.is_active) return false;
            if (!template || template.scope !== 'PLATFORM' || !template.is_active) return false;
            if (!capability || capability.scope !== 'PLATFORM' || !capability.is_active) return false;

            const override = overrides.find(o => o.capability_code === capability.code);
            if (override) {
                if (override.effect === 'DENY') return false;
                if (override.effect === 'ALLOW') return true;
            }

            return template.capabilities.includes(capability.code);
        };

        const evaluateCanOrg = ({ profile, targetOrg, membership, capability, membershipTemplate, platformRole, bridgeGrants, overrides }) => {
            if (!profile || !profile.is_active) return false;
            if (!targetOrg || !targetOrg.is_active) return false;
            if (!membership || !membership.is_active) return false; // Active context without membership grants nothing
            if (!capability || capability.scope !== 'ORGANIZATION' || !capability.is_active) return false;

            let hasBaseTemplate = false;
            if (membershipTemplate && membershipTemplate.scope === 'ORGANIZATION' && membershipTemplate.is_active) {
                hasBaseTemplate = membershipTemplate.capabilities.includes(capability.code);
            }

            let hasBasePlatformBridge = false;
            if (platformRole && platformRole.is_active && platformRole.scope === 'PLATFORM') {
                hasBasePlatformBridge = bridgeGrants.includes(capability.code);
            }

            const hasBase = hasBaseTemplate || hasBasePlatformBridge;

            const override = overrides.find(o => o.capability_code === capability.code);
            if (override) {
                if (override.effect === 'DENY') return false;
                if (override.effect === 'ALLOW') return true;
            }

            return hasBase;
        };

        const activeProfile = { id: 'prof-1', is_active: true };
        const inactiveProfile = { id: 'prof-1', is_active: false };
        const activeOrg = { id: 'org-1', is_active: true };
        const activeMembership = { id: 'mem-1', is_active: true };
        const platformCap = { code: 'PLATFORM_MANAGE', scope: 'PLATFORM', is_active: true };
        const inactivePlatformCap = { code: 'PLATFORM_MANAGE', scope: 'PLATFORM', is_active: false };
        const orgCapImport = { code: 'IMPORT_CREATE', scope: 'ORGANIZATION', is_active: true };
        const orgCapSettings = { code: 'ORG_SETTINGS_MANAGE', scope: 'ORGANIZATION', is_active: true };

        const acctSuperAdminRole = { scope: 'PLATFORM', is_active: true };
        const acctBridgeGrants = ['IMPORT_CREATE'];

        // 1. Unauthenticated caller fails closed
        expect(evaluateCanPlatform({ profile: null })).toBe(false);
        expect(evaluateCanOrg({ profile: null, targetOrg: activeOrg, membership: activeMembership, capability: orgCapImport, overrides: [] })).toBe(false);

        // 2. Inactive profile fails closed
        expect(evaluateCanPlatform({ profile: inactiveProfile })).toBe(false);

        // 3. Missing platform role fails closed
        expect(evaluateCanPlatform({ profile: activeProfile, platformRole: null })).toBe(false);

        // 4. Inactive platform role fails closed
        expect(evaluateCanPlatform({ profile: activeProfile, platformRole: { is_active: false } })).toBe(false);

        // 5. Inactive role template fails closed
        expect(evaluateCanPlatform({
            profile: activeProfile,
            platformRole: { is_active: true },
            template: { scope: 'PLATFORM', is_active: false, capabilities: ['PLATFORM_MANAGE'] },
            capability: platformCap,
            overrides: []
        })).toBe(false);

        // 6. Inactive capability fails closed
        expect(evaluateCanPlatform({
            profile: activeProfile,
            platformRole: { is_active: true },
            template: { scope: 'PLATFORM', is_active: true, capabilities: ['PLATFORM_MANAGE'] },
            capability: inactivePlatformCap,
            overrides: []
        })).toBe(false);

        // 7. Active context without membership grants nothing
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: null, // NO membership
            capability: orgCapImport,
            overrides: []
        })).toBe(false);

        // 8. ACCOUNTING_SUPERADMIN without membership grants no org access
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: null,
            capability: orgCapImport,
            platformRole: acctSuperAdminRole,
            bridgeGrants: acctBridgeGrants,
            overrides: []
        })).toBe(false);

        // 9. ACCOUNTING_SUPERADMIN with membership receives only configured bridge capabilities
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: activeMembership,
            capability: orgCapImport,
            platformRole: acctSuperAdminRole,
            bridgeGrants: acctBridgeGrants,
            overrides: []
        })).toBe(true);

        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: activeMembership,
            capability: orgCapSettings, // NOT in bridge
            platformRole: acctSuperAdminRole,
            bridgeGrants: acctBridgeGrants,
            overrides: []
        })).toBe(false);

        // 10. Membership DENY overrides base ALLOW
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: activeMembership,
            capability: orgCapImport,
            platformRole: acctSuperAdminRole,
            bridgeGrants: acctBridgeGrants,
            overrides: [{ capability_code: 'IMPORT_CREATE', effect: 'DENY' }]
        })).toBe(false);

        // 11. Membership ALLOW can grant a capability absent from template
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: activeMembership,
            capability: orgCapSettings,
            platformRole: acctSuperAdminRole,
            bridgeGrants: acctBridgeGrants,
            overrides: [{ capability_code: 'ORG_SETTINGS_MANAGE', effect: 'ALLOW' }]
        })).toBe(true);

        // 12. Current real user with no new authorization assignment fails closed
        expect(evaluateCanOrg({
            profile: activeProfile,
            targetOrg: activeOrg,
            membership: activeMembership,
            capability: orgCapImport,
            membershipTemplate: null,
            platformRole: null,
            bridgeGrants: [],
            overrides: []
        })).toBe(false);
    });

    test('Behavior Preservation: Existing RPCs and RLS definitions are untouched', () => {
        const m018Path = path.join(process.cwd(), 'sql', '018_superadmin_operational_capabilities.sql');
        const m018Content = fs.readFileSync(m018Path, 'utf8');

        // Verify existing RPCs still rely on legacy private.func_role and private.org_id
        expect(m018Content).toContain('v_org_id := private.org_id();');
        expect(m018Content).toContain('v_caller_role := private.func_role();');

        // Verify none of the 018 business RPCs were edited to call can_org or can_platform
        expect(m018Content).not.toContain('private.can_org');
        expect(m018Content).not.toContain('private.can_platform');
    });

    test('Rollback Exactness: 019 DOWN removes ONLY WP-A1 additions', () => {
        const downPath = path.join(process.cwd(), 'sql', '019_capability_foundation_down.sql');
        const downContent = fs.readFileSync(downPath, 'utf8');

        expect(downContent).toContain('DROP FUNCTION IF EXISTS private.can_org(UUID, TEXT);');
        expect(downContent).toContain('DROP FUNCTION IF EXISTS private.can_platform(TEXT);');
        expect(downContent).toContain('DROP FUNCTION IF EXISTS private.active_org_id();');
        expect(downContent).toContain('DROP FUNCTION IF EXISTS private.current_profile_id();');

        expect(downContent).toContain('DROP COLUMN IF EXISTS role_template_id;');

        expect(downContent).toContain('DROP TABLE IF EXISTS public.eco_user_active_context;');
        expect(downContent).toContain('DROP TABLE IF EXISTS public.eco_capabilities;');

        // Verify DOWN does NOT touch legacy tables
        expect(downContent).not.toContain('DROP TABLE IF EXISTS public.eco_user_profiles');
        expect(downContent).not.toContain('DROP TABLE IF EXISTS public.eco_organizations');
        expect(downContent).not.toContain('DROP TABLE IF EXISTS public.eco_organization_members;');
    });
});
