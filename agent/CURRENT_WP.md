# Current Work Package: WP-A3.2.1-VH1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-A3.2.1-VH1 — BEHAVIORAL SECURITY HARNESS AUTHENTICATED ROLE SIMULATION  
**PARENT WP**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
**MODE**: BEHAVIORAL TEST HARNESS AUTHENTICATED ROLE SIMULATION IMPLEMENTED  
**STATUS**: `WP_A3_2_1_VH1_IMPLEMENTED`  
**BASE COMMIT**: `467e57e49b510f1a556e667364e5c1a7ceaec654`  
**READY_FOR**: `READY_TO_RERUN_DB_022`  

---

## 1. Summary of Changes

1. `tests/db/022_identity_and_org_admin.sql`:
   - Updated DB behavioral security test suite to simulate Supabase `authenticated` role (`SET LOCAL ROLE authenticated`) for all RLS visibility and RPC assertions.
   - Preserves privileged fixture setup (baseline check, synthetic user & profile reconciliation, membership creation) and privileged teardown (`BEGIN ... ROLLBACK`).
   - Created persona switching helper `harness_set_persona(p_auth_id)` setting both JWT claim (`request.jwt.claim.sub`) and PostgreSQL role (`SET LOCAL ROLE authenticated`).
   - Added role fail-fast assertion checking `current_user = 'authenticated'`, raising `BEHAVIORAL_TEST_NOT_RUNNING_AS_AUTHENTICATED` if not running under `authenticated`.
   - Created privileged role reset helper `harness_reset_role()` (`EXECUTE 'RESET ROLE'`) for temporary privileged assertions or setup modifications.
   - Maintained strict expected test counts: Emiliano sees 1 org (DEMO NORTE), Marianela sees 3 orgs (NORTE, SUR, OESTE).
2. `tests/services/identityAndOrgAdminCutover.test.js`:
   - Added automated Jest checks confirming `BEHAVIORAL_TEST_NOT_RUNNING_AS_AUTHENTICATED`, `SET LOCAL ROLE authenticated`, `harness_set_persona`, and `harness_reset_role` exist in the DB harness.
3. Untouched files:
   - `sql/022_identity_and_org_admin.sql` (Forward migration)
   - `sql/022_identity_and_org_admin_preflight.sql`
   - `sql/022_identity_and_org_admin_postcheck.sql`
   - `sql/022_identity_and_org_admin_down.sql`
   - RLS policies, RPCs, DB schema, frontend.

---

## 2. Test Verification

- `npm test`: 22 test suites passed, 269 tests passed.

---

## 3. Next Step Gate

`tests/db/022_identity_and_org_admin.sql` is ready to re-run in Supabase SQL Editor against DEV.
