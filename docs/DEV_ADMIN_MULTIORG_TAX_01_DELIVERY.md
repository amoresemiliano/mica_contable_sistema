# Multi organization access and IIBB assignment in DEV

DEV-ADMIN-MULTIORG-TAX-01 is implemented and locally verified against base `ed8e9b407e450893e7ae70572008dc1f270e2b9b`. It prepares migration 042, keeps migration 041 byte-identical, and changes only organization context and rate administration. SQL execution, deployment and PROD access were not performed.

## Findings and rate assignment

The repository trace follows `administration.js` → `adminRates.js` → `administrationService.platformRates` → `mica_platform_iibb` → `guard_041_iibb_assignment` → `eco_org_activity_iibb_rates`.

The management selector passes `adminTargetOrg` explicitly to the rate renderer. The renderer passes that target as `p_org` for list, assign and unassign. Assignment state comes from active organization rows matching `definition_id`; after a write, only the rate renderer reloads. These paths do not switch operational context. Assignment/unassignment controls are rendered for a visible target and an active or assigned definition.

The confirmed contract gap is that 041 checks an active assigned economic activity but does not expose that prerequisite in its definition list, and reports a combined generic error for an inactive definition or missing activity. Definition creation is independent of assignment and therefore can succeed while assignment fails. 042 adds target-specific `activity_assigned`, separates inactive-definition and missing-activity errors, and retains the existing scope, rate authority, immutable snapshot trigger and overlapping-period checks. The UI identifies the missing activity by name, disables an unavailable assignment, displays global and company state separately, and refreshes the rate state without clearing the selected company. Unassignment remains available for an assigned rate.

The exact cause of the reported DEV incident is not runtime-confirmed: no server error text was supplied, and remote SQL was forbidden. Missing activity is a reproduced contract failure, not a claimed diagnosis of that specific incident. The final runtime trace remains an acceptance gate; another actual error must be addressed if DEV returns one.

## Multi organization contract

The multi-org restriction is confirmed in the previous code: `list_operational_org_targets` and `switch_superadmin_org_context` require a Platform role; session hydration only requests targets for Platform actors; the selector always prepends Platform and is hidden for normal members. Multiple membership rows therefore did not become operational choices.

042 adds `list_my_organization_contexts()` and `switch_my_organization_context(uuid)`. Tenant choices come only from the caller's active memberships, active organizations and active organization roles, and include the company and role names/IDs. Platform choices continue to come from the canonical explicit scope/root authority. The generic switch delegates Platform actors to the unchanged Platform RPC; tenant actors cannot select null/Platform or an inaccessible UUID. Profile and membership/organization/role locks serialize switching and protect revocable access. Tenant switching writes only `eco_user_active_context`, with an audit event; it never rewrites profile organization ownership or creates another identity.

`get_my_operational_context()` preserves an accessible selected context. With no valid selection it first retains an accessible legacy default, then uses the existing company-list name/UUID order. A user without active memberships receives an authorization error, never Platform. An invalid Platform organization resolves back to Platform. Resolution may persist a default, so the replacement is VOLATILE. Current membership role metadata is returned independently for each organization.

The shell exposes both memberships to a multi-org tenant and omits Platform. A single-org tenant keeps its company name in the existing header. Changing context clears records, perceptions, bank rows, salaries, manual movements, OCR history, import issues, categories, activities, rates, tenant permissions, dataset caches, classification context and tenant preferences before publishing the new snapshot. Hydration retains generation checks and also checks the current role identity before publishing. Failed hydration clears both permissions and data. Existing Platform switching and transport-error reconciliation remain covered by regression tests.

## Migration and rollback

Migration: `sql/042_multiorg_and_rate_assignments.sql`.
Rollback: `sql/042_multiorg_and_rate_assignments_down.sql`.
Prepared runtime/security harness: `tests/db/042_multiorg_and_rate_assignments.sql`.

The migration preflights ten canonical body hashes, owner, fixed search path, SECURITY DEFINER metadata and public/anon grants. It stores the exact definitions, owners and ACLs of the two replaced RPCs. The two new RPCs permit authenticated execution only. Rollback verifies unchanged ownership/ACLs, restores the previous definitions/configuration/volatility, and removes the new contracts and backup table. It retains all contexts, memberships, rates and audit history. No historical migration is edited.

## Verification results

The tracked test tree has 715 passing tests and nine failing historical SQL hash assertions across 64 suites. Those nine failures were already documented on the base delivery; historical SQL files are unchanged in this package. Focused context, authorization-contract and regression suites pass. PostgreSQL/PLpgSQL function syntax parsing passes for migration 042 and rollback, with the runtime harness also parsed as SQL. Parsing does not execute SQL or prove live database authorization.

The local Edge browser executes the real store, selector, header, module access rules, service and Administration renderer with synthetic RPC responses. It passes A → B → A without reload/login, distinct role labels, sidebar/module visibility, cache reset, unauthorized-target rejection, omission of Platform for tenants, IIBB prerequisite/assignment/unassignment state, target retention and desktop/mobile regressions. The RPC fixtures do not prove server runtime behavior.

Repeat local checks:

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests
node tests/browser/admin-target.mjs
git diff --check
```

## DEV acceptance after separate migration and deployment authorization

1. Review/apply 042 against the actual DEV contracts, then execute the rollback-only `tests/db/042_multiorg_and_rate_assignments.sql` harness. Require zero exceptions for different memberships/roles, safe initial context, A/B switching, unauthorized/inactive/removed access, revoked Platform scope, rate authority, prerequisite, overlap and context isolation. SQL has not been executed as part of this delivery.
2. Sign in with a synthetic user assigned to two active companies with different roles. Verify that both companies are in the operational selector and Platform is absent. Select B, then A; the header, role and sidebar must update without login/reload and no previous-company data may remain.
3. Revoke the synthetic user's B membership in another authorized session while its selector is open. A stale attempt to select B must fail. Verify the user cannot select an arbitrary UUID or Platform, and an inaccessible saved context resolves only to a remaining authorized company.
4. Stay in Platform with a managed company. Create a dated IIBB definition for an activity not assigned there. Verify the named prerequisite message. Assign the activity through Actividades, return to Impuestos, assign then desassign the rate. Verify the state changes and both Platform context and the management target remain unchanged. Capture any unexpected RPC error exactly; the reported incident is not closed until this passes on DEV.
5. Open a tenant session and verify only its assigned rates are visible. Repeat organization selection at 390px; no horizontal page overflow, company/role residue or Platform option is acceptable. Verify a scoped Platform user can still enter only authorized companies and return to Platform.

`STATUS=IMPLEMENTED / STATICALLY_VERIFIED / READY_FOR_MANUAL_CHECK`.
`SQL_EXECUTED=NO`, `PROD_TOUCHED=NO`, `DEPLOYED=NO`.
`READY_FOR_DEV_MIGRATION=YES` for review of the prepared script with its fail-closed preflight.
`READY_FOR_DEV_DEPLOY=NO` until DEV migration/harness acceptance and the actual IIBB incident trace pass.
