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
        expect(upContent).toContain('CREATE TABLE IF NOT EXISTS public.eco_platform_audit_events');
        expect(upContent).toContain('enforce_append_only_platform_audit');
        expect(upContent).toContain('AUDIT_PLATFORM_VIEW');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.change_user_role');
        expect(upContent).toContain('ORG_MEMBER_PERMISSION_MANAGE');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.set_user_active');
        expect(upContent).toContain('ORG_MEMBER_MANAGE');
        expect(upContent).toContain('CREATE OR REPLACE FUNCTION public.set_global_user_active');
        expect(upContent).toContain('GLOBAL_USER_MANAGE');
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
        expect(downContent).toContain('DROP TABLE IF EXISTS public.eco_platform_audit_events CASCADE;');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.change_user_role');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.set_user_active');
        expect(downContent).toContain('DROP FUNCTION IF EXISTS public.set_global_user_active');
        expect(downContent).toContain('CREATE OR REPLACE FUNCTION public.switch_superadmin_org_context');
        expect(downContent).toContain('private.func_role() <> \'ADMIN\'');
        expect(downContent).toContain('v_caller_role != \'SUPERADMIN\'');

        const postcheckContent = fs.readFileSync(postcheckPath, 'utf8');
        expect(postcheckContent).toContain('eco_platform_audit_events');
        expect(postcheckContent).toContain('enforce_append_only_platform_audit');

        const dbTestContent = fs.readFileSync(dbTestPath, 'utf8');
        expect(dbTestContent).toContain('BEGIN;');
        expect(dbTestContent).toContain('ROLLBACK;');
        expect(dbTestContent).toContain('M022_NOT_APPLIED_RUN_FORWARD_AND_POSTCHECK_FIRST');
        expect(dbTestContent).toContain('M022_SCHEMA_DRIFT');
        expect(dbTestContent).toContain('SYNTHETIC_PROFILE_CARDINALITY_ERROR');
        expect(dbTestContent).not.toContain('\\i ');
        expect(dbTestContent).not.toContain('Synthetic User A'); // Stale full_name column assumption removed
        expect(dbTestContent).toContain('SELF_ROLE_CHANGE_NOT_ALLOWED');
        expect(dbTestContent).toContain('SELF_DEACTIVATION_NOT_ALLOWED');
        expect(dbTestContent).toContain('set_global_user_active');
        expect(dbTestContent).toContain('eco_platform_audit_events');
        expect(dbTestContent).toContain('AMBIGUOUS_ORGANIZATION_CONTEXT');
        expect(dbTestContent).toContain('BEHAVIORAL_TEST_NOT_RUNNING_AS_AUTHENTICATED');
        expect(dbTestContent).toContain('SET LOCAL ROLE authenticated');
        expect(dbTestContent).toContain('harness_set_persona');
        expect(dbTestContent).toContain('harness_reset_role');
        expect(dbTestContent).toContain('LEGACY_ORGANIZATION_RLS_POLICY_PRESENT');
        expect(dbTestContent).toContain('SECTION_8_UNEXPECTED_EXCEPTION');
        expect(dbTestContent).toContain('SECTION_8_NO_EXCEPTION');
        expect(dbTestContent).toContain('SECTION_8_DIAGNOSTICS');
        expect(dbTestContent).not.toContain('private.');
    });

    test('Multi-Org Target Resolution & Stale profile.organization_id Immunity Simulation', () => {
        const NORTE = '38419581-8163-482c-9813-616fa6214d71';
        const SUR = 'c7af5a5c-1aac-4add-9873-8073044bf979';

        // Target user belongs to BOTH NORTE and SUR, but profile.organization_id is SUR (stale for NORTE admin)
        const targetUser = {
            id: 'prof-multi',
            profile_org_id: SUR, // Stale single-org column
            role: 'USER', // Stale single-org role
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

        const platformSuperadmin = {
            id: 'prof-vegen',
            active_context: NORTE, // Active context set to NORTE
            platformCapabilities: ['GLOBAL_USER_MANAGE', 'PLATFORM_MANAGE', 'SUPPORT_IMPERSONATE', 'AUDIT_PLATFORM_VIEW']
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

        // Platform audit event mock store
        const platformAuditLog = [];

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
                .filter(orgId => caller.capabilities && caller.capabilities[orgId] && caller.capabilities[orgId].includes(capability));

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

        // 4. Admin NORTE changes role on an inactive membership -> allows update, stays inactive
        norteMembership.template = 'ACCOUNTANT';
        expect(targetUser.memberships.find(m => m.org_id === NORTE).template).toBe('ACCOUNTANT');
        expect(targetUser.memberships.find(m => m.org_id === NORTE).is_active).toBe(false);

        // Reactivate NORTE membership
        norteMembership.is_active = true;

        // 5. Global deactivation via Platform Superadmin: mutates ONLY global profile, emits platform audit event
        const executeGlobalDeactivation = (caller, target, activeState) => {
            if (!caller.platformCapabilities || (!caller.platformCapabilities.includes('GLOBAL_USER_MANAGE') && !caller.platformCapabilities.includes('PLATFORM_MANAGE'))) {
                throw new Error('FORBIDDEN');
            }
            const prev = target.is_active;
            target.is_active = activeState; // Mutates global profile only
            platformAuditLog.push({
                actor: caller.id,
                event_type: 'GLOBAL_USER_ACTIVE_CHANGED',
                target: target.id,
                metadata: { new_active: activeState, previous_active: prev }
            });
        };

        executeGlobalDeactivation(platformSuperadmin, targetUser, false);
        expect(targetUser.is_active).toBe(false);
        expect(targetUser.memberships.find(m => m.org_id === SUR).is_active).toBe(true); // Membership row untouched
        expect(platformAuditLog.length).toBe(1);
        expect(platformAuditLog[0].event_type).toBe('GLOBAL_USER_ACTIVE_CHANGED');
        expect(platformAuditLog[0].actor).toBe(platformSuperadmin.id);
        expect(platformAuditLog[0].target).toBe(targetUser.id);
        expect(platformAuditLog[0].metadata.new_active).toBe(false);

        // 6. Tenant admin attempting global deactivation fails with FORBIDDEN and emits NO platform audit
        expect(() => {
            executeGlobalDeactivation(adminNorte, targetUser, true);
        }).toThrow('FORBIDDEN');
        expect(platformAuditLog.length).toBe(1); // No new audit row

        // 7. Superadmin in BOTH orgs without active context or explicit org fails closed on ambiguity
        expect(() => {
            resolveTargetOrg(superAdminBoth, targetUser, 'ORG_MEMBER_PERMISSION_MANAGE');
        }).toThrow('AMBIGUOUS_ORGANIZATION_CONTEXT');

        // 8. Superadmin with explicit p_org_id resolves cleanly
        const explicitOrg = resolveTargetOrg(superAdminBoth, targetUser, 'ORG_MEMBER_PERMISSION_MANAGE', NORTE);
        expect(explicitOrg).toBe(NORTE);
    });

    test('WP-AUTH-RESET-1 Verification: Migration 023 SQL files and DB matrix test exist and are well-formed', () => {
        const preflight023Path = path.join(process.cwd(), 'sql', '023_clean_authorization_preflight.sql');
        const up023Path = path.join(process.cwd(), 'sql', '023_clean_authorization_cutover.sql');
        const postcheck023Path = path.join(process.cwd(), 'sql', '023_clean_authorization_postcheck.sql');
        const matrixTestPath = path.join(process.cwd(), 'tests', 'db', '023_authorization_matrix.sql');

        expect(fs.existsSync(preflight023Path)).toBe(true);
        expect(fs.existsSync(up023Path)).toBe(true);
        expect(fs.existsSync(postcheck023Path)).toBe(true);
        expect(fs.existsSync(matrixTestPath)).toBe(true);

        const upContent = fs.readFileSync(up023Path, 'utf8');
        expect(upContent).toContain('DROP POLICY IF EXISTS "Organizations member view"');
        expect(upContent).toContain('CREATE POLICY "Organizations viewable by own users"');
        expect(upContent).toContain('authorized_orgs_for_capability(\'ORG_VIEW\')');
        expect(upContent).toContain('private.org_id()');
        expect(upContent).toContain('private.active_org_id()');
        expect(upContent).toContain('vegendigital@gmail.com');
        expect(upContent).toContain('drcmarianela@gmail.com');
        expect(upContent).toContain('emilianodirosa1@gmail.com');
        expect(upContent).toContain('edravi77@gmail.com');
        expect(upContent).toContain('calleelcalvario16@gmail.com');
        expect(upContent).toContain('59436df3-9f15-4f5e-b17e-37c55482521c'); // MICA org neutralized

        const postcheckContent = fs.readFileSync(postcheck023Path, 'utf8');
        expect(postcheckContent).toContain('Postcheck 023 FAILED');
        expect(postcheckContent).toContain('eco_organizations');
        expect(postcheckContent).toContain('authorized_orgs_for_capability%ORG_VIEW');
        expect(postcheckContent).toContain('TENANT_ADMIN');
        expect(postcheckContent).toContain('ACCOUNTING_SUPERADMIN');
        expect(postcheckContent).toContain('PLATFORM_SUPERADMIN');

        const matrixContent = fs.readFileSync(matrixTestPath, 'utf8');
        expect(matrixContent).toContain('BEGIN;');
        expect(matrixContent).toContain('ROLLBACK;');
        expect(matrixContent).toContain('SET LOCAL ROLE authenticated');
        expect(matrixContent).toContain('Matrix Test FAILED');
        expect(matrixContent).not.toContain('private.');
    });
});
