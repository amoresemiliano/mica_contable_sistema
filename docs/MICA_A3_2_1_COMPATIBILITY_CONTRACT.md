# MICA Authorization Compatibility Contract (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: FROZEN & UPDATED (GLOBAL VS TENANT STATE SEPARATION & MULTI-ORG RESOLUTION)  
> **Baseline Commit**: `fab6e49633228d10b86e0439db879f32c57e6b97`  

---

## 1. Purpose & Scope

This document establishes the bidirectional compatibility contract between the client application, existing database layers, and the capability-based authorization subsystem introduced in Migration 022.

---

## 2. API & Signature Compatibility

| Function Signature | Supported Call Signatures | Pre-M022 Return / Errors | Post-M022 Return / Errors | Compatibility Status |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | `(target_id, new_role)`<br>`(target_id, new_role, p_org_id)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND`<br>`AMBIGUOUS_ORGANIZATION_CONTEXT` | **BACKWARD_COMPATIBLE_EXTENDED** |
| `public.set_user_active` | `(target_id, new_active)`<br>`(target_id, new_active, p_org_id)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND`<br>`AMBIGUOUS_ORGANIZATION_CONTEXT` | **BACKWARD_COMPATIBLE_EXTENDED** (Tenant Membership Only) |
| `public.set_global_user_active` | `(target_id, new_active)` | N/A (New explicit platform RPC) | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND` | **NEW_EXPLICIT_PLATFORM_RPC** (Global Account Only) |
| `public.switch_superadmin_org_context` | `(p_org_id)` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | **EXACT_MATCH** |

---

## 3. Behavioral Invariants & Semantic Guarantees

1. **Explicit Separation of Global vs Tenant State**:
   - `set_user_active` operates strictly on `eco_organization_members.is_active` for a specific tenant organization. It **never** mutates `eco_user_profiles.is_active`.
   - `set_global_user_active` operates strictly on `eco_user_profiles.is_active` at platform level. It **never** touches `eco_organization_members`.
2. **Active Context Independence**:
   - Platform global operations (`set_global_user_active`) do not depend on, read, or require `active_org_id()`. An active context cannot grant or deny global platform capability.
   - For tenant operations, `active_org_id()` acts solely as an operation selector when `p_org_id` is omitted, never as an authorization bypass.
3. **Legacy `profile.role` Classification**:
   - `eco_user_profiles.role` is classified as `COMPATIBILITY_ONLY / DISPLAY_ONLY`.
   - Backend authorization readers remaining: **ZERO**.
   - Changes to role in Org A update `eco_organization_members.role_template_id` for Org A only; Org B canonical template is completely isolated.
4. **Append-Only Audit Guarantee**:
   - Database trigger `enforce_append_only_audit` on `eco_audit_events` remains active and untouched.
