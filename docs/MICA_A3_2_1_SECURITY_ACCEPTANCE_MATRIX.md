# MICA Authorization Security Acceptance Matrix (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Target Migration**: M022 (`sql/022_identity_and_org_admin.sql`)  
> **Status**: FROZEN / READY FOR TEST HARNESS  

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
| **SEC-08** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Member Profile | `change_user_role(target, 'REVIEWER')` | **ALLOW** | Status 200, Role updated, Audit written |
| **SEC-09** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Self Profile | `change_user_role(self, 'USER')` | **DENY** | Exception `SELF_ROLE_CHANGE_NOT_ALLOWED` |
| **SEC-10** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` Member Profile | `change_user_role(target_sur, 'REVIEWER')` | **DENY** | Exception `FORBIDDEN` |
| **SEC-11** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` / Member Profile | `set_user_active(target, false)` | **ALLOW** | Status 200, Member deactivated, Audit written |
| **SEC-12** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Self Profile | `set_user_active(self, false)` | **DENY** | Exception `SELF_DEACTIVATION_NOT_ALLOWED` |
| **SEC-13** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` Member Profile | `set_user_active(target_sur, false)` | **DENY** | Exception `FORBIDDEN` |
| **SEC-14** | `emilianodirosa1@gmail.com` | `TENANT_ADMIN` | Platform / Global | `switch_superadmin_org_context(DEMO SUR)` | **DENY** | Exception `Unauthorized: Only SUPERADMIN can switch organization context` |
| **SEC-15** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | Platform / Global | `switch_superadmin_org_context(DEMO NORTE)` | **ALLOW** | Updates context to `DEMO NORTE`, Audit written |
| **SEC-16** | `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | `DEMO NORTE` / Member Profile | `change_user_role(target, 'USER')` | **DENY** | Exception `FORBIDDEN` (No tenant membership) |
| **SEC-17** | `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `DEMO NORTE` / Member Profile | `change_user_role(target_norte, 'USER')` | **DENY** | Exception `FORBIDDEN` (Accounting superadmin has operational capabilities, not member permission management) |
| **SEC-18** | `Synthetic UPLOADER` | `UPLOADER` (Base Deny) | `DEMO NORTE` / Member Profile | `change_user_role(...)` | **DENY** | Exception `FORBIDDEN` |
| **SEC-19** | `Synthetic UPLOADER + ALLOW` | `UPLOADER` + `ALLOW ORG_MEMBER_PERMISSION_MANAGE` | `DEMO NORTE` / Member Profile | `change_user_role(...)` | **ALLOW** | Status 200 via explicit capability override |
| **SEC-20** | `Synthetic ADMIN + DENY` | `TENANT_ADMIN` + `DENY ORG_MEMBER_MANAGE` | `DEMO NORTE` / Member Profile | `set_user_active(...)` | **DENY** | Exception `FORBIDDEN` via explicit DENY override |
| **SEC-21** | Inactive Profile | `TENANT_ADMIN` (`is_active = FALSE`) | `DEMO NORTE` | Any RPC / Query | **DENY** | Exception `UNAUTHORIZED` / 0 rows (Fail-Closed) |
