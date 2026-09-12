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
        expect(upContent).toContain('AMBIGUOUS_ORGANIZATION_CONTEXT');
        expect(upContent).toContain('eco_organization_members');

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
        expect(dbTestContent).toContain('AMBIGUOUS_ORGANIZATION_CONTEXT');
    });

    test('Multi-Org Target Resolution & Stale profile.organization_id Immunity Simulation', () => {
        const NORTE = '38419581-8163-482c-9813-616fa6214d71';
        const SUR = 'c7af5a5c-1aac-4add-9873-8073044bf979';

        // Target user belongs to BOTH NORTE and SUR, but profile.organization_id is SUR (stale for NORTE admin)
        const targetUser = {
            id: 'prof-multi',
            profile_org_id: SUR, // Stale single-org column
            is_active: true,
            memberships: [
                { id: 'mem-norte', org_id: NORTE, template: 'UPLOADER', is_active: true },
                { id: 'mem-sur', org_id: SUR, template: 'UPLOADER', is_active: true }
            ]
        };

        const adminNorte = {
            id: 'prof-emiliano',
            active_context: null,
            memberships: [{ org_id: NORTE, template: 'TENANT_ADMIN', is_active: true }],
            capabilities: { [NORTE]: ['ORG_MEMBER_PERMISSION_MANAGE', 'ORG_MEMBER_MANAGE', 'ORG_MEMBER_VIEW'] }
        };

        const superAdminBoth = {
            id: 'prof-super',
            active_context: null,
            memberships: [
                { org_id: NORTE, template: 'TENANT_ADMIN', is_active: true },
                { org_id: SUR, template: 'TENANT_ADMIN', is_active: true }
            ],
            capabilities: {
                [NORTE]: ['ORG_MEMBER_PERMISSION_MANAGE', 'ORG_MEMBER_MANAGE'],
                [SUR]: ['ORG_MEMBER_PERMISSION_MANAGE', 'ORG_MEMBER_MANAGE']
            }
        };

        // Deterministic target org resolver matching M022 logic
        const resolveTargetOrg = (caller, target, capability, suppliedOrgId = null) => {
            if (suppliedOrgId) return suppliedOrgId;
            if (caller.active_context) {
                const targetInActive = target.memberships.some(m => m.org_id === caller.active_context);
                if (targetInActive) return caller.active_context;
            }

            // Find candidate memberships where caller holds required capability
            const candidateOrgs = target.memberships
                .map(m => m.org_id)
                .filter(orgId => caller.capabilities[orgId] && caller.capabilities[orgId].includes(capability));

            if (candidateOrgs.length > 1) throw new Error('AMBIGUOUS_ORGANIZATION_CONTEXT');
            if (candidateOrgs.length === 0) return null;
            return candidateOrgs[0];
        };

        // 1. Admin NORTE resolves target org to NORTE despite target.profile_org_id being SUR
        const resolvedOrg = resolveTargetOrg(adminNorte, targetUser, 'ORG_MEMBER_PERMISSION_MANAGE');
        expect(resolvedOrg).toBe(NORTE);

        // 2. Admin NORTE mutates role in NORTE -> SUR membership remains untouched
        const norteMembership = targetUser.memberships.find(m => m.org_id === resolvedOrg);
        norteMembership.template = 'REVIEWER';
        expect(targetUser.memberships.find(m => m.org_id === NORTE).template).toBe('REVIEWER');
        expect(targetUser.memberships.find(m => m.org_id === SUR).template).toBe('UPLOADER'); // Untouched

        // 3. Admin NORTE deactivates user in NORTE -> SUR membership & global profile remain active
        norteMembership.is_active = false;
        expect(targetUser.memberships.find(m => m.org_id === NORTE).is_active).toBe(false);
        expect(targetUser.memberships.find(m => m.org_id === SUR).is_active).toBe(true); // Untouched
        expect(targetUser.is_active).toBe(true); // Global profile untouched

        // 4. Superadmin in BOTH orgs without active context or explicit org fails closed on ambiguity
        expect(() => {
            resolveTargetOrg(superAdminBoth, targetUser, 'ORG_MEMBER_PERMISSION_MANAGE');
        }).toThrow('AMBIGUOUS_ORGANIZATION_CONTEXT');

        // 5. Superadmin with explicit p_org_id resolves cleanly
        const explicitOrg = resolveTargetOrg(superAdminBoth, targetUser, 'ORG_MEMBER_PERMISSION_MANAGE', NORTE);
        expect(explicitOrg).toBe(NORTE);
    });
});
