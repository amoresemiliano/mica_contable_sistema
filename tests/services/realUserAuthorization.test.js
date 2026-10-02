import { jest } from '@jest/globals';
import fs from 'fs';
import path from 'path';

describe('WP-A2 Real User Authorization Assignments Contract & Isolation Tests', () => {

    test('Verification: Migration 020 SQL files exist and are well-formed', () => {
        const preflightPath = path.join(process.cwd(), 'sql', '020_preflight_check.sql');
        const upPath = path.join(process.cwd(), 'sql', '020_real_user_authorization.sql');
        const downPath = path.join(process.cwd(), 'sql', '020_real_user_authorization_down.sql');
        const postcheckPath = path.join(process.cwd(), 'sql', '020_postcheck.sql');
        const dbTestPath = path.join(process.cwd(), 'tests', 'db', '020_real_user_authorization.sql');

        expect(fs.existsSync(preflightPath)).toBe(true);
        expect(fs.existsSync(upPath)).toBe(true);
        expect(fs.existsSync(downPath)).toBe(true);
        expect(fs.existsSync(postcheckPath)).toBe(true);
        expect(fs.existsSync(dbTestPath)).toBe(true);
    });

    test('Freeze UUID Compliance: 020 SQL scripts use full frozen org UUIDs and exclude legacy MICA as target', () => {
        const upPath = path.join(process.cwd(), 'sql', '020_real_user_authorization.sql');
        const upContent = fs.readFileSync(upPath, 'utf8');

        const norteUuid  = '38419581-8163-482c-9813-616fa6214d71';
        const surUuid    = 'c7af5a5c-1aac-4add-9873-8073044bf979';
        const oesteUuid  = '1f5d071f-a09e-4825-9f12-88533383599e';
        const legacyMica = '59436df3-9f15-4f5e-b17e-37c55482521c';

        expect(upContent).toContain(norteUuid);
        expect(upContent).toContain(surUuid);
        expect(upContent).toContain(oesteUuid);

        // Legacy MICA org must NEVER be used as target tenant for WP-A2 assignments
        expect(upContent).not.toContain(legacyMica);
    });

    test('Idempotency & Contract Preservation: 020 Forward migration uses real schema ON CONFLICT targets and preserves legacy profile fields', () => {
        const upPath = path.join(process.cwd(), 'sql', '020_real_user_authorization.sql');
        const upContent = fs.readFileSync(upPath, 'utf8');

        // M020 must NOT use invalid ON CONFLICT (user_profile_id, role_template_id) because eco_user_platform_role PK is user_profile_id
        expect(upContent).not.toContain('ON CONFLICT (user_profile_id, role_template_id)');

        // Verified ON CONFLICT targets for eco_organization_members and eco_user_active_context
        expect(upContent).toContain('ON CONFLICT (organization_id, user_profile_id)');
        expect(upContent).toContain('ON CONFLICT (user_profile_id)');

        // Must not alter legacy profile role or organization_id
        expect(upContent).not.toContain('UPDATE public.eco_user_profiles SET role');
        expect(upContent).not.toContain('UPDATE public.eco_user_profiles SET organization_id');
        expect(upContent).not.toContain('ALTER TABLE public.eco_user_profiles');
    });

    test('M019 Schema & Preflight Compliance: 020 checks eco_user_platform_role PRIMARY KEY contract and fail-closed handling', () => {
        const m019Path = path.join(process.cwd(), 'sql', '019_capability_foundation.sql');
        const m019Content = fs.readFileSync(m019Path, 'utf8');
        const preflightPath = path.join(process.cwd(), 'sql', '020_preflight_check.sql');
        const preflightContent = fs.readFileSync(preflightPath, 'utf8');

        // 1. Prove M019 models eco_user_platform_role uniqueness as PRIMARY KEY(user_profile_id)
        expect(m019Content).toContain('user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id)');

        // 2 & 3. Preflight rejects ANY existing platform role row for vegendigital and Marianela
        expect(preflightContent).toContain('vegendigital already has a pre-existing platform role row in eco_user_platform_role.');
        expect(preflightContent).toContain('drcmarianela already has a pre-existing platform role row in eco_user_platform_role.');

        // Explicit read check on auth.users
        expect(preflightContent).toContain('SELECT COUNT(*) INTO v_auth_count FROM auth.users;');
        expect(preflightContent).toContain('auth.users table is inaccessible or caller lacks SELECT privilege');

        // Target user checks
        expect(preflightContent).toContain('vegendigital@gmail.com');
        expect(preflightContent).toContain('drcmarianela@gmail.com');
        expect(preflightContent).toContain('emilianodirosa1@gmail.com');
        expect(preflightContent).toContain('edravi77@gmail.com');
        expect(preflightContent).toContain('calleelcalvario16@gmail.com');
    });

    test('Reversibility Safety Preflight: 020 Preflight rejects pre-existing target platform roles, memberships, or active contexts', () => {
        const preflightPath = path.join(process.cwd(), 'sql', '020_preflight_check.sql');
        const preflightContent = fs.readFileSync(preflightPath, 'utf8');

        // Platform roles absence checks
        expect(preflightContent).toContain('vegendigital already has a pre-existing platform role row in eco_user_platform_role.');
        expect(preflightContent).toContain('drcmarianela already has a pre-existing platform role row in eco_user_platform_role.');

        // Target memberships absence checks
        expect(preflightContent).toContain('drcmarianela already has pre-existing membership in DEMO NORTE, SUR, or OESTE');
        expect(preflightContent).toContain('emilianodirosa1 already has pre-existing membership in DEMO NORTE');
        expect(preflightContent).toContain('edravi77 already has pre-existing membership in DEMO SUR');
        expect(preflightContent).toContain('calleelcalvario16 already has pre-existing membership in DEMO OESTE');

        // Active context absence check
        expect(preflightContent).toContain('One or more target accounts already have a pre-existing active context row');
    });

    test('Targeted Rollback Safety: 020 DOWN removes only M020 assignments, retains Calle profile identity, and contains no broad deletes/truncates', () => {
        const downPath = path.join(process.cwd(), 'sql', '020_real_user_authorization_down.sql');
        const downContent = fs.readFileSync(downPath, 'utf8');

        // Targeted DELETEs
        expect(downContent).toContain('DELETE FROM public.eco_user_active_context');
        expect(downContent).toContain('DELETE FROM public.eco_organization_members');
        expect(downContent).toContain('DELETE FROM public.eco_user_platform_role');

        // Must not blindly delete Calle's profile identity
        expect(downContent).not.toContain('DELETE FROM public.eco_user_profiles WHERE auth_user_id = v_calle_auth_id');
        expect(downContent).not.toContain('DELETE FROM public.eco_user_profiles;');

        // No broad un-scoped DELETEs or TRUNCATEs
        expect(downContent).not.toContain('TRUNCATE');
        expect(downContent).not.toMatch(/DELETE\s+FROM\s+public\.eco_user_active_context\s*;/i);
        expect(downContent).not.toMatch(/DELETE\s+FROM\s+public\.eco_organization_members\s*;/i);
        expect(downContent).not.toMatch(/DELETE\s+FROM\s+public\.eco_user_platform_role\s*;/i);
    });

    test('M020 WP-A2 Target User Authorization Model Simulation', () => {
        const caps = {
            PLATFORM_MANAGE: { scope: 'PLATFORM' },
            REPORT_COMPARE_SCOPED_ORGS: { scope: 'PLATFORM' },
            IMPORT_CREATE: { scope: 'ORGANIZATION' },
            ORG_MEMBER_INVITE: { scope: 'ORGANIZATION' }
        };

        const roles = {
            PLATFORM_SUPERADMIN: ['PLATFORM_MANAGE'],
            ACCOUNTING_SUPERADMIN: ['REPORT_COMPARE_SCOPED_ORGS'],
            TENANT_ADMIN: ['IMPORT_CREATE', 'ORG_MEMBER_INVITE']
        };

        const platformOrgBridges = {
            ACCOUNTING_SUPERADMIN: ['IMPORT_CREATE']
        };

        const NORTE = '38419581-8163-482c-9813-616fa6214d71';
        const SUR   = 'c7af5a5c-1aac-4add-9873-8073044bf979';
        const OESTE = '1f5d071f-a09e-4825-9f12-88533383599e';
        const MICA  = '59436df3-9f15-4f5e-b17e-37c55482521c';

        // Target users setup
        const users = {
            vegendigital: {
                platformRole: 'PLATFORM_SUPERADMIN',
                memberships: {},
                activeContext: null
            },
            Marianela: {
                platformRole: 'ACCOUNTING_SUPERADMIN',
                memberships: { [NORTE]: null, [SUR]: null, [OESTE]: null },
                activeContext: NORTE
            },
            Emiliano: {
                platformRole: null,
                memberships: { [NORTE]: 'TENANT_ADMIN' },
                activeContext: NORTE
            },
            Edravi: {
                platformRole: null,
                memberships: { [SUR]: 'TENANT_ADMIN' },
                activeContext: SUR
            },
            Calle: {
                platformRole: null,
                memberships: { [OESTE]: 'TENANT_ADMIN' },
                activeContext: OESTE
            }
        };

        const evaluateCanPlatform = (userKey, capCode) => {
            const user = users[userKey];
            if (!user || !user.platformRole) return false;
            const tplCaps = roles[user.platformRole] || [];
            return tplCaps.includes(capCode);
        };

        const evaluateCanOrg = (userKey, orgId, capCode) => {
            const user = users[userKey];
            if (!user) return false;
            const membershipTpl = user.memberships[orgId];
            const hasMembership = membershipTpl !== undefined;
            if (!hasMembership) return false; // MANDATORY: membership required for can_org

            let hasBaseTemplate = false;
            if (membershipTpl && roles[membershipTpl]) {
                hasBaseTemplate = roles[membershipTpl].includes(capCode);
            }

            let hasPlatformBridge = false;
            if (user.platformRole && platformOrgBridges[user.platformRole]) {
                hasPlatformBridge = platformOrgBridges[user.platformRole].includes(capCode);
            }

            return hasBaseTemplate || hasPlatformBridge;
        };

        // Assertions
        // 1. vegendigital platform superadmin
        expect(evaluateCanPlatform('vegendigital', 'PLATFORM_MANAGE')).toBe(true);
        expect(evaluateCanOrg('vegendigital', NORTE, 'IMPORT_CREATE')).toBe(false); // NO tenant bypass without membership

        // 2. Marianela accounting superadmin
        expect(evaluateCanPlatform('Marianela', 'REPORT_COMPARE_SCOPED_ORGS')).toBe(true);
        expect(evaluateCanOrg('Marianela', NORTE, 'IMPORT_CREATE')).toBe(true);
        expect(evaluateCanOrg('Marianela', SUR, 'IMPORT_CREATE')).toBe(true);
        expect(evaluateCanOrg('Marianela', OESTE, 'IMPORT_CREATE')).toBe(true);
        expect(evaluateCanOrg('Marianela', MICA, 'IMPORT_CREATE')).toBe(false); // NO membership in MICA

        // 3. Emiliano tenant admin NORTE
        expect(evaluateCanOrg('Emiliano', NORTE, 'ORG_MEMBER_INVITE')).toBe(true);
        expect(evaluateCanOrg('Emiliano', SUR, 'ORG_MEMBER_INVITE')).toBe(false);
        expect(evaluateCanOrg('Emiliano', OESTE, 'ORG_MEMBER_INVITE')).toBe(false);
        expect(evaluateCanPlatform('Emiliano', 'REPORT_COMPARE_SCOPED_ORGS')).toBe(false); // NO platform escalation

        // 4. Edravi tenant admin SUR
        expect(evaluateCanOrg('Edravi', NORTE, 'ORG_MEMBER_INVITE')).toBe(false);
        expect(evaluateCanOrg('Edravi', SUR, 'ORG_MEMBER_INVITE')).toBe(true);
        expect(evaluateCanOrg('Edravi', OESTE, 'ORG_MEMBER_INVITE')).toBe(false);

        // 5. Calle tenant admin OESTE
        expect(evaluateCanOrg('Calle', NORTE, 'ORG_MEMBER_INVITE')).toBe(false);
        expect(evaluateCanOrg('Calle', SUR, 'ORG_MEMBER_INVITE')).toBe(false);
        expect(evaluateCanOrg('Calle', OESTE, 'ORG_MEMBER_INVITE')).toBe(true);
    });
});
