# Current Work Package: WP-A3.2.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1 — IDENTITY, PROFILES & ORGANIZATION ADMINISTRATION  
**MODE**: IMPLEMENTATION COMPLETE & PRE-DEV BLOCKER RESOLVED  
**STATUS**: `WP_A3_2_1_IMPLEMENTED`  
**BASELINE SHA**: `fc68469d294155c7827b45627f0b2facedff76b9`  
**READY_FOR**: `READY_FOR_MANUAL_DEV_DB_VALIDATION`  

---

## 1. Deliverables & Multi-Org Target Resolution Summary

1. `sql/022_identity_and_org_admin.sql` — Forward migration:
   - `change_user_role`: Mutates canonical `eco_organization_members.role_template_id` based on deterministic target org resolution (explicit `p_org_id`, active context, or unique authorized membership; fails closed with `AMBIGUOUS_ORGANIZATION_CONTEXT` on ambiguity).
   - `set_user_active`: Operates on `eco_organization_members.is_active` for tenant administration (`ORG_MEMBER_MANAGE`), guaranteeing tenant membership isolation without deactivating global profiles or cross-tenant memberships.
   - `switch_superadmin_org_context`: Platform capability-governed (`SUPPORT_IMPERSONATE` / `ACCESS_ANY_ORG`) context switching.
   - Set-based RLS on `eco_organizations`, `eco_user_profiles`, and `eco_audit_events`.
2. `sql/022_identity_and_org_admin_preflight.sql` — Pre-migration baseline verification.
3. `sql/022_identity_and_org_admin_postcheck.sql` — Post-migration verification script.
4. `sql/022_identity_and_org_admin_down.sql` — Rollback script cleanly restoring pre-M022 definitions.
5. `tests/db/022_identity_and_org_admin.sql` — Comprehensive DB behavioral test suite with multi-org target resolution, stale `profile.organization_id` immunity, and ambiguity fail-closed tests.
6. `docs/MICA_A3_2_1_DESIGN.md` — Detailed technical design specification.
7. `docs/MICA_A3_2_1_COMPATIBILITY_CONTRACT.md` — Backward & bidirectional compatibility contract.
8. `docs/MICA_A3_2_1_SECURITY_ACCEPTANCE_MATRIX.md` — Comprehensive security truth table and test matrix.
9. `docs/MICA_A3_2_1_MANUAL_DEV_VALIDATION.md` — Manual DEV browser/persona validation runbook.
10. `tests/services/identityAndOrgAdminCutover.test.js` — Automated Jest test suite passing 100%.

---

## 2. Fundamental Architectural Rule Reaffirmed

> **`eco_user_profiles.organization_id` is legacy and non-authoritative.**  
> Authorization and tenant target boundaries are derived exclusively from `public.eco_organization_members`.

---

## 3. Next Step Gate

WP-A3.2.1 is fully implemented, verified, and ready for manual DEV DB application by the human operator.
