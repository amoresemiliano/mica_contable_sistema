# MICA — WP-A1 Jules Findings Disposition v1.1

Status: **CHANGES INCORPORATED — PENDING JULES RE-REVIEW**

## Verdict received
`APPROVE_WITH_CHANGES`

## Blocker 1 — Active context FK lifecycle
**Accepted.**

Changed:
`eco_user_active_context.organization_id`
from:
`ON DELETE RESTRICT`
to:
`ON DELETE SET NULL`

Reason:
Active context is UX/work state, not ownership. Deleting an organization must not be blocked by stale/inactive user context rows.

## Blocker 2 — ACCOUNTING_SUPERADMIN bridge
**Accepted and resolved explicitly.**

New bridge:
`eco_platform_role_org_capabilities`

Purpose:
A PLATFORM-scope role may define organization-scoped capability grants, but those grants are effective only when the user has an ACTIVE membership in the target organization.

This preserves:
- platform identity of ACCOUNTING_SUPERADMIN;
- membership-defined tenant scope;
- capability-based per-org authorization;
- no ACCESS_ANY_ORG for ACCOUNTING_SUPERADMIN.

`private.can_org()` therefore evaluates:
1. active user profile;
2. active target organization;
3. active membership in target organization;
4. membership role-template org grants;
5. platform-role org-capability bridge grants;
6. membership override ALLOW/DENY;
7. explicit DENY wins.

## High risk 1 — active platform role
**Accepted.**

`private.can_platform()` and platform-role org bridge evaluation require:
- `eco_user_platform_role.is_active = TRUE`;
- role template `is_active = TRUE`;
- capability `is_active = TRUE`.

## High risk 2 — PLATFORM_SUPERADMIN elevated path
**Clarified.**

WP-A1 does NOT implement elevated tenant access.

`ACCESS_ANY_ORG = YES` is seeded as a platform entitlement for future use, but normal `private.can_org()` does not bypass membership for PLATFORM_SUPERADMIN in WP-A1.

Therefore WP-A1 remains fail-closed and behavior-preserving.

The explicit, audited elevated-access path belongs to a later WP before any new authorization helper replaces legacy tenant access.

## Medium risk 1 — membership uniqueness
**Already satisfied in current schema.**

Verified current constraint:
`UNIQUE (organization_id, user_profile_id)`

WP-A1 postcheck must assert this invariant remains present.

## Medium risk 2 — split-brain / legacy drift
**Accepted and constrained.**

WP-A1 does NOT migrate real users and does NOT make the new authorization model authoritative.

Therefore:
- no dual-write trigger is introduced;
- no legacy role update is mirrored into new authorization tables;
- new real-user authorization rows remain absent until the dedicated user-migration WP;
- existing app continues using legacy authorization unchanged.

This intentionally avoids creating two simultaneously authoritative sources.

## Missing invariant — empty new auth state
**Added.**

Tests must prove:
- a real current user with no new platform role/membership template mapping fails closed in new helpers;
- legacy application authorization continues unchanged because no existing RPC/RLS uses the new helpers in WP-A1.

## Missing invariant — ALLOW override
**Added.**

Explicit ALLOW override grants an organization capability even if the membership role template omits it, provided:
- membership is active;
- capability is active and organization-scoped;
- no explicit DENY exists for the same membership/capability.

Since one override row exists per membership/capability, ALLOW and DENY cannot coexist for the same pair.
