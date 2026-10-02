# MICA — WP-A1 Authorization Helpers Design v1.1

Status: **REVISED DESIGN — PENDING FINAL REVIEW**

## private.current_profile_id()

Returns the active `eco_user_profiles.id` associated with `auth.uid()`.

Fail closed:
- unauthenticated -> NULL;
- missing profile -> NULL;
- inactive profile -> NULL.

## private.active_org_id()

Reads `eco_user_active_context.organization_id`.

This is context only.
It is never proof of membership or authority.

## private.can_platform(capability_code TEXT)

Required evaluation:

1. current profile exists and is active;
2. `eco_user_platform_role` exists and `is_active = TRUE`;
3. referenced role template:
   - scope = PLATFORM;
   - is_active = TRUE;
4. referenced capability:
   - scope = PLATFORM;
   - is_active = TRUE;
5. base grant is read from `eco_role_template_capabilities`;
6. user-specific override is read from `eco_user_platform_capability_overrides`;
7. explicit DENY wins;
8. explicit ALLOW can grant a capability absent from the base template;
9. otherwise return base grant;
10. any invalid/missing state fails closed.

## private.can_org(org_id UUID, capability_code TEXT)

Required evaluation:

1. current profile exists and is active;
2. target organization exists and is active according to current organization lifecycle semantics;
3. an ACTIVE `eco_organization_members` row exists for current profile + target org;
4. requested capability exists:
   - scope = ORGANIZATION;
   - is_active = TRUE;
5. membership role template, when present:
   - scope = ORGANIZATION;
   - is_active = TRUE;
6. base organization grant may come from:
   - membership role template via `eco_role_template_capabilities`;
   - active PLATFORM role via `eco_platform_role_org_capabilities`;
7. platform-role org grants are valid ONLY because active membership already passed step 3;
8. membership-specific override is applied last;
9. explicit DENY wins;
10. explicit ALLOW can grant a capability omitted by all base grants;
11. otherwise return whether any base grant exists;
12. any invalid/missing state fails closed.

## ACCOUNTING_SUPERADMIN semantics

`ACCOUNTING_SUPERADMIN`:
- is a PLATFORM role;
- does NOT have ACCESS_ANY_ORG;
- receives selected ORGANIZATION capabilities through `eco_platform_role_org_capabilities`;
- those grants activate only for organizations where the user has an active membership.

Therefore:

`platform accounting authority + active membership = accounting capability in that organization`

This is the explicit bridge missing in v1.0.

## PLATFORM_SUPERADMIN semantics during WP-A1

`PLATFORM_SUPERADMIN` may have `ACCESS_ANY_ORG = YES` as a platform capability definition.

However WP-A1 intentionally does NOT make `can_org()` bypass membership.

The future elevated support/access path must be:
- explicit;
- audited;
- designed in a later WP.

Until that path exists, the new `can_org()` remains fail-closed for a PLATFORM_SUPERADMIN who has no membership.

This does not change current application behavior because WP-A1 does not replace existing authorization calls.

## Split-brain prevention

WP-A1 does not migrate real users.

No trigger or dual-write mechanism synchronizes:
- legacy profile role/org;
- new platform role;
- new membership role template.

The new model remains non-authoritative until the dedicated migration WP.
