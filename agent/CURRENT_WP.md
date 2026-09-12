# Current Work Package: WP-A3.2.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1 — IDENTITY, PROFILES & ORGANIZATION ADMINISTRATION  
**MODE**: IMPLEMENTATION COMPLETE & READY FOR DEV VALIDATION  
**STATUS**: `WP_A3_2_1_IMPLEMENTED`  
**BASELINE SHA**: `e2f9c5baed420d0d1b1e98f2fc260f36505dc6f8`  
**READY_FOR**: `READY_FOR_MANUAL_DEV_DB_VALIDATION`  

---

## 1. Deliverables & Validation Summary

1. `sql/022_identity_and_org_admin_preflight.sql` — Pre-migration baseline verification.
2. `sql/022_identity_and_org_admin.sql` — Forward migration (RPCs `change_user_role`, `set_user_active`, `switch_superadmin_org_context`; RLS on `eco_organizations`, `eco_user_profiles`, `eco_audit_events`).
3. `sql/022_identity_and_org_admin_postcheck.sql` — Post-migration verification script.
4. `sql/022_identity_and_org_admin_down.sql` — Clean rollback script isolated to M022.
5. `tests/db/022_identity_and_org_admin.sql` — Transactional DB behavioral test suite (21 test cases).
6. `docs/MICA_A3_2_1_DESIGN.md` — Detailed technical design specification.
7. `docs/MICA_A3_2_1_COMPATIBILITY_CONTRACT.md` — Backward & bidirectional compatibility contract.
8. `docs/MICA_A3_2_1_SECURITY_ACCEPTANCE_MATRIX.md` — Comprehensive security truth table and test matrix.
9. `docs/MICA_A3_2_1_MANUAL_DEV_VALIDATION.md` — Manual DEV browser/persona validation runbook.
10. `tests/services/identityAndOrgAdminCutover.test.js` — Automated Jest test suite passing 100%.

---

## 2. Core Architectural Alignments

- **Canonical Self-Identity**: `auth.users.id` &rarr; `public.eco_user_profiles.auth_user_id` (`auth_user_id = auth.uid() AND is_active = TRUE`).
- **Canonical Membership Authority**: Multi-org profile administration is governed strictly by `public.eco_organization_members` instead of legacy `profile.organization_id`.
- **Capability Governance**:
  - `change_user_role` &rarr; `ORG_MEMBER_PERMISSION_MANAGE`
  - `set_user_active` &rarr; `ORG_MEMBER_MANAGE`
  - `switch_superadmin_org_context` &rarr; `SUPPORT_IMPERSONATE` / `ACCESS_ANY_ORG`
  - `eco_organizations` &rarr; `ORG_VIEW` (set-based)
  - `eco_user_profiles` &rarr; Self (`auth.uid()`) + `ORG_MEMBER_VIEW` (canonical membership join)
  - `eco_audit_events` &rarr; `AUDIT_VIEW_ORG` (set-based)
- **Append-Only Audit Guarantee**: `enforce_append_only_audit` trigger preserved unmodified.

---

## 3. Next Step Gate

WP-A3.2.1 is fully implemented and tested locally. The human operator will manually apply `sql/022_identity_and_org_admin.sql` in Supabase DEV to execute manual DEV database validation.
