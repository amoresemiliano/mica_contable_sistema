# MICA Authorization Compatibility Contract (WP-A3.2.1)

> **Work Package**: WP-A3.2.1 — Identity, Profiles & Organization Administration  
> **Status**: FROZEN  
> **Baseline Commit**: `e2f9c5baed420d0d1b1e98f2fc260f36505dc6f8`  

---

## 1. Purpose & Scope

This document establishes the bidirectional compatibility contract between the client application, existing database layers, and the capability-based authorization subsystem introduced in Migration 022.

---

## 2. API & Signature Compatibility

All RPC function signatures, parameter names, error codes, and return types are strictly preserved:

| Function | Parameter Types | Pre-M022 Return / Errors | Post-M022 Return / Errors | Compatibility Status |
| :--- | :--- | :--- | :--- | :--- |
| `public.change_user_role` | `(target_user_id UUID, new_role TEXT)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_ROLE_CHANGE_NOT_ALLOWED`<br>`INVALID_ROLE`<br>`TARGET_NOT_FOUND` | **EXACT_MATCH** |
| `public.set_user_active` | `(target_user_id UUID, new_active BOOLEAN)` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND` | `VOID`<br>`UNAUTHORIZED`<br>`FORBIDDEN`<br>`SELF_DEACTIVATION_NOT_ALLOWED`<br>`TARGET_NOT_FOUND` | **EXACT_MATCH** |
| `public.switch_superadmin_org_context` | `(p_org_id UUID)` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | `VOID`<br>`Unauthorized: Only SUPERADMIN can switch organization context`<br>`Invalid organization ID`<br>`User profile not found or inactive` | **EXACT_MATCH** |

---

## 3. Behavioral Invariants & Semantic Equivalence

1. **Self-Profile Reading**:
   - An active user can always query their own profile record (`auth_user_id = auth.uid() AND is_active = TRUE`).
   - Inactive user profiles fail closed and cannot read their own or any other records.
2. **Tenant Admin Profile Reading**:
   - A tenant administrator with `ORG_MEMBER_VIEW` in organization `X` can read profiles of all active members in organization `X`.
   - The administrator cannot read profiles belonging exclusively to other tenant organizations (`Y`, `Z`).
3. **Multi-Org Isolation**:
   - An accounting superadmin with memberships in multiple organizations (e.g., Marianela in NORTE, SUR, OESTE) can administer members only within those scoped organizations.
   - A platform superadmin without tenant memberships (e.g., VEGEN) cannot modify tenant member roles or toggle tenant member status via tenant RPCs (`can_org` fails closed).
4. **Append-Only Audit Guarantee**:
   - The database trigger `enforce_append_only_audit` on `eco_audit_events` remains active and unmodified.
   - All role changes, status updates, and context switches generate structured audit events atomically within the executing transaction.
5. **No Frontend Dual-Write**:
   - The client application is not required to pass extra capability tokens.
   - Legacy `eco_user_profiles.organization_id` is maintained in sync during context switches to preserve frontend session hydration until WP-A3.3.
