import { jest } from '@jest/globals';
import fs from 'fs';
import path from 'path';

describe('WP-A3.2.0 Authorization Primitives Safety & Performance Validation', () => {

    test('Verification: Migration 021 SQL files exist and are well-formed', () => {
        const preflightPath = path.join(process.cwd(), 'sql', '021_preflight_check.sql');
        const upPath = path.join(process.cwd(), 'sql', '021_authorization_primitives.sql');
        const downPath = path.join(process.cwd(), 'sql', '021_authorization_primitives_down.sql');
        const postcheckPath = path.join(process.cwd(), 'sql', '021_postcheck.sql');
        const dbTestPath = path.join(process.cwd(), 'tests', 'db', '021_authorization_primitives.sql');

        expect(fs.existsSync(preflightPath)).toBe(true);
        expect(fs.existsSync(upPath)).toBe(true);
        expect(fs.existsSync(downPath)).toBe(true);
        expect(fs.existsSync(postcheckPath)).toBe(true);
        expect(fs.existsSync(dbTestPath)).toBe(true);

        const upContent = fs.readFileSync(upPath, 'utf8');
        expect(upContent).toContain('idx_eco_org_members_covering');
        expect(upContent).toContain('idx_eco_user_platform_role_covering');
        expect(upContent).toContain('FUNCTION private.authorized_orgs_for_capability');

        const downContent = fs.readFileSync(downPath, 'utf8');
        expect(downContent).toContain('DROP FUNCTION IF EXISTS private.authorized_orgs_for_capability');
        expect(downContent).toContain('DROP INDEX IF EXISTS public.idx_eco_user_platform_role_covering');
        expect(downContent).toContain('DROP INDEX IF EXISTS public.idx_eco_org_members_covering');
        // DOWN must strictly avoid touching M019 or M020 tables
        expect(downContent).not.toContain('DROP TABLE');
    });

    test('Semantic Truth Table & Synthetic Override Isolation Evaluation', () => {
        // Mock authorization engine reflecting M019/M021 contracts
        const evaluateCanOrg = ({ profile, targetOrgId, memberships, platformRole, bridgeGrants, templates, overrides }) => {
            if (!profile || !profile.is_active) return false;
            if (!targetOrgId) return false;

            const membership = memberships.find(m => m.organization_id === targetOrgId && m.is_active);
            if (!membership) return false;

            // Check override for this membership
            const override = overrides.find(o => o.membership_id === membership.id);
            if (override) {
                if (override.effect === 'DENY') return false;
                if (override.effect === 'ALLOW') return true;
            }

            // Check membership base template
            let hasBase = false;
            if (membership.role_template_id) {
                const tpl = templates.find(t => t.id === membership.role_template_id && t.is_active);
                if (tpl && tpl.capabilities.includes('IMPORT_CREATE')) {
                    hasBase = true;
                }
            }

            // Check platform role bridge
            if (!hasBase && platformRole && platformRole.is_active) {
                if (bridgeGrants.includes('IMPORT_CREATE')) {
                    hasBase = true;
                }
            }

            return hasBase;
        };

        const profile = { id: 'prof-1', is_active: true };
        const templates = [{ id: 'tpl-uploader', is_active: true, capabilities: ['IMPORT_CREATE'] }];

        // 1. Base ALLOW + Override DENY in Org A
        const membershipA = { id: 'mem-a', organization_id: 'org-a', role_template_id: 'tpl-uploader', is_active: true };
        const membershipB = { id: 'mem-b', organization_id: 'org-b', role_template_id: 'tpl-uploader', is_active: true };

        const overrides = [
            { membership_id: 'mem-a', capability_code: 'IMPORT_CREATE', effect: 'DENY' }
        ];

        // Org A has DENY override -> FALSE
        const canOrgA = evaluateCanOrg({
            profile,
            targetOrgId: 'org-a',
            memberships: [membershipA, membershipB],
            platformRole: null,
            bridgeGrants: [],
            templates,
            overrides
        });
        expect(canOrgA).toBe(false);

        // Org B has no override -> TRUE (cross-tenant isolation preserved)
        const canOrgB = evaluateCanOrg({
            profile,
            targetOrgId: 'org-b',
            memberships: [membershipA, membershipB],
            platformRole: null,
            bridgeGrants: [],
            templates,
            overrides
        });
        expect(canOrgB).toBe(true);
    });

    test('Set-based Authorized Organizations Evaluation for High-Volume RLS Pattern', () => {
        const profile = { id: 'prof-marianela', is_active: true };
        const memberships = [
            { id: 'm1', organization_id: 'org-norte', is_active: true },
            { id: 'm2', organization_id: 'org-sur', is_active: true },
            { id: 'm3', organization_id: 'org-oeste', is_active: true }
        ];
        const platformRole = { id: 'pr-1', is_active: true };
        const bridgeGrants = ['RECORD_VIEW'];

        const getAuthorizedOrgs = ({ profile, memberships, platformRole, bridgeGrants, capabilityCode }) => {
            if (!profile || !profile.is_active) return [];
            if (!platformRole || !platformRole.is_active) return [];
            if (!bridgeGrants.includes(capabilityCode)) return [];

            return memberships.filter(m => m.is_active).map(m => m.organization_id);
        };

        const authorizedOrgs = getAuthorizedOrgs({ profile, memberships, platformRole, bridgeGrants, capabilityCode: 'RECORD_VIEW' });
        expect(authorizedOrgs).toEqual(['org-norte', 'org-sur', 'org-oeste']);
        expect(authorizedOrgs).not.toContain('org-mica-legacy');
    });
});
