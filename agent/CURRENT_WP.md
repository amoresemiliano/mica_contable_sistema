# Current Work Package: WP-AUTH-RESET-1

**PROJECT**: MICA  
**WORK PACKAGE**: WP-AUTH-RESET-1 — FINAL REPOSITORY ALIGNMENT + LOCAL EFFICIENT DELIVERY SKILL  
**MODE**: CANONICAL AUTHORIZATION FOUNDATION RECONCILIATION & DEV RESET  
**STATUS**: `DEV_RUNTIME_VERIFIED`  
**BASE COMMIT**: `ddfcb87adce13f2fa370d0101c5aa11794cd887f`  

---

## 1. Summary of Deliverables & Alignment

1. `sql/023_clean_authorization_cutover.sql`:
   - Reconciles all canonical capabilities (17 Platform, 25 Organization).
   - Reconciles all 8 canonical role templates (`PLATFORM_SUPERADMIN`, `ACCOUNTING_SUPERADMIN`, `TENANT_ADMIN`, `ACCOUNTANT`, `UPLOADER`, `REVIEWER`, `READ_ONLY`, `EXTERNAL_AUDITOR`), preserving existing UUIDs and normalizing scopes and descriptions.
   - Recreates canonical role template capability mappings and the `ACCOUNTING_SUPERADMIN` platform-to-org capability bridge (`ORG_VIEW`, etc.).
   - Drops all legacy/competing SELECT policies on `public.eco_organizations`, explicitly including:
     ```sql
     DROP POLICY IF EXISTS org_members_read_orgs ON public.eco_organizations;
     ```
   - Establishes the single canonical SELECT policy on `public.eco_organizations` using `private.authorized_orgs_for_capability('ORG_VIEW')`.
   - Forces RLS on `public.eco_organizations`.
   - Resets platform roles and tenant memberships for the 5 real DEV users.
   - Resets active context (`eco_user_active_context`) and compatibility columns.

2. `sql/023_clean_authorization_postcheck.sql`:
   - Validates that all 8 canonical role templates exist with exact scopes and `is_active = TRUE`.
   - Validates that `ACCOUNTING_SUPERADMIN` possesses the canonical `ORG_VIEW` capability bridge.
   - Validates that exactly 1 SELECT policy exists on `public.eco_organizations` governed by `ORG_VIEW`.
   - Asserts absence of legacy permissive policies including `'org_members_read_orgs'`.
   - Validates that MICA legacy org has 0 active memberships for all 5 real users.
   - Validates exact membership and platform role assignments for all 5 users.
   - Validates that `private.org_id()` delegates strictly to `active_org_id()`.

3. `tests/db/023_authorization_matrix.sql`:
   - Small, clean acceptance test exercising real DEV personas under authenticated role simulation (`SET LOCAL ROLE authenticated`).
   - Asserts exact visible organizations for Emiliano ({NORTE}), Edravi ({SUR}), Calle ({OESTE}), Marianela ({NORTE, SUR, OESTE}), and VEGEN ({0}).
   - Proves active context changes do not expand unauthorized organization visibility.
   - Proves cross-tenant mutation RPCs fail closed.

4. `docs/WP_AUTH_RESET_1_MANUAL_VERIFICATION.md`:
   - Comprehensive, copy-paste ready manual verification pack for the human owner covering Checks 1 through 12.
   - Updated CHECK 6 documenting single SELECT policy enforcement without `org_members_read_orgs`.

5. Local Efficient Delivery Skill:
   - Created at `.agents/skills/efficient-delivery/SKILL.md` (and `.agent/skills/efficient-delivery/SKILL.md`).
   - Establishes 14 core rules for minimal human/agent cycles to achieve verified observable progress.

6. Project Agent Context:
   - Created `agent/CONTEXT.md` requiring:
     1. `autonomous-engineering-execution`
     2. `evidence-first-engineering`
     3. `efficient-delivery`

---

## 2. Verification & DEV Runtime Status

- `sql/023_clean_authorization_preflight.sql` -> PASS
- `sql/023_clean_authorization_cutover.sql` -> PASS
- `DROP POLICY IF EXISTS org_members_read_orgs ON public.eco_organizations;` -> Applied & Codified
- `sql/023_clean_authorization_postcheck.sql` -> PASS
- `tests/db/023_authorization_matrix.sql` -> PASS
- Next Step: Ready for functional browser validation (`READY_FOR_FUNCTIONAL_BROWSER_VALIDATION: YES`).
