# MICA Authorization Compatibility Contract (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: FROZEN & UPDATED (MULTI-ORG TARGET RESOLUTION)  
> **Baseline Commit**: `e2f9c5baed420d0d1b1e98f2fc260f36505dc6f8`  

---

## 1. Purpose & Scope

This document establishes the bidirectional compatibility contract between the client application, existing database layers, and the capability-based authorization subsystem introduced in Migration 022.

---

## 2. API & Signature Compatibility

All RPC function signatures support both legacy 2-argument invocation and explicit 3-argument multi-org scoping:

| Function Signature | Supported Call Signatures | Pre-M022 Return / Errors | Post-M022 Return / Errors | Compatibility Status |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | `(target_id, new_role)`<br>`(target_id, new_role, p_org_id)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND`<br>`AMBIGUOUS_ORGANIZATION_CONTEXT` | **BACKWARD_COMPATIBLE_EXTENDED** |
| `public.set_user_active` | `(target_id, new_active)`<br>`(target_id, new_active, p_org_id)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND`<br>`AMBIGUOUS_ORGANIZATION_CONTEXT` | **BACKWARD_COMPATIBLE_EXTENDED** |
| `public.switch_superadmin_org_context` | `(p_org_id)` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | **EXACT_MATCH** |

---

## 3. Behavioral Invariants & Semantic Guarantees

1. **Non-Authoritative `profile.organization_id`**:
   - `eco_user_profiles.organization_id` is never used to determine authorization, target permissions, or organization boundaries.
   - Target user membership is resolved exclusively through canonical records in `public.eco_organization_members`.
2. **Tenant Membership State Isolation**:
   - Deactivating a user via tenant `set_user_active` sets `eco_organization_members.is_active = FALSE` for that tenant only.
   - The user's memberships in other organizations and global user profile remain active.
3. **Multi-Org Ambiguity Protection**:
   - If an administrative caller manages multiple organizations where a target user belongs, and neither active context nor explicit `p_org_id` is supplied, the operation fails closed with `AMBIGUOUS_ORGANIZATION_CONTEXT`.
4. **Append-Only Audit Guarantee**:
   - Database trigger `enforce_append_only_audit` on `eco_audit_events` remains active and untouched.
