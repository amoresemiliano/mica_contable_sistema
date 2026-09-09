# MICA Authorization Security Acceptance Matrix (WP-A3.2.0)

> **Work Package**: WP-A3.2.0 — Authorization Primitives Safety & Performance Validation  
> **Status**: VERIFIED & COMPLETE  
> **Scope**: Real user baseline truth table, negative isolation assertions, and synthetic override fixtures.

---

## 1. Real User Baseline Truth Table

| User Account | Role / Context | Target Organization | Tested Capability | Expected Outcome | Actual Result | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | N/A (Platform) | `PLATFORM_MANAGE` | `TRUE` | `TRUE` | **PASS** |
| `vegendigital@gmail.com` | `PLATFORM_SUPERADMIN` | `DEMO NORTE` | `ORG_VIEW` | `FALSE` (No membership) | `FALSE` | **PASS** |
| `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | N/A (Platform) | `REPORT_COMPARE_SCOPED_ORGS` | `TRUE` | `TRUE` | **PASS** |
| `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `DEMO NORTE` | `RECORD_VIEW` | `TRUE` (Via bridge + membership) | `TRUE` | **PASS** |
| `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `DEMO SUR` | `RECORD_VIEW` | `TRUE` (Via bridge + membership) | `TRUE` | **PASS** |
| `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `DEMO OESTE` | `RECORD_VIEW` | `TRUE` (Via bridge + membership) | `TRUE` | **PASS** |
| `drcmarianela@gmail.com` | `ACCOUNTING_SUPERADMIN` | `LEGACY MICA` | `RECORD_VIEW` | `FALSE` (No membership) | `FALSE` | **PASS** |
| `emilianodirosa1@gmail.com`| `TENANT_ADMIN` | `DEMO NORTE` | `ORG_MEMBER_INVITE` | `TRUE` | `TRUE` | **PASS** |
| `emilianodirosa1@gmail.com`| `TENANT_ADMIN` | `DEMO SUR` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |
| `emilianodirosa1@gmail.com`| `TENANT_ADMIN` | `DEMO OESTE` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |
| `edravi77@gmail.com` | `TENANT_ADMIN` | `DEMO SUR` | `ORG_MEMBER_INVITE` | `TRUE` | `TRUE` | **PASS** |
| `edravi77@gmail.com` | `TENANT_ADMIN` | `DEMO NORTE` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |
| `edravi77@gmail.com` | `TENANT_ADMIN` | `DEMO OESTE` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |
| `calleelcalvario16@gmail.com`| `TENANT_ADMIN` | `DEMO OESTE` | `ORG_MEMBER_INVITE` | `TRUE` | `TRUE` | **PASS** |
| `calleelcalvario16@gmail.com`| `TENANT_ADMIN` | `DEMO NORTE` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |
| `calleelcalvario16@gmail.com`| `TENANT_ADMIN` | `DEMO SUR` | `ORG_MEMBER_INVITE` | `FALSE` (Tenant isolation) | `FALSE` | **PASS** |

---

## 2. Synthetic Override Fixture Matrix

| Test ID | Test Scenario | Baseline State | Override Applied | Target Org | Capability | Expected | Actual |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **SYNTH-01** | `BASE_DENY + OVERRIDE_ALLOW` | `UPLOADER` role (no `ORG_MEMBER_INVITE`) | `ALLOW` override | `DEMO NORTE` | `ORG_MEMBER_INVITE` | `TRUE` | `TRUE` |
| **SYNTH-02** | `BASE_ALLOW + OVERRIDE_DENY` | `UPLOADER` role (has `IMPORT_CREATE`) | `DENY` override | `DEMO NORTE` | `IMPORT_CREATE` | `FALSE` | `FALSE` |
| **SYNTH-03** | `CROSS_ORG_OVERRIDE_ISOLATION` | Member in Org NORTE (DENY) and Org SUR (None) | Org NORTE `DENY` | `DEMO SUR` | `IMPORT_CREATE` | `TRUE` | `TRUE` |
| **SYNTH-04** | `INACTIVE_MEMBERSHIP` | `TENANT_ADMIN` with `is_active = FALSE` | None | `DEMO OESTE` | `RECORD_VIEW` | `FALSE` | `FALSE` |
| **SYNTH-05** | `INACTIVE_PROFILE` | Profile with `is_active = FALSE` | None | `DEMO NORTE` | `ORG_VIEW` | `FALSE` | `FALSE` |
| **SYNTH-06** | `INACTIVE_CAPABILITY` | Valid membership & template | Capability `is_active = FALSE` | `DEMO NORTE` | Inactive Cap | `FALSE` | `FALSE` |
| **SYNTH-07** | `ACCOUNTING_WITHOUT_MEMBERSHIP` | `ACCOUNTING_SUPERADMIN` platform role | None | `LEGACY MICA` | `RECORD_VIEW` | `FALSE` | `FALSE` |
| **SYNTH-08** | `PLATFORM_WITHOUT_MEMBERSHIP` | `PLATFORM_SUPERADMIN` platform role | None | `DEMO NORTE` | `ORG_VIEW` | `FALSE` | `FALSE` |

---

## 3. Invariant Governance Summary

1. `ACTIVE CONTEXT != AUTHORIZATION`: Verified. Changing active UI context row in `eco_user_active_context` does NOT alter `private.can_org` evaluation.
2. `DENY OVERRIDES WIN`: Verified. An explicit `DENY` override unconditionally revokes base template and platform bridge capabilities.
3. `OVERRIDE TENANT ISOLATION`: Verified. Overrides in `eco_membership_capability_overrides` bind strictly to `membership_id` and never spill over to other organizations for the same user.
