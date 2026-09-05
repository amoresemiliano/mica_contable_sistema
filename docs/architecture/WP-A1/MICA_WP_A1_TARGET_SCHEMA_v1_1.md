# MICA — WP-A1 Target Schema v1.1

Status: **REVISED DESIGN — PENDING FINAL REVIEW**

WP-A1 is additive. Existing auth, RLS, RPC and frontend behavior must remain unchanged.

## 1. eco_capabilities

```sql
CREATE TABLE public.eco_capabilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('PLATFORM', 'ORGANIZATION')),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 2. eco_role_templates

```sql
CREATE TABLE public.eco_role_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    scope TEXT NOT NULL CHECK (scope IN ('PLATFORM', 'ORGANIZATION')),
    name TEXT NOT NULL,
    description TEXT,
    is_system BOOLEAN NOT NULL DEFAULT TRUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 3. eco_role_template_capabilities

Maps a role template to capabilities of the SAME scope.

```sql
CREATE TABLE public.eco_role_template_capabilities (
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role_template_id, capability_id)
);
```

Scope compatibility must be validated by migration/postcheck and helper logic.

## 4. eco_platform_role_org_capabilities

Explicit bridge for platform roles that grant organization capabilities only inside organizations where the user has an active membership.

Primary use:
`ACCOUNTING_SUPERADMIN`.

```sql
CREATE TABLE public.eco_platform_role_org_capabilities (
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (role_template_id, capability_id)
);
```

Contract:
- `role_template_id` must reference PLATFORM scope;
- `capability_id` must reference ORGANIZATION scope;
- grants are ineffective without active membership in target organization.

## 5. eco_membership_capability_overrides

```sql
CREATE TABLE public.eco_membership_capability_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL REFERENCES public.eco_organization_members(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    effect TEXT NOT NULL CHECK (effect IN ('ALLOW', 'DENY')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (membership_id, capability_id)
);
```

Only ORGANIZATION-scope capabilities are valid here.

## 6. eco_user_platform_role

```sql
CREATE TABLE public.eco_user_platform_role (
    user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    role_template_id UUID NOT NULL REFERENCES public.eco_role_templates(id),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Only PLATFORM-scope role templates are valid here.

## 7. eco_user_platform_capability_overrides

```sql
CREATE TABLE public.eco_user_platform_capability_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_profile_id UUID NOT NULL REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    capability_id UUID NOT NULL REFERENCES public.eco_capabilities(id) ON DELETE CASCADE,
    effect TEXT NOT NULL CHECK (effect IN ('ALLOW', 'DENY')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_profile_id, capability_id)
);
```

Only PLATFORM-scope capabilities are valid here.

## 8. eco_user_active_context

```sql
CREATE TABLE public.eco_user_active_context (
    user_profile_id UUID PRIMARY KEY REFERENCES public.eco_user_profiles(id) ON DELETE CASCADE,
    organization_id UUID NULL REFERENCES public.eco_organizations(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`organization_id = NULL` means Global context.

Active context never grants authorization.

## 9. Evolve eco_organization_members

```sql
ALTER TABLE public.eco_organization_members
ADD COLUMN role_template_id UUID NULL
REFERENCES public.eco_role_templates(id);
```

Existing `role` remains.

Current verified invariant that must be preserved:
`UNIQUE (organization_id, user_profile_id)`.

## 10. Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_eco_org_members_user_active
ON public.eco_organization_members(user_profile_id, is_active);

CREATE INDEX IF NOT EXISTS idx_eco_org_members_org_active
ON public.eco_organization_members(organization_id, is_active);

CREATE INDEX IF NOT EXISTS idx_membership_cap_overrides_membership
ON public.eco_membership_capability_overrides(membership_id);

CREATE INDEX IF NOT EXISTS idx_platform_cap_overrides_user
ON public.eco_user_platform_capability_overrides(user_profile_id);
```

## 11. WP-A1 compatibility rule

WP-A1 must not:
- drop or repurpose `eco_user_profiles.organization_id`;
- drop or repurpose `eco_user_profiles.role`;
- remove `eco_organization_members.role`;
- migrate real users;
- introduce dual-write synchronization;
- alter current RLS;
- alter current RPC bodies;
- change frontend behavior.
