# MICA Manual DEV Validation Plan: Identity & Org Admin (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Target Environment**: DEV / Supabase Staging  
> **Prerequisite**: Migration `sql/022_identity_and_org_admin.sql` applied in DEV database.  

---

## 1. Validation Personas

| Persona | Email | Assigned Role Template | Organizations Assigned |
| :--- | :--- | :--- | :--- |
| **VEGEN** (Platform Admin) | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` (Platform) | None (Platform global) |
| **Marianela** (Accounting Superadmin) | `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` (Platform bridge) | `DEMO NORTE`, `DEMO SUR`, `DEMO OESTE` |
| **Emiliano** (Tenant Admin NORTE) | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` (Organization) | `DEMO NORTE` |
| **Edravi** (Tenant Admin SUR) | `edravi77@gmail.com` | `TENANT_ADMIN` (Organization) | `DEMO SUR` |
| **Calle** (Tenant Admin OESTE) | `calleelcalvario16@gmail.com` | `TENANT_ADMIN` (Organization) | `DEMO OESTE` |

---

## 2. Test Execution Protocol

### Scenario 1: Emiliano (Tenant Admin — DEMO NORTE)
1. **Login**: Authenticate as `emilianodirosa1@gmail.com`.
2. **Profile & Org Visibility**:
   - Verify active organization shows `DEMO NORTE`.
   - Querying `eco_organizations` returns ONLY `DEMO NORTE`.
   - Querying `eco_user_profiles` returns Emiliano's profile and active members of `DEMO NORTE`. It must NOT list members belonging exclusively to `DEMO SUR` or `DEMO OESTE`.
3. **Audit Visibility**:
   - Audit event viewer / query on `eco_audit_events` returns events matching `organization_id = DEMO NORTE`.
4. **Member Role Administration**:
   - Execute `change_user_role` on a member of `DEMO NORTE`: Expected Success.
   - Execute `change_user_role` on self: Expected Error `SELF_ROLE_CHANGE_NOT_ALLOWED`.
   - Execute `change_user_role` on an ID from `DEMO SUR`: Expected Error `FORBIDDEN` or `TARGET_NOT_FOUND`.
5. **Context Switch Attempt**:
   - Attempt executing `switch_superadmin_org_context`: Expected Error `Unauthorized: Only SUPERADMIN can switch organization context`.

---

### Scenario 2: VEGEN (Platform Superadmin)
1. **Login**: Authenticate as `vegendigital@gmail.com`.
2. **Context Switching**:
   - Execute `switch_superadmin_org_context(DEMO NORTE)`: Expected Success.
   - Execute `switch_superadmin_org_context(DEMO SUR)`: Expected Success.
   - Execute `switch_superadmin_org_context(NULL)` (Global mode): Expected Success.
3. **Tenant Administration Isolation**:
   - Attempt executing tenant `change_user_role` or `set_user_active` directly: Expected Error `FORBIDDEN` (No tenant membership; Platform Superadmin does not bypass tenant capability checks).

---

### Scenario 3: Marianela (Accounting Superadmin)
1. **Login**: Authenticate as `drcmarianela@gmail.com`.
2. **Organization Visibility**:
   - Querying `eco_organizations` returns `DEMO NORTE`, `DEMO SUR`, and `DEMO OESTE` (scoped bridge).
   - Legacy `MICA` organization (where Marianela has no membership) is NOT returned.
3. **Audit Visibility**:
   - Audit viewer returns events from `DEMO NORTE`, `DEMO SUR`, and `DEMO OESTE`.
4. **Member Role Administration**:
   - Attempt executing `change_user_role`: Expected Error `FORBIDDEN` (`ACCOUNTING_SUPERADMIN` template grants operational accounting capabilities, not tenant user permission management).
