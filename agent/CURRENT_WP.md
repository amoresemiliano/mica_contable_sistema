# Current Work Package: WP-AUTH-RESET-1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-AUTH-RESET-1 — CLEAN DEV AUTHORIZATION CUTOVER  
**MODE**: CLEAN CANONICAL AUTHORIZATION CUTOVER & DEV RESET  
**STATUS**: `READY_FOR_MANUAL_023_PREFLIGHT`  
**BASE COMMIT**: `80a9afed0132fb9823de227aa7d363624125e93e`  

---

## 1. Summary of Deliverables

1. `sql/023_clean_authorization_preflight.sql`:
   - Non-mutating preflight validation checking presence of required authorization tables, canonical private helper functions, role templates, active `ORG_VIEW` capability, real DEV users in `auth.users`, and DEV organizations.

2. `sql/023_clean_authorization_cutover.sql`:
   - Drops all legacy/competing SELECT policies on `public.eco_organizations` (`"Organizations member view"`, `"Organizations viewable by own users"`, etc.).
   - Establishes the single canonical SELECT policy on `public.eco_organizations` using `private.authorized_orgs_for_capability('ORG_VIEW')`.
   - Forces RLS on `public.eco_organizations`.
   - Updates `private.org_id()` to strictly return `private.active_org_id()`, eliminating reliance on deprecated `eco_user_profiles.organization_id`.
   - Deterministically purges MICA legacy organization (`59436df3-9f15-4f5e-b17e-37c55482521c`) memberships and overrides for the five real DEV users.
   - Resets platform roles:
     - `vegendigital@gmail.com` -> `PLATFORM_SUPERADMIN`
     - `drcmarianela@gmail.com` -> `ACCOUNTING_SUPERADMIN`
     - Emiliano, Edravi, Calle -> No platform role
   - Resets tenant memberships:
     - VEGEN: 0 memberships
     - MARIANELA: DEMO NORTE, DEMO SUR, DEMO OESTE (`role_template_id = NULL`)
     - EMILIANO: DEMO NORTE only (`TENANT_ADMIN`)
     - EDRAVI: DEMO SUR only (`TENANT_ADMIN`)
     - CALLE: DEMO OESTE only (`TENANT_ADMIN`)
   - Resets canonical active context (`eco_user_active_context`) and normalizes compatibility display columns.

3. `sql/023_clean_authorization_postcheck.sql`:
   - Validates that exactly 1 SELECT policy exists on `public.eco_organizations` governed by `ORG_VIEW`.
   - Validates that MICA legacy org has 0 active memberships for all 5 real users.
   - Validates exact membership and platform role assignments for all 5 users.
   - Validates that `private.org_id()` delegates strictly to `active_org_id()`.

4. `tests/db/023_authorization_matrix.sql`:
   - Small, clean, readable (< 200 lines) acceptance test exercising real DEV personas under authenticated role simulation (`SET LOCAL ROLE authenticated`).
   - Asserts exact visible organizations for Emiliano ({NORTE}), Edravi ({SUR}), Calle ({OESTE}), Marianela ({NORTE, SUR, OESTE}), and VEGEN ({0}).
   - Proves active context changes do not expand unauthorized organization visibility.
   - Proves cross-tenant mutation RPCs fail closed.
   - Runs safely under `BEGIN ... ROLLBACK`.

5. `tests/db/022_identity_and_org_admin.sql`:
   - Marked as `LEGACY / NON-BLOCKING DIAGNOSTIC HARNESS`.

6. `tests/services/identityAndOrgAdminCutover.test.js`:
   - Added automated tests verifying existence and well-formedness of all 023 migration scripts and acceptance matrix test.

---

## 2. Verification

- `npm test`: 22 test suites passed, 270 tests passed.
- Accounting processing logic & importers: 100% untouched.
- Supabase live database: 100% untouched (Awaiting human execution).

---

## 3. Human Execution Gate (Sequential Steps in Supabase SQL Editor)

1. `sql/023_clean_authorization_preflight.sql`
2. `sql/023_clean_authorization_cutover.sql`
3. `sql/023_clean_authorization_postcheck.sql`
4. `tests/db/023_authorization_matrix.sql`
