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

*See `sql/design/015_agenda_obligaciones_draft.sql` for the full schema proposal.*

## 4. Lifecycle / State Model
An `eco_obligation_instances` record can have the following statuses:
*   `PENDING`: Generated or manually created, but not yet paid.
*   `PAID`: Fully paid.
*   `OVERDUE`: **(Computed)** We should NOT store `OVERDUE` directly as a static state, because time continuously moves. Instead, status is `PENDING` but the `due_date < CURRENT_DATE`. A database view or API logic should dynamically compute `OVERDUE`.
*   `CANCELLED`: Invalidated or reversed (e.g., if a source record was fundamentally wrong and the obligation shouldn't exist).

## 5. Idempotency & Source Integration
Re-importing source data (like salaries) must not create duplicate instances.

**Identity Rule**: Idempotency is guaranteed by a UNIQUE constraint on `(organization_id, org_obligation_id, period)`.
*   **A. Sueldos**: When the Salary Parser processes a file, the backend will check for existing instances for that period and `org_obligation`. If the underlying raw `eco_financial_movements` changes the amount, the `eco_obligation_instances` amount should be updated, and an audit event generated. Raw source records remain immutable.
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
Given MICA is accounting software, we must track changes. A new table `eco_obligation_audit` (or extending existing `eco_audit_events`) will record:
*   `INSTANCE_GENERATED`
*   `AMOUNT_UPDATED` (e.g., due to source recalculation)
*   `PAYMENT_ADDED`
*   `PAYMENT_REVERSED`
*   `DUE_DATE_CHANGED`
Raw source data in `eco_financial_movements` remains strictly immutable.

## 9. User Journeys & UX
*   **Dashboard**: Shows summary cards for "Pendientes", "Vencidas", "Próximas a vencer".
*   **Filtros**: By Client, Period, Obligation Type.
*   **Acciones en Lista**: "Marcar Pagado" (opens modal for date, amount, evidence), "Ver Detalle", "Añadir Manual".
*   **Sueldos UX**: The `salaryParser.js` currently extracts "sindicatoAporte". This should be mapped in the backend. Instead of hardcoding `if sindicato === X`, the parser sends the raw extracted mapping, and the backend resolves it against `eco_org_obligations` configured for `source_type = 'PAYROLL'`.

## 10. Risks & Unresolved Decisions
See `AGENDA_OBLIGACIONES_IMPLEMENTATION_PLAN.md` for open product decisions and risks.
