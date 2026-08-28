-- tests/db/013_2_harden_financial.sql

-- Test suite for 013.2 Financial RPC Hardening
-- To be executed manually or via pgTAP

BEGIN;

-- 1. Aconpy Periodo: 06/2026 -> 2026-06
-- Insert a row with periodo '06/2026' and verify the financial movement is saved with '2026-06' and identity contains '2026-06'.

-- 2. Aconpy Periodo: 2026-06 -> 2026-06
-- Insert a row with periodo '2026-06' and verify canonicalization leaves it intact.

-- 3. Aconpy Periodo: 13/2026 invalid
-- Insert a row with periodo '13/2026' and verify it's flagged as INVALID and issue PARSE_ERROR is created.

-- 4. Aconpy Anticipo
-- Insert a row with 'anticipoSueldo': '100' and 'anticipos': '50', verify '100' is used in the fingerprint.
-- Insert a row with 'anticipos': '50' only, verify fallback '50' is used.

-- 5. Aconpy Numeric Deterministic
-- Insert a row with 'remunerativo': '1000.5' and verify the fingerprint matches exactly the sha256 of TO_CHAR '    1000.50' structure.

-- 6. BBVA Fechas estrictas: 31/02/2026 invalid
-- Insert a row with fecha '31/02/2026' and verify it falls into INVALID.

-- 7. BBVA Fechas estrictas: 2026-02-31 invalid
-- Insert a row with fecha '2026-02-31' and verify it falls into INVALID.

-- 8. BBVA Signals order invariant
-- Insert a row with signals ["IVA", "IIBB"] and another with ["IIBB", "IVA"]. Both should compute the same fingerprint.

-- 9. BBVA Signals duplicate invariant
-- Insert a row with signals ["IVA", "IVA"] and verify the fingerprint matches ["IVA"].

-- 10. BBVA Referencia + Saldo nulo
-- Insert a row with referencia '123' and saldo '' and verify it's ACCEPTED.

-- 11. BBVA Sin referencia + Saldo válido
-- Insert a row with referencia '' and saldo '1000' and verify identity contains 'NO_REFERENCE' and '1000'.

-- 12. BBVA Sin referencia + Saldo vacío
-- Insert a row with referencia '' and saldo '' and verify it falls into INVALID.

-- 13. Security: Filename vacío
-- Execute RPC with original_name '' and verify it throws 'Invalid original_name'.

-- 14. Security: File >20MB
-- Execute RPC with size_bytes 25000000 and verify it throws 'Invalid size_bytes (must be between 1 and 20MB)'.

-- 15. Security: MIME no permitido
-- Execute RPC with mime_type 'image/png' and verify it throws 'Invalid mime_type'.

-- 16. Security: storage_path de otro org/import
-- Execute RPC with storage_path 'wrong-org/import_id/file.csv' and verify it throws 'Invalid storage path'.

ROLLBACK;
