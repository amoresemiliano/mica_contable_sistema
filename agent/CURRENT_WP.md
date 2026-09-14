# Current Work Package: WP-A3.2.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1 — IDENTITY, PROFILES & ORGANIZATION ADMINISTRATION  
**MODE**: IMPLEMENTATION COMPLETE & LIVE DEV FIXTURE PROFILE RECONCILIATION RESOLVED  
**STATUS**: `WP_A3_2_1_IMPLEMENTED`  
**BASELINE SHA**: `6ebb2c7aa11753d6a386b76bb2ad6094b6d7b9c9`  
**READY_FOR**: `READY_FOR_JULES_RECHECK`  

---

## 1. Deliverables & Live DEV Profile Reconciliation Summary

1. `tests/db/022_identity_and_org_admin.sql` — DB behavioral test suite:
   - Implemented dual-mode synthetic profile reconciliation supporting both auto-created profile environments (live Supabase DEV auth triggers) and explicit profile insertion environments.
   - For every synthetic user, attempts resolving profile by `auth_user_id`; updates `organization_id`, `role`, and `is_active` if present, or inserts directly using canonical columns if absent.
   - Added `SYNTHETIC_PROFILE_CARDINALITY_ERROR` assertion ensuring exactly 1 profile row exists per synthetic user.
   - Maintained strict transaction isolation with `BEGIN ... ROLLBACK`.
2. `sql/022_identity_and_org_admin.sql` — Forward migration (untouched).
3. `sql/022_identity_and_org_admin_preflight.sql` — Pre-migration baseline verification (untouched).
4. `sql/022_identity_and_org_admin_postcheck.sql` — Post-migration verification script (untouched).
5. `sql/022_identity_and_org_admin_down.sql` — Rollback script (untouched).
6. `docs/MICA_A3_2_1_DESIGN.md` — Detailed technical design specification.
7. `docs/MICA_A3_2_1_COMPATIBILITY_CONTRACT.md` — Backward & bidirectional compatibility contract.
8. `docs/MICA_A3_2_1_SECURITY_ACCEPTANCE_MATRIX.md` — Comprehensive security truth table and test matrix.
9. `docs/MICA_A3_2_1_MANUAL_DEV_VALIDATION.md` — Manual DEV browser/persona validation runbook.
10. `tests/services/identityAndOrgAdminCutover.test.js` — Automated Jest test suite passing 100%.

---

## 2. Fundamental Architectural Rules Reaffirmed

> **1. Active Context != Authorization**: `active_org_id()` is a selector, never an authority grant/denial for platform operations.  
> **2. Partitioned Audit Architecture**: Tenant audit (`eco_audit_events`, org NOT NULL) vs Platform audit (`eco_platform_audit_events`, global/platform scope).  
> **3. `eco_user_profiles.organization_id` & `role` are non-authoritative**: Authorization and tenant target boundaries are derived exclusively from `public.eco_organization_members`.

---

## 3. Next Step Gate

WP-A3.2.1 is fully implemented, verified, and ready for behavioral test re-run in Supabase SQL Editor.
