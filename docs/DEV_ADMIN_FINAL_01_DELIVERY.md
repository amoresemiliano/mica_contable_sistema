# Administration completion in DEV

DEV-ADMIN-FINAL-01 is implemented and verified with local UI fixtures and static contract tests. Database runtime acceptance remains pending. No SQL was executed, no deployment was made, and PROD was not accessed.

The requested base is `313a75dc1c572930f323fa9c1e91df236ae4e8f6`. At the start of this review, both the checkout and remote `dev` already contained its direct successor, `e0a749713520c12aef1bb97951f28abe37b5360e`, with the Administration implementation. This delivery adds explicit company actions to the access summary, preserves the company when changing an existing role, removes the obsolete Platform context requirement, and expands browser assertions.

## Tax model and authorization

The repository schema stores tenant IIBB rows in `public.eco_org_activity_iibb_rates`, with activity, jurisdiction, rate, effective dates and active state. It has no global definitions catalogue. Migration 041 adds private global version definitions and attaches their provenance to every existing organization row. It does not delete historical rows or replace the operational readers. Assignment creates organization snapshots; unassignment deactivates them. New versions preserve prior versions. IVA remains the existing general reference catalogue.

`mica_platform_iibb` requires `RATE_MANAGE_ANY_ORG`, Platform context and the canonical explicit scope for the target. It requires an assigned active activity and rejects overlapping active periods. A trigger blocks legacy tenant writes to the globally owned IIBB assignment model. Tenant UI is read-only for these rates.

`mica_platform_access` uses explicit targets without modifying operational context. Authorization requires canonical global user administration authority (`GLOBAL_USER_MANAGE` or the existing `MICA_ADMIN_MANAGE` compatibility contract), active organization scope, bridged invitation/member/role authority and full role delegation checks. Protected users, self-administration and incompatible roles remain restricted. Existing email uses the canonical profile and membership table; new email creates pending preauthorization rather than another auth identity. Authentication, assignment confirmation and account activation remain separate. This flow does not send an authentication email automatically.

The new RPCs retain `SECURITY DEFINER`, fixed empty search paths, restricted execution grants and audit events. Existing tenant authorization functions are not replaced. Migration preflight checks twelve canonical function body hashes plus security metadata; rollback removes new contracts and provenance while archiving definitions and assignments and retaining business/access history.

Migration: `sql/041_administration_completion.sql`.
Rollback: `sql/041_administration_completion_down.sql`.
Prepared negative/runtime harness: `tests/db/041_administration_completion.sql`.

Live DEV schema and SQL harness execution are unverified. The migration header explicitly records this limitation. The scripts require review against actual DEV before application; deployment readiness depends on passing that gate.

## Administration experience

Users for the managed company have a useful empty state and an invitation/assignment action. The editor defaults to company access when a management target exists, lists authorized companies and compatible human-readable roles, and provides Platform access separately. Advanced navigation uses Usuarios, Roles and Accesos. Role editing groups permissions by function; exceptions remain collapsed. The access summary offers company role changes and soft access removal with confirmation. Editing an access to Company A retains Company A even if Company B is the current management target.

Company detail uses the shared native modal drawer with backdrop, close control, scroll, all requested profile fields and a 600px desktop width. Browser assertions verify top-layer rendering above a sidebar with maximum z-index at 1440px and 390px. Tenant administration also passes page overflow checks at 320px.

## Verification

The tracked test tree reports 702 passing tests and nine failing historical migration hash assertions across 62 suites. The changed SQL/UI contract suites pass. All nine failures first disagree on `sql/009_supabase_native_auth.sql`; comparison with the requested base confirms the same bytes were already present there. Four files in the 038 hash manifest disagree with that manifest but match the requested base exactly: 009, 016, 018 and 018 rollback. Historical migrations and manifests were not changed to conceal the discrepancy.

Run the tracked tree with:

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests
node tests/browser/admin-target.mjs
git diff --check
```

The browser check passes global IIBB creation/assignment/unassignment, company and Platform invitation, existing identity assignment, authorized company selector, role filtering, advanced navigation, access-company preservation, collapsed exceptions, native modal stacking, tenant assigned-rate view, safe date/text rendering and mobile overflow. RPC responses are local fixtures; these checks do not verify database authorization at runtime.

The default unbounded Jest discovery also discovers an untracked `.local-data/040-baseline` copy of old tests. Its additional failures are not part of the tracked test-tree result above.

## Manual DEV acceptance after database validation

These checks are for the later authorized DEV migration/deployment stage. Do not run them against PROD.

1. Apply the reviewed 041 migration in DEV only after its canonical preflight matches; execute `tests/db/041_administration_completion.sql` and require its transaction to finish without exceptions. It rolls back synthetic fixtures.
2. Stay in Vegen Platform, choose a permitted company, open Usuarios and invite a new email with a company role. Authenticate that account, confirm its assignment, and explicitly activate it. Assign an existing confirmed account and verify that the auth identity is reused.
3. Open Impuestos, create an IIBB version with an assigned activity and effective dates, assign it to the managed company, then unassign it. Verify the Platform operational context stays unchanged and the tenant sees only its active assigned rates.
4. Open Permisos avanzados and switch between Usuarios, Roles and Accesos. Change a user's role for a company different from the management target; verify the editor retains the access company. Remove access with confirmation and verify it becomes inactive. Exceptions must start collapsed.
5. Open company detail using the eye action at desktop and 390px width. Verify it appears above the sidebar, all fields are readable, content scrolls and the close control restores focus.

Readiness: prepared migration and rollback are available; `READY_FOR_DEV_MIGRATION=NO` until actual DEV contract review, and `READY_FOR_DEV_DEPLOY=NO` until migration and runtime security acceptance pass. The historical hash mismatch is tracked verification debt. `SQL_EXECUTED=NO`, `PROD_TOUCHED=NO`, `DEPLOYED=NO`.
