# Project State

## Phase 5.6.2/6+ - Consolidation & Reorganization (In Progress)
- **Status:** HUMAN_GATE_REQUIRED (Migration 014 drafted)
- **BBVA Pipeline:** Fixed `saldo` mapping (78 staged, 74 valid, 4 invalid) locally. Tests pass.
- **Frontend Refactor:** Pending 014 application. Includes new UX navigation, Soft-Delete, Categories/Activities assignment.
- **Database Migrations:**
  - `013.1`, `013.2`, `013.3` applied successfully (BBVA format fix).
  - `014` ready for human review.

## Boundaries & Out of Scope
- **AGENDA / OBLIGACIONES**: Payment Agenda, paid/unpaid monthly obligations, Monotributo, Ganancias, Bienes Personales, annual/monthly tax schedules, configurable union payment obligations, payment reminders, and missing-payment reports are strictly OUT OF SCOPE for Migration 014. These belong to a separate future domain.

## Environment
- Node.js tests: 164/164 PASS.
- DB: Supabase Staging.
