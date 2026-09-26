# Owner operational context — Phase 1

Base: `9855b31c4acad055e35e5f6de53b441f2c63d102`.
Implementation is local. Migration and DB integration tests have NOT been executed.

## Review/apply order

1. Review the full `sql/035_owner_operational_context.sql` and confirm LIVE contracts below.
2. Apply 035 manually in DEV, then run the DB integration test with existing authorized users.
3. Load the matching frontend and perform the five browser checks below.

The frontend requires the new RPCs. Do not publish it before the migration is applied.
No historical migration, `can_org`, or catalog assignment capability is changed.

## LIVE preflight (read-only, not executed by the agent)

```sql
SELECT p.oid::regprocedure AS signature,
       pg_get_function_result(p.oid) AS result,
       p.proargnames, p.prosecdef, p.proconfig
FROM pg_proc p
WHERE p.oid IN (
  to_regprocedure('public.switch_superadmin_org_context(uuid)'),
  to_regprocedure('private.current_profile_id()'),
  to_regprocedure('private.active_org_id()'),
  to_regprocedure('private.can_platform(text)'),
  to_regprocedure('private.can_org(uuid,text)')
);
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('eco_organizations', 'eco_user_active_context',
                    'eco_organization_members', 'eco_user_platform_role', 'eco_role_templates')
ORDER BY table_name, ordinal_position;
```

Expected switch: `switch_superadmin_org_context(p_org_id uuid) RETURNS void`.
Required: organization `is_active boolean`; canonical active-context row; membership/template tables;
catalog assignment `is_assigned`; normalized/financial soft deletion columns.
The migration aborts if the reviewed switch signature or primary authorization prerequisites differ.
Other referenced columns/tables must also be reviewed against LIVE before application.

## RPC changes

- `list_operational_org_targets()` returns active IDs/names, only for effective `ACCESS_ANY_ORG`.
- `switch_superadmin_org_context(uuid)` keeps its signature, requires active identity/capability/target,
  serializes changes for the profile and records the platform audit event.
- `get_my_operational_context()` returns confirmed org and real membership preset, falling back to
  the active platform preset. No `profile.role` or Google display name is used as authority.
- `get_operational_snapshot(uuid)` checks the expected current org and returns only assigned
  categories/activities (`ORG_VIEW`) and active rates (`CATALOG_ORG_VIEW`).
- `get_operational_records_page(uuid,uuid,integer)` and `get_operational_financials_page(uuid,uuid,integer)`
  expose explicit fields in batches of at most 500, requiring `RECORD_VIEW` or the owner capability.
  Every page checks the expected confirmed active organization. Owner read access does not grant writes.
- See [035 pre-application review](035_PRE_APPLICATION_REVIEW.md) for exact payload allowlists,
  repo authority evidence, expanded preflight and LIVE definition/ACL rollback.

## Browser acceptance checks

1. Owner: Platform -> NORTE -> SUR -> Platform from Comprobantes, Bancos, Sueldos, Categorización
   and Panel. The selected module stays open; empty destinations show empty data, never the previous org.
2. Inspect the header: authenticated email, confirmed org, actual preset name. An owner without membership
   shows its platform preset, not a fabricated tenant administrator role.
3. Owner has no operational upload/drop controls. A tenant with IMPORT_CREATE and the appropriate
   BANK_IMPORT/PAYROLL_IMPORT/PERCEPTION_IMPORT capability keeps the corresponding controls.
   Global catalog import remains available in Platform with GLOBAL_CATALOG_MANAGE.
4. In browser DevTools, fail the snapshot or a historical page after a successful switch. No previous rows may appear;
   retry must reload the confirmed destination. A denied switch must retain the previous context/data.
5. Delay a snapshot, log out, then sign in as another user. The old response must never refill the store.
   A user with only CATALOG_ASSIGN_ANY_ORG must never receive an operational selector.

## Deliberate Phase 1 limits

- Manual movements and OCR are cleared and disabled: no persistent reader/writer is invented.
- Import issues are cleared; the previous unscoped issue reader/bulk mutation is disabled pending a
  dedicated tenant contract. This phase's minimum rehydration does not include issue resolution.
- Bank rules/templates and category history use `auth_user_id + organization_id` keys. Unowned legacy
  keys are not automatically copied. Column visibility remains a presentation preference.
- Concurrent local switches are rejected while a switch/load/write is pending; no advanced multitab coordination.
- The context is still shared per profile on the server. Snapshot org checks and a post-load context read
  detect mismatches, but do not replace server-side versioned mutation guards across tabs. Use one tab in Phase 1.
- Existing operational write RPC authorization is not comprehensively migrated in this block. The owner's
  importer restriction is enforced in the frontend; this migration adds no server-side import prohibition.
- Historical responses are bounded (500 rows per request); the frontend still assembles all rows in
  temporary memory for existing grids. This is not a cross-request MVCC snapshot or lazy-loading UI.
- `sql/035_owner_operational_context_down.sql` restores the actual switch definition, owner and effective
  ACL captured by 035, then removes only the five new RPCs and the private migration backup.
  Roll back frontend/RPC contracts together. Neither migration nor rollback has been executed.

## Verification

Run the full suite with:

```powershell
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand
git diff --check
```

DB integration script: `tests/db/035_owner_operational_context.sql` (transaction with ROLLBACK).
Its identities are explicit psql inputs; it does not create users, memberships or organizations.
