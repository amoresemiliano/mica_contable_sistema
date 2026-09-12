# MICA Authorization Security Acceptance Matrix (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Target Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  
> **Status**: FROZEN & UPDATED (GLOBAL VS TENANT STATE SEPARATION & MULTI-ORG RESOLUTION)  

---

## 1. Security Verification Matrix

| Test ID | Persona / Subject | Role Template / Overrides | Target Org / Resource | Capability / Action | Expected Result | Target Error / Assertion |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Self Profile | SELECT from `eco_user_profiles` | **ALLOW** | Returns 1 row (own profile) |
| **SEC-02** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Member Profile | SELECT from `eco_user_profiles` | **ALLOW** | Returns NORTE member profile via `ORG_MEMBER_VIEW` |
| **SEC-03** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` / Member Profile | SELECT from `eco_user_profiles` | **DENY** | 0 rows returned (Cross-tenant isolation) |
| **SEC-04** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Org row | SELECT from `eco_organizations` | **ALLOW** | Returns `DEMO NORTE` via `ORG_VIEW` |
| **SEC-05** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` / Org row | SELECT from `eco_organizations` | **DENY** | 0 rows returned |
| **SEC-06** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Audit Log | SELECT from `eco_audit_events` | **ALLOW** | Returns NORTE audit records via `AUDIT_VIEW_ORG` |
| **SEC-07** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` / Audit Log | SELECT from `eco_audit_events` | **DENY** | 0 rows returned |
| **SEC-08** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Multi-Org Member (`profile.org_id = SUR`) | `change_user_role(target, 'REVIEWER')` | **ALLOW** | Resolves NORTE membership; updates NORTE template to `REVIEWER`; SUR template untouched |
| **SEC-09** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Multi-Org Member (`profile.org_id = SUR`) | `set_user_active(target, false)` | **ALLOW** | Deactivates NORTE membership only; SUR membership and global profile remain active |
| **SEC-10** | `Superadmin in NORTE & SUR` | `TENANT_ADMIN` (Both) | Multi-Org Member (No active context / No `p_org_id`) | `change_user_role(target, 'ACCOUNTANT')` | **DENY** | Fails closed with `AMBIGUOUS_ORGANIZATION_CONTEXT` |
| **SEC-11** | `Superadmin in NORTE & SUR` | `TENANT_ADMIN` (Both) | Multi-Org Member + `p_org_id = DEMO NORTE` | `change_user_role(target, 'ACCOUNTANT', NORTE)` | **ALLOW** | Scopes to NORTE; updates NORTE template to `ACCOUNTANT` |
| **SEC-12** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Self Profile | `change_user_role(self, 'USER')` | **DENY** | Exception `SELF_ROLE_CHANGE_NOT_ALLOWED` |
| **SEC-13** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` Member Profile (Only SUR) | `change_user_role(target_sur, 'REVIEWER')` | **DENY** | Exception `TARGET_NOT_FOUND` / `FORBIDDEN` |
| **SEC-14** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Self Profile | `set_user_active(self, false)` | **DENY** | Exception `SELF_DEACTIVATION_NOT_ALLOWED` |
| **SEC-15** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` Member Profile (Only SUR) | `set_user_active(target_sur, false)` | **DENY** | Exception `TARGET_NOT_FOUND` / `FORBIDDEN` |
| **SEC-16** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Platform / Global | `switch_superadmin_org_context(DEMO SUR)` | **DENY** | Exception `Unauthorized: Only SUPERADMIN can switch organization context` |
| **SEC-17** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | Platform / Global | `switch_superadmin_org_context(DEMO NORTE)` | **ALLOW** | Updates context to `DEMO NORTE`, Audit written |
| **SEC-18** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` (Active context NORTE) | Global Target Profile | `set_global_user_active(target, false)` | **ALLOW** | Deactivates `eco_user_profiles.is_active` globally regardless of active context |
| **SEC-19** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` (Active context NULL) | Global Target Profile | `set_global_user_active(target, false)` | **ALLOW** | Identical authorization and execution result |
| **SEC-20** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Global Target Profile | `set_global_user_active(target, false)` | **DENY** | Exception `FORBIDDEN` |
| **SEC-21** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | `DEMO NORTE` / Member Profile | `change_user_role(target, 'USER')` | **DENY** | Exception `TARGET_NOT_FOUND` / `FORBIDDEN` (No tenant membership) |
| **SEC-22** | `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `DEMO NORTE` / Member Profile | `change_user_role(target_norte, 'USER')` | **DENY** | Exception `FORBIDDEN` (Operational accounting authority, not member permission management) |
| **SEC-23** | Inactive Profile | `TENANT_ADMIN` (`is_active = FALSE`) | `DEMO NORTE` | Any RPC / Query | **DENY** | Exception `UNAUTHORIZED` / 0 rows (Fail-Closed) |
| **SEC-24** | Any User | Authenticated | `eco_audit_events` | `DELETE` / `UPDATE` | **DENY** | Exception via `enforce_append_only_audit` trigger |
