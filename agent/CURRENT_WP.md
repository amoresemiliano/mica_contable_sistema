# Current Work Package: WP-A3.2.1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1 — IDENTITY, PROFILES & ORGANIZATION ADMINISTRATION  
**MODE**: IMPLEMENTATION COMPLETE & SUPABASE SQL EDITOR COMPATIBILITY FIX RESOLVED  
**STATUS**: `WP_A3_2_1_IMPLEMENTED`  
**BASELINE SHA**: `645a4636be303851e4aebe6a46da5594abd80bea`  
**READY_FOR**: `READY_FOR_JULES_RECHECK`  

---

## 1. Deliverables & Platform Audit Blocker Summary

1. `sql/022_identity_and_org_admin.sql` — Forward migration:
   - `public.eco_platform_audit_events`: Dedicated platform audit table with append-only trigger (`enforce_append_only_platform_audit`) and RLS restricted to `AUDIT_PLATFORM_VIEW` / `PLATFORM_MANAGE`.
   - `set_global_user_active`: Dedicated platform RPC emitting `GLOBAL_USER_ACTIVE_CHANGED` into `eco_platform_audit_events`. Zero dependence on active tenant context.
   - `switch_superadmin_org_context`: Emits `SUPERADMIN_ORG_CONTEXT_SWITCHED` into `eco_platform_audit_events`.
   - `change_user_role`: Mutates canonical `eco_organization_members.role_template_id`. Supports configuring inactive memberships prior to reactivation (`is_active` remains `FALSE`).
   - `set_user_active`: Operates strictly on `eco_organization_members.is_active` for tenant administration (`ORG_MEMBER_MANAGE`), emitting tenant audit to `eco_audit_events`.
   - Set-based RLS on `eco_organizations`, `eco_user_profiles`, and `eco_audit_events`.
2. `sql/022_identity_and_org_admin_preflight.sql` — Pre-migration baseline verification.
3. `sql/022_identity_and_org_admin_postcheck.sql` — Post-migration verification script (including `eco_platform_audit_events` and RLS).
4. `sql/022_identity_and_org_admin_down.sql` — Rollback script cleanly dropping `eco_platform_audit_events` and restoring pre-M022 definitions.
5. `tests/db/022_identity_and_org_admin.sql` — Comprehensive DB behavioral test suite:
   - Directly executable in Supabase SQL Editor against applied M022 schema (no `\i` meta-command).
   - Fail-fast baseline check asserting all M022 RPCs, platform audit table, and triggers exist before fixture creation.
   - Full transaction safety with `BEGIN ... ROLLBACK`.
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
