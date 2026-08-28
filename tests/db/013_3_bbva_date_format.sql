-- tests/db/013_3_bbva_date_format.sql

-- Test suite for 013.3 Financial RPC BBVA Date format (DD-MM-YYYY)
-- To be executed manually or via pgTAP

BEGIN;

-- 1. BBVA Fechas estrictas: 30-06-2026 -> 2026-06-30
-- Insert a row with fecha '30-06-2026' and verify it's ACCEPTED and saved as '2026-06-30'::DATE.

-- 2. BBVA Fechas estrictas: 29-06-2026 -> 2026-06-29
-- Insert a row with fecha '29-06-2026' and verify it's ACCEPTED.

-- 3. BBVA Fechas estrictas: 29-02-2026 -> invalid
-- Insert a row with fecha '29-02-2026' and verify it falls into INVALID (PARSE_ERROR).

-- 4. BBVA Fechas estrictas: 29-02-2028 -> válido (leap year)
-- Insert a row with fecha '29-02-2028' and verify it's ACCEPTED.

-- 5. BBVA Fechas estrictas: 31-04-2026 -> invalid
-- Insert a row with fecha '31-04-2026' and verify it falls into INVALID (PARSE_ERROR).

-- 6. BBVA Fechas estrictas: Backward compatibility
-- Insert a row with fecha '30/06/2026' and another with '2026-06-30' and verify both are ACCEPTED.

ROLLBACK;
