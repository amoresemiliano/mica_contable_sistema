# WP-AUTH-RESET-1: Manual Verification Pack (DEV)

**Target Environment:** DEV Database (Supabase SQL Editor / Terminal / Browser)  
**Status:** `READY_FOR_MANUAL_CHECK`  
**Purpose:** Independent manual verification queries and commands for the human owner to verify the canonical authorization cutover.

---

## CHECK 1 — CANONICAL ROLE TEMPLATES

Execute in **Supabase SQL Editor**:

```sql
SELECT code, scope, is_active, is_system
FROM public.eco_role_templates
WHERE code IN (
  'PLATFORM_SUPERADMIN',
  'ACCOUNTING_SUPERADMIN',
  'TENANT_ADMIN',
  'ACCOUNTANT',
  'UPLOADER',
  'REVIEWER',
  'READ_ONLY',
  'EXTERNAL_AUDITOR'
)
ORDER BY scope, code;
```

### Expected Output:
| code | scope | is_active | is_system |
| :--- | :--- | :--- | :--- |
| ACCOUNTING_SUPERADMIN | PLATFORM | true | true |
| PLATFORM_SUPERADMIN | PLATFORM | true | true |
| ACCOUNTANT | ORGANIZATION | true | true |
| EXTERNAL_AUDITOR | ORGANIZATION | true | true |
| READ_ONLY | ORGANIZATION | true | true |
| REVIEWER | ORGANIZATION | true | true |
| TENANT_ADMIN | ORGANIZATION | true | true |
| UPLOADER | ORGANIZATION | true | true |

*(Exactly 8 canonical role templates, active = true, normalized scope).*

---

## CHECK 2 — PLATFORM ROLES

Execute in **Supabase SQL Editor**:

```sql
SELECT u.email, rt.code AS platform_role, upr.is_active
FROM auth.users u
JOIN public.eco_user_profiles p ON p.auth_user_id = u.id
LEFT JOIN public.eco_user_platform_role upr ON upr.user_profile_id = p.id AND upr.is_active = TRUE
LEFT JOIN public.eco_role_templates rt ON rt.id = upr.role_template_id
WHERE u.email IN (
  'vegendigital@gmail.com',
  'drcmarianela@gmail.com',
  'emilianodirosa1@gmail.com',
  'edravi77@gmail.com',
  'calleelcalvario16@gmail.com'
)
ORDER BY u.email;
```

### Expected Output:
| email | platform_role | is_active |
| :--- | :--- | :--- |
| calleelcalvario16@gmail.com | *NULL* | *NULL* |
| drcmarianela@gmail.com | ACCOUNTING_SUPERADMIN | true |
| edravi77@gmail.com | *NULL* | *NULL* |
| emilianodirosa1@gmail.com | *NULL* | *NULL* |
| vegendigital@gmail.com | PLATFORM_SUPERADMIN | true |

---

## CHECK 3 — MEMBERSHIP MATRIX

Execute in **Supabase SQL Editor**:

```sql
SELECT u.email, o.name AS organization, rt.code AS role_template, m.is_active
FROM public.eco_organization_members m
JOIN public.eco_user_profiles p ON p.id = m.user_profile_id
JOIN auth.users u ON u.id = p.auth_user_id
JOIN public.eco_organizations o ON o.id = m.organization_id
LEFT JOIN public.eco_role_templates rt ON rt.id = m.role_template_id
WHERE u.email IN (
  'vegendigital@gmail.com',
  'drcmarianela@gmail.com',
  'emilianodirosa1@gmail.com',
  'edravi77@gmail.com',
  'calleelcalvario16@gmail.com'
)
ORDER BY u.email, o.name;
```

### Expected Output:
| email | organization | role_template | is_active |
| :--- | :--- | :--- | :--- |
| calleelcalvario16@gmail.com | DEMO OESTE | TENANT_ADMIN | true |
| drcmarianela@gmail.com | DEMO NORTE | *NULL* | true |
| drcmarianela@gmail.com | DEMO OESTE | *NULL* | true |
| drcmarianela@gmail.com | DEMO SUR | *NULL* | true |
| edravi77@gmail.com | DEMO SUR | TENANT_ADMIN | true |
| emilianodirosa1@gmail.com | DEMO NORTE | TENANT_ADMIN | true |

*(VEGEN has 0 rows; Marianela has 3 rows; Emiliano has 1; Edravi has 1; Calle has 1).*

---

## CHECK 4 — MICA LEGACY LEAK

Execute in **Supabase SQL Editor**:

```sql
SELECT u.email, o.name, m.is_active
FROM public.eco_organization_members m
JOIN public.eco_organizations o ON o.id = m.organization_id
JOIN public.eco_user_profiles p ON p.id = m.user_profile_id
JOIN auth.users u ON u.id = p.auth_user_id
WHERE o.id = '59436df3-9f15-4f5e-b17e-37c55482521c'::UUID
  AND u.email IN (
    'vegendigital@gmail.com',
    'drcmarianela@gmail.com',
    'emilianodirosa1@gmail.com',
    'edravi77@gmail.com',
    'calleelcalvario16@gmail.com'
  );
```

### Expected Output:
```
(0 rows)
```

---

## CHECK 5 — ACTIVE CONTEXT

Execute in **Supabase SQL Editor**:

```sql
SELECT u.email, o.name AS active_org
FROM public.eco_user_profiles p
JOIN auth.users u ON u.id = p.auth_user_id
LEFT JOIN public.eco_user_active_context ac ON ac.user_profile_id = p.id
LEFT JOIN public.eco_organizations o ON o.id = ac.organization_id
WHERE u.email IN (
  'vegendigital@gmail.com',
  'drcmarianela@gmail.com',
  'emilianodirosa1@gmail.com',
  'edravi77@gmail.com',
  'calleelcalvario16@gmail.com'
)
ORDER BY u.email;
```

