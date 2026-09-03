# Documentación de Recuperación de Movimientos de Crédito BBVA (One-Off)

## Contexto Histórico
Durante la ejecución del reintento de importación BBVA (Migración 016):
- **BBVA 05-2026 (Mayo)**: 84 filas fuente → 71 débitos persistidos, 13 créditos no persistidos.
- **BBVA 06-2026 (Junio)**: 78 filas fuente → 59 débitos persistidos, 19 créditos no persistidos.
- **Causa Raíz**: En los archivos de extracto BBVA, las filas de crédito dejan la columna 7 (`Importe`) vacía `""` y colocan el monto positivo de crédito en la columna 6 (`Cod. Mov.`). El parser original rechazaba estas filas con `Importe vacío o no numérico`.

## Jerarquía de Importaciones y Linaje
La recuperación crea registros dedicados en `eco_source_imports`:
- **Original Import** → `retry_of_import_id` → **Retry Attempt #1** → `retry_of_import_id` → **Recovery Attempt**
- **Mayo Recovery Attempt**:
  - `retry_of_import_id`: `8a6ca4d8-a31f-4a1b-b145-85336958c843`
  - Contadores: `total_rows = 9`, `accepted_rows = 9`, `invalid_rows = 0`, `duplicate_rows = 0`
- **Junio Recovery Attempt**:
  - `retry_of_import_id`: `b6024ac0-afb9-4da1-a984-4fcbfbd7eedc`
  - Contadores: `total_rows = 15`, `accepted_rows = 15`, `invalid_rows = 0`, `duplicate_rows = 0`

## Invariantes Preservados
1. **Inmutabilidad Histórica**: Los registros de importación inicial y reintento (`881859f6...`, `a1ea483b...`, `8a6ca4d8...`, `b6024ac0...`), contadores históricos (`71/13` y `59/19`), archivos fuente (`eco_source_files`) e incidentes (`eco_import_issues`) permanecen **100% inalterados**.
2. **Sin Cambios de Esquema ni Migración**: No se modifica la Migración 016 ni 014, ni se crea una Migración 017.
3. **Control Tenant-Scoped**: Precondiciones, consultas y deduplicación están estrictamente filtradas por `organization_id = v_org_id`.
4. **Idempotencia Garantizada**: Cada fila a recuperar verifica su `identity_key` en `eco_financial_movements` para el tenant. Ejecuciones subsecuentes insertan 0 filas sin alterar los totales.

## Estrategia de Recuperación
El script `scripts/recovery/2026-09-bbva-credit-recovery.sql`:
1. Verifica precondiciones tenant-scoped estrictas:
   - Movimientos activos de Mayo = 71
   - Movimientos activos de Junio = 59
   - Movimientos activos totales BBVA = 130
2. Inserta los registros de importación de recuperación en `eco_source_imports`.
3. Inserta exactamente las **24 identidades válidas de crédito**:
   - 9 de Mayo (completando 80 de 84 filas fuente; 4 son filas inválidas del extracto/metadata).
   - 15 de Junio (completando 74 de 78 filas fuente; 4 son filas inválidas del extracto/metadata).
4. Verifica aserciones post-recuperación:
   - Total Mayo = 80
   - Total Junio = 74
   - Total BBVA = 154
5. Realiza `COMMIT` únicamente si todas las aserciones se cumplen al 100%.

## Manual de Ejecución
Ejecutar únicamente bajo supervisión humana en la base de datos DEV tras aprobación del Human Gate.
