# Agenda / Obligaciones - Implementation Plan

## 1. Implementation Phases (Work Packages)

We recommend breaking the implementation into 4 sequential Work Packages to ensure stability and continuous delivery.

### WP1 — Core Obligation Engine
*   **Objective**: Deploy the database schema, RLS, and basic CRUD RPCs for Obligations.
*   **DB Changes**: Apply `015_agenda_obligaciones.sql` (based on the draft).
*   **Frontend**: Admin UI to manage `eco_obligation_definitions` and assign them to clients (`eco_org_obligations`).
*   **DoD**: A user can manually define an obligation for a client, create a manual instance for a period, and it saves correctly to the DB.

### WP2 — Payroll Integration (Sueldos)
*   **Objective**: Automatically generate Obligation Instances when Sueldos are processed.
*   **DB Changes**: Update Sueldos import pipeline to call a new RPC `generate_payroll_obligations`.
*   **Frontend**: Sueldos parser updates to capture configurable unions, sending a generalized payload to the backend.
*   **DoD**: Uploading an Acompy Excel automatically creates SEC/FAECYS/etc. instances in the Agenda. Re-uploading updates the amounts safely without duplicates.

### WP3 — Agenda UI & Payments
*   **Objective**: Build the accountant-facing Agenda Dashboard and Payment lifecycle.
*   **DB Changes**: RPCs for `mark_obligation_paid` and `reverse_payment`.
*   **Frontend**: Dashboard (Pendientes, Vencidas, Pagadas). Modals for attaching payment evidence.
*   **DoD**: Accountant can view a list of what's due, filter by client/period, and mark items as paid (with or without partial payments based on Product Decision).

### WP4 — Tax Integrations & Reporting
*   **Objective**: Integrate tax calculations and build advanced reporting/exports.
*   **DB Changes**: Read-only views for reporting. RPCs for exporting to Excel.
*   **Frontend**: Tax calculation pipelines (IVA, IIBB) feed into the Agenda. Excel Export buttons.
*   **DoD**: Calculated taxes appear in Agenda automatically. The user can export a full compliance report.

---

## 2. Server Contract (RPC / API Design)

The backend will expose strictly typed, `SECURITY DEFINER` RPCs to handle operations, enforcing tenant isolation via `private.org_id()`.

### `get_agenda_dashboard`
*   **Input**: `p_period TEXT` (optional), `p_status TEXT` (optional)
*   **Output**: JSON array of instances joined with definitions and total paid.

### `create_manual_obligation_instance`
*   **Input**: `p_org_obligation_id UUID`, `p_period TEXT`, `p_amount NUMERIC`, `p_due_date DATE`
*   **Output**: The new `instance_id UUID`.
*   **Logic**: Validates org, ensures no duplicate period exists.

### `mark_obligation_paid`
*   **Input**: `p_instance_id UUID`, `p_amount NUMERIC`, `p_payment_date DATE`, `p_method TEXT`, `p_evidence_url TEXT` (optional)
*   **Output**: Success boolean.
*   **Logic**: Creates a record in `eco_obligation_payments`. If total payments >= instance amount, updates instance status to `PAID`. Triggers audit.

### `reverse_payment`
*   **Input**: `p_payment_id UUID`, `p_reason TEXT`
*   **Output**: Success boolean.
*   **Logic**: Deletes/marks inactive the payment. Recalculates instance status (reverts to `PENDING` if needed). Triggers audit.

### `generate_payroll_obligations` (Internal/System RPC)
*   **Input**: `p_financial_movement_id UUID` (the raw salary record)
*   **Logic**: Reads the mapped `eco_org_obligations` for `PAYROLL`. Upserts instances for the specific period.

---

## 3. Product Decisions Required (Open Questions)

To proceed with WP3 (Agenda UI & Payments), the Product Owner / Accountant must decide on the following genuine business logic questions:

1.  **Partial Payments**
    *   *Question*: Should the system support registering partial payments (e.g., paying 50% of an IVA obligation now, 50% later), or is it strictly Full Payment / Unpaid?
    *   *A.* Yes, support partial payments natively (Complex UI).
    *   *B.* No, an obligation is either PAID or PENDING entirely.
    *   *Recommended Default*: **B** for v1 to keep the UI and state machine simple, with structural DB support for **A** later.

2.  **Payment Evidence**
    *   *Question*: Is uploading a receipt (comprobante de pago) mandatory when marking an obligation as PAID, or optional?
    *   *A.* Mandatory.
    *   *B.* Optional.
    *   *Recommended Default*: **B** (Optional). Forcing uploads creates friction in bulk data entry.

3.  **Manual Amount Overrides on Automatic Sources**
    *   *Question*: If the system calculates $10,000 for SEC based on Payroll, can the accountant manually override the Agenda to say "Actually it is $9,500"?
    *   *A.* Yes, allow manual override (creates audit trail).
    *   *B.* No, the source (Payroll) must be fixed to fix the Agenda.
    *   *Recommended Default*: **B**. Modifying downstream numbers breaks the single source of truth. If the number is wrong, the raw Sueldos import/mapping needs fixing.

4.  **Due Date Intelligence**
    *   *Question*: For v1, how should Due Dates be set?
    *   *A.* Accountant enters them manually for each instance / configured as a fixed day of month per client.
    *   *B.* System attempts to calculate them based on AFIP calendar and CUIT termination.
    *   *Recommended Default*: **A**. Building the full Argentine tax calendar engine is too complex for WP1. Start with manual/simple recurrence.