### Expected Output:
| email | active_org |
| :--- | :--- |
| calleelcalvario16@gmail.com | DEMO OESTE |
| drcmarianela@gmail.com | DEMO NORTE |
| edravi77@gmail.com | DEMO SUR |
| emilianodirosa1@gmail.com | DEMO NORTE |
| vegendigital@gmail.com | *NULL* |

---

## CHECK 6 — ORGANIZATION RLS POLICIES

Execute in **Supabase SQL Editor**:

```sql
SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'eco_organizations';
```

### Expected Output:
| policyname | cmd | qual |
| :--- | :--- | :--- |
| Organizations viewable by own users | SELECT | (id IN ( SELECT private.authorized_orgs_for_capability('ORG_VIEW'::text) AS organization_id)) |

*(Exactly 1 SELECT policy. No competing permissive policies like "Organizations member view" or "org_members_read_orgs").*

---

## CHECK 7 — AUTHORIZED ORGS PER PERSONA

Run each transaction block individually in **Supabase SQL Editor**:

### 7.1 EMILIANO (Tenant Admin NORTE)
```sql
BEGIN;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'emilianodirosa1@gmail.com'), true);
SET LOCAL ROLE authenticated;

SELECT id, name FROM public.eco_organizations ORDER BY name;

ROLLBACK;
```
**Expected:** Exactly 1 row: `DEMO NORTE`.

---

### 7.2 EDRAVI (Tenant Admin SUR)
```sql
BEGIN;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'edravi77@gmail.com'), true);
SET LOCAL ROLE authenticated;

SELECT id, name FROM public.eco_organizations ORDER BY name;

ROLLBACK;
```
**Expected:** Exactly 1 row: `DEMO SUR`.

---

### 7.3 CALLE (Tenant Admin OESTE)
```sql
BEGIN;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'calleelcalvario16@gmail.com'), true);
SET LOCAL ROLE authenticated;

SELECT id, name FROM public.eco_organizations ORDER BY name;

ROLLBACK;
```
**Expected:** Exactly 1 row: `DEMO OESTE`.

---

### 7.4 MARIANELA (Accounting Superadmin)
```sql
BEGIN;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'drcmarianela@gmail.com'), true);
SET LOCAL ROLE authenticated;

SELECT id, name FROM public.eco_organizations ORDER BY name;

ROLLBACK;
```
**Expected:** Exactly 3 rows: `DEMO NORTE`, `DEMO OESTE`, `DEMO SUR`.

---

### 7.5 VEGEN (Platform Superadmin)
```sql
BEGIN;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'vegendigital@gmail.com'), true);
SET LOCAL ROLE authenticated;

SELECT id, name FROM public.eco_organizations ORDER BY name;

ROLLBACK;
```
**Expected:** 0 rows *(Platform Superadmin has no tenant memberships; platform role alone does not grant tenant access)*.

---

## CHECK 8 — PRIVATE.ORG_ID SOURCE

Execute in **Supabase SQL Editor**:

```sql
SELECT pg_get_functiondef('private.org_id()'::regprocedure);
```

### Expected Output:
Body must contain `SELECT private.active_org_id();` and must **NOT** query `eco_user_profiles.organization_id`.

---

## CHECK 9 — CAPABILITY BRIDGE

Execute in **Supabase SQL Editor**:

```sql
SELECT rt.code AS role_template, c.code AS capability_code
FROM public.eco_platform_role_org_capabilities proc
JOIN public.eco_role_templates rt ON rt.id = proc.role_template_id
JOIN public.eco_capabilities c ON c.id = proc.capability_id
WHERE rt.code = 'ACCOUNTING_SUPERADMIN' AND c.code = 'ORG_VIEW';
```

### Expected Output:
| role_template | capability_code |
| :--- | :--- |
| ACCOUNTING_SUPERADMIN | ORG_VIEW |

---

## CHECK 10 — CROSS-TENANT NEGATIVE

Execute in **Supabase SQL Editor**:

```sql
BEGIN;
-- Impersonate Emiliano
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM auth.users WHERE email = 'emilianodirosa1@gmail.com'), true);
SET LOCAL ROLE authenticated;

-- Emiliano attempts to read DEMO SUR directly
SELECT count(*) AS should_be_zero
FROM public.eco_organizations
WHERE id = 'c7af5a5c-1aac-4add-9873-8073044bf979'::UUID;

ROLLBACK;
```

### Expected Output:
| should_be_zero |
| :--- |
| 0 |

---

## CHECK 11 — STATIC REPOSITORY CHECK

Execute in **local terminal**:

```bash
git rev-parse HEAD
git status -s
npm test
```

### Verification Checks:
1. `git rev-parse HEAD` matches final commit SHA.
2. `git status -s` shows no unstaged repository modifications.
3. `npm test` runs 22 test suites with 270 passed tests.

---

## CHECK 12 — APPLICATION CHECK

Manual UI verification via browser:
1. **Login as Emiliano (`emilianodirosa1@gmail.com`)**:
   - Organization selector lists only `DEMO NORTE`.
   - Data grids show accounting records for DEMO NORTE.
2. **Login as Marianela (`drcmarianela@gmail.com`)**:
   - Organization selector lists `DEMO NORTE`, `DEMO SUR`, and `DEMO OESTE`.
   - Context switch between organizations succeeds and loads the respective tenant data without expanding scope beyond the 3 authorized organizations.
