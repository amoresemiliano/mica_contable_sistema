# Current Work Package: WP-A3.2.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1 — IDENTITY, PROFILES & ORGANIZATION ADMINISTRATION  
**MODE**: IMPLEMENTATION COMPLETE & FINAL PRE-DEV SEMANTIC FIX RESOLVED  
**STATUS**: `WP_A3_2_1_IMPLEMENTED`  
**BASELINE SHA**: `fab6e49633228d10b86e0439db879f32c57e6b97`  
**READY_FOR**: `READY_FOR_JULES_PRE_DEV_REVIEW`  

---

## 1. Deliverables & Semantic Fix Summary

1. `sql/022_identity_and_org_admin.sql` — Forward migration:
   - `change_user_role`: Mutates canonical `eco_organization_members.role_template_id` based on deterministic target org resolution (explicit `p_org_id`, active context, or unique authorized membership; fails closed with `AMBIGUOUS_ORGANIZATION_CONTEXT` on ambiguity). Syncs `eco_user_profiles.role` for session display compatibility only (lossy, zero authorization readers).
   - `set_user_active`: Operates strictly on `eco_organization_members.is_active` for tenant administration (`ORG_MEMBER_MANAGE`), guaranteeing tenant membership isolation without deactivating global profiles or cross-tenant memberships.
   - `set_global_user_active`: Dedicated platform-scoped RPC operating strictly on `eco_user_profiles.is_active` governed by `GLOBAL_USER_MANAGE` / `PLATFORM_MANAGE`. Zero dependence on `active_org_id()`, completely isolated from tenant memberships.
   - `switch_superadmin_org_context`: Platform capability-governed (`SUPPORT_IMPERSONATE` / `ACCESS_ANY_ORG`) context switching.
   - Set-based RLS on `eco_organizations`, `eco_user_profiles`, and `eco_audit_events`.
2. `sql/022_identity_and_org_admin_preflight.sql` — Pre-migration baseline verification.
3. `sql/022_identity_and_org_admin_postcheck.sql` — Post-migration verification script (including `set_global_user_active` verification).
4. `sql/022_identity_and_org_admin_down.sql` — Rollback script cleanly restoring pre-M022 definitions and dropping new RPCs.
5. `tests/db/022_identity_and_org_admin.sql` — Comprehensive DB behavioral test suite (tenant membership vs global profile state isolation, active context independence, multi-org role isolation, ambiguity fail-closed tests).
6. `docs/MICA_A3_2_1_DESIGN.md` — Detailed technical design specification.
7. `docs/MICA_A3_2_1_COMPATIBILITY_CONTRACT.md` — Backward & bidirectional compatibility contract.
8. `docs/MICA_A3_2_1_SECURITY_ACCEPTANCE_MATRIX.md` — Comprehensive security truth table and test matrix.
9. `docs/MICA_A3_2_1_MANUAL_DEV_VALIDATION.md` — Manual DEV browser/persona validation runbook.
10. `tests/services/identityAndOrgAdminCutover.test.js` — Automated Jest test suite passing 100%.

---

## 2. Fundamental Architectural Rules Reaffirmed

> **1. Active Context != Authorization**: `active_org_id()` is a selector, never an authority grant/denial for platform operations.  
> **2. `eco_user_profiles.organization_id` & `role` are non-authoritative**: Authorization and tenant target boundaries are derived exclusively from `public.eco_organization_members`.

---

## 3. Next Step Gate

WP-A3.2.1 is fully implemented, verified, and ready for pre-DEV review.
