# Current Work Package: WP-AUTH-RESET-1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-AUTH-RESET-1 — CANONICAL AUTHORIZATION FOUNDATION + CLEAN DEV CUTOVER  
**MODE**: CANONICAL AUTHORIZATION FOUNDATION RECONCILIATION & DEV RESET  
**STATUS**: `READY_FOR_MANUAL_CHECK_1`  
**BASE COMMIT**: `239ef3f3deeef3a906b362351b6e87070ccfbb9f`  

---

## 1. Summary of Deliverables

1. `sql/023_clean_authorization_preflight.sql`:
   - Non-mutating structural preflight validation checking presence of required authorization tables, foreign keys, real DEV users in `auth.users`, and DEV organizations.
   - Does NOT fail on missing role templates, as 023 forward migration reconciles them idempotently.

2. `sql/023_clean_authorization_cutover.sql`:
   - Reconciles all canonical capabilities (17 Platform, 25 Organization).
   - Reconciles all 8 canonical role templates (`PLATFORM_SUPERADMIN`, `ACCOUNTING_SUPERADMIN`, `TENANT_ADMIN`, `ACCOUNTANT`, `UPLOADER`, `REVIEWER`, `READ_ONLY`, `EXTERNAL_AUDITOR`), preserving existing UUIDs and normalizing scopes and descriptions.
   - Recreates canonical role template capability mappings and the `ACCOUNTING_SUPERADMIN` platform-to-org capability bridge (`ORG_VIEW`, etc.).
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
   - Validates that all 8 canonical role templates exist with exact scopes and `is_active = TRUE`.
   - Validates that `ACCOUNTING_SUPERADMIN` possesses the canonical `ORG_VIEW` capability bridge.
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

5. `docs/WP_AUTH_RESET_1_MANUAL_VERIFICATION.md`:
   - Comprehensive, copy-paste ready manual verification pack for the human owner covering Checks 1 through 12.

6. `tests/db/022_identity_and_org_admin.sql`:
   - Marked as `LEGACY / NON-BLOCKING DIAGNOSTIC HARNESS`.

7. `tests/services/identityAndOrgAdminCutover.test.js`:
   - Added automated tests verifying existence and well-formedness of all 023 migration scripts, acceptance matrix test, and manual verification documentation.

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
5. Execute manual checks in `docs/WP_AUTH_RESET_1_MANUAL_VERIFICATION.md`
