# Agenda / Obligaciones - Architecture Design

## 1. Product Context
The "Agenda / Obligaciones" domain transforms MICA from a pure conciliation tool into an operational accounting platform capable of tracking what clients owe, how much, when it is due, and its payment status. This covers payroll contributions (SEC, FAECYS), taxes (Monotributo, IVA, IIBB), and configurable/manual obligations.

## 2. Domain Model
The domain relies on a separation between **Global Definitions**, **Organization Assignments**, and **Instances**.

*   **Jurisdiction (`eco_jurisdictions`)**: Represents taxing or union authorities (AFIP, ARBA, SEC). Global catalog.
*   **Obligation Definition (`eco_obligation_definitions`)**: Represents generic types of obligations (IVA, SEC, INACAP). Global catalog.
*   **Organization Obligation (`eco_org_obligations`)**: Represents a specific client's configuration for an obligation (e.g., this client pays SEC monthly, linked to a specific jurisdiction).
*   **Obligation Instance (`eco_obligation_instances`)**: The concrete payable amount for a specific period (e.g., SEC for October 2023 is $50,000, due Nov 10).
*   **Obligation Payment (`eco_obligation_payments`)**: Tracks settlements against an instance.

This model is highly extensible. New taxes or union rules can be added to the global catalog without schema changes, and clients simply "subscribe" to them via `eco_org_obligations`.

## 3. Database Model & Multitenancy
Multitenancy is strictly enforced. All transactional tables (`eco_org_obligations`, `eco_obligation_instances`, `eco_obligation_payments`) have an `organization_id` column.
Following the MICA standard, `organization_id` should **never** be trusted from the frontend. Security Definer RPCs will enforce constraints, and RLS will use `private.org_id()` to ensure tenants only access their data.

**History Protection**: All foreign keys to critical organizational entities and parents use `ON DELETE RESTRICT` (instead of `CASCADE`) to prevent accidental destruction of audit history and instances.

*See `sql/design/015_agenda_obligaciones_draft.sql` for the full schema proposal.*

## 4. Lifecycle / State Model
An `eco_obligation_instances` record can have the following stored statuses:
*   `PENDING`: Generated or manually created, but not yet paid (or partially paid).
*   `PAID`: Fully paid.
*   `CANCELLED`: Invalidated or reversed (e.g., if a source record was fundamentally wrong and the obligation shouldn't exist).

**Computed Overdue State**:
*   `OVERDUE`: We do **NOT** store `OVERDUE` directly as a static state, because time continuously moves. Instead, status is `PENDING` but the `due_date < CURRENT_DATE`. A database view or API logic dynamically computes `OVERDUE`.

## 5. Idempotency & Source Integration
Re-importing source data (like salaries) must not create duplicate instances.

**Extensible Identity Key**: Idempotency is guaranteed by a UNIQUE constraint on `(organization_id, identity_key)`.
The `identity_key` is a deterministic hash of the context: e.g., `hash(org_obligation_id, period, jurisdiction/context)`. This is extensible for complex cases compared to a flat tuple.

**Source Amendment Rules & No Silent Override**:
*   **A. Sueldos**: When the Salary Parser processes a file, the backend checks for existing instances via `identity_key`. If the underlying raw `eco_financial_movements` changes the amount:
    *   The `eco_obligation_instances` amount is updated.
    *   An audit event is ALWAYS generated.
    *   No silent override is permitted. Any user-made manual adjustment to an automatically sourced obligation requires an explicit audit log and cannot simply overwrite the source. If the source is wrong, the source should be fixed (immutable raw records are appended/corrected).
    *   **Amount Below Paid Rule**: If the recalculated obligation amount is less than the total active payments already recorded, the system will NOT silently normalize history. It will preserve all payments and the audit trail, flag the obligation as requiring review (`requires_review = TRUE`), and will NOT auto-refund or delete payments. The UI/API will expose this state to show the inconsistency.
*   **B. Taxes**: Future calculations will work similarly, upserting the instance based on the deterministic key.
*   **C. Manual**: Follows the same key. Manual overrides to calculated amounts must be clearly audited.

## 6. Permissions / Roles
*   `ADMIN`: Can configure global catalogs and organization-specific overrides. Can manual override amounts.
*   `UPLOADER`: Triggers generation of obligations (e.g., uploading Sueldos), but cannot mark as Paid or Cancelled.
*   `REVIEWER`: Can verify instances, attach payment evidence, and mark as `PAID`. Can change due dates.
*   `USER`: Read-only access to view Dashboards (Pending/Overdue).

## 7. Reporting Model
The schema supports reporting via SQL views or RPCs over `eco_obligation_instances` joined with `eco_org_obligations` and `eco_obligation_payments`.
Key queries:
*   `get_pending_by_client()`: `status = PENDING AND due_date >= TODAY`
*   `get_overdue_by_client()`: `status = PENDING AND due_date < TODAY`
*   `get_paid_by_period()`: JOIN with payments to sum amounts.

## 8. Auditability
Given MICA is accounting software, we must track changes. We reuse the existing `public.eco_audit_events` table to record:
*   `INSTANCE_GENERATED`
*   `AMOUNT_UPDATED` (e.g., due to source recalculation)
*   `PAYMENT_ADDED`
*   `PAYMENT_REVERSED`
*   `DUE_DATE_CHANGED`
Raw source data in `eco_financial_movements` remains strictly immutable.

## 9. User Journeys & UX
*   **Dashboard**: Shows summary cards for "Pendientes", "Vencidas", "Próximas a vencer".
*   **Filtros**: By Client, Period, Obligation Type.
*   **Acciones en Lista**: "Marcar Pagado" (opens modal for date, amount, evidence), "Ver Detalle", "Añadir Manual". Payment evidence is stored as a stable path (`supporting_evidence_path`), not a signed URL. Signed URLs are generated at read-time only.
*   **Sueldos UX**: The `salaryParser.js` currently extracts "sindicatoAporte". This should be mapped in the backend. Instead of hardcoding `if sindicato === X`, the parser sends the raw extracted mapping, and the backend resolves it against `eco_org_obligations` configured for `source_type = 'PAYROLL'`.

## 10. Risks & Unresolved Decisions
See `AGENDA_OBLIGACIONES_IMPLEMENTATION_PLAN.md` for open product decisions and risks.
