# MICA — WP-A1 Acceptance Contract v1.1

Status: **REVISED — PENDING FINAL REVIEW**

## Required result

A new capability-based authorization foundation exists additively while current application behavior remains unchanged.

## Acceptance criteria

1. New tables exist with intended constraints.
2. `eco_organization_members.role_template_id` exists and is nullable.
3. Current `UNIQUE(organization_id, user_profile_id)` membership invariant remains present.
4. Existing `eco_organization_members.role` remains untouched.
5. Legacy `eco_user_profiles.organization_id` remains untouched.
6. Legacy `eco_user_profiles.role` remains untouched.
7. Existing RLS policy definitions remain equivalent before vs after WP-A1.
8. Existing RPC definitions remain unchanged.
9. Existing application tests remain green.
10. New schema and helper tests pass.
11. Capability seed data is complete and idempotent.
12. `current_profile_id`, `active_org_id`, `can_platform`, `can_org` fail closed.
13. `eco_user_active_context.organization_id` uses `ON DELETE SET NULL`.
14. Deleting an organization is not blocked by active-context rows.
15. Active context alone never grants tenant access.
16. Inactive platform role grants nothing.
17. Inactive role template grants nothing.
18. Inactive capability grants nothing.
19. ACCOUNTING_SUPERADMIN org grants require active membership in target org.
20. ACCOUNTING_SUPERADMIN without membership cannot operate target org through `can_org`.
21. ACCOUNTING_SUPERADMIN organization capability bridge works only for configured org-scoped capabilities.
22. PLATFORM_SUPERADMIN receives no implicit `can_org` bypass in WP-A1.
23. Explicit membership DENY beats all base ALLOW grants.
24. Explicit membership ALLOW grants a capability absent from base templates/bridge.
25. A current real user with no new authorization assignment fails closed in new helpers.
26. Empty new authorization state does not alter legacy application behavior.
27. No dual-write triggers are introduced in WP-A1.
28. No real-user assignments are migrated in WP-A1.
29. Preflight exists.
30. Postcheck exists.
31. DOWN/rollback removes only WP-A1 additions.
32. No organization/accounting data is mutated.
33. Jules final security/design review is APPROVE before live DEV apply.

## Stop condition

If implementation requires modifying an existing RPC, existing RLS policy, frontend flow, or real-user authorization state, WP-A1 scope is violated and work stops for redesign.
