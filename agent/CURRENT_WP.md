# Current Work Package: WP-A3.2.1-VH1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1-VH1 — FINAL BEHAVIORAL HARNESS HARDENING  
**PARENT WP**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
**MODE**: FINAL BEHAVIORAL HARNESS HARDENING IMPLEMENTED  
**STATUS**: `WP_A3_2_1_VH1_HARDENED`  
**BASE COMMIT**: `25041e59c11be456838f3ade42a727f8dbe2118f`  
**READY_FOR**: `READY_TO_RERUN_DB_022`  

---

## 1. Summary of Changes

1. `tests/db/022_identity_and_org_admin.sql`:
   - **Removed direct internal `private.can_org` call**: Replaced direct schema invocation `private.can_org(v_sur_org_id, 'ORG_MEMBER_PERMISSION_MANAGE')` with a public behavioral negative test invoking `public.change_user_role(v_synth_user_b_profile_id, 'ADMIN', v_sur_org_id)` as Synthetic Multi, asserting that it fails closed with `FORBIDDEN`.
   - **Zero authenticated calls to `private.*`**: Scanned and verified that no authenticated test phase accesses private schema objects.
   - **Privileged/Authenticated Separation**: Fixture setups (active context assignment/deletion, synthetic member creation, inactive state toggles) and append-only trigger integrity tests run under `harness_reset_role()`; application behavior, RLS visibility, and RPC entrypoints run under `harness_set_persona()` (`authenticated`).
   - **Conflicting Legacy Policy Guard**: Added fail-fast baseline check in Section 0 detecting whether conflicting legacy policy `"Organizations member view"` exists on `public.eco_organizations`, raising `LEGACY_ORGANIZATION_RLS_POLICY_PRESENT`.
   - **DEV Legacy Drift Documented**: The legacy policy `"Organizations member view"` on `public.eco_organizations` was present in DEV because M022 only dropped `"Organizations viewable by own users"`. This policy was manually removed in DEV.
   - **Transaction Rollback Preserved**: The entire script remains wrapped in `BEGIN; ... ROLLBACK;`.

2. `tests/services/identityAndOrgAdminCutover.test.js`:
   - Added automated Jest assertions verifying absence of `private.` direct calls and presence of `LEGACY_ORGANIZATION_RLS_POLICY_PRESENT` drift guard.

3. Untouched files:
   - `sql/022_identity_and_org_admin.sql` (Forward migration)
   - `sql/022_identity_and_org_admin_preflight.sql`
   - `sql/022_identity_and_org_admin_postcheck.sql`
   - `sql/022_identity_and_org_admin_down.sql`
   - RLS policies, RPCs, DB schema, permissions, frontend.

---

## 2. Test Verification

- `npm test`: 22 test suites passed, 269 tests passed.

---

## 3. Next Step Gate

`tests/db/022_identity_and_org_admin.sql` is ready for final rerun in Supabase SQL Editor against DEV.
