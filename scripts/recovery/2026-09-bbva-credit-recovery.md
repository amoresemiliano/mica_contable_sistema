# Documentación de Recuperación de Movimientos de Crédito BBVA (One-Off)

## Contexto Histórico
Durante la ejecución del reintento de importación BBVA (Migración 016):
- **BBVA 05-2026 (Mayo)**: 84 filas fuente → 71 débitos persistidos, 13 créditos no persistidos.
- **BBVA 06-2026 (Junio)**: 78 filas fuente → 59 débitos persistidos, 19 créditos no persistidos.
- **Causa Raíz**: En los archivos de extracto BBVA, las filas de crédito dejan la columna 7 (`Importe`) vacía `""` y colocan el monto positivo de crédito en la columna 6 (`Cod. Mov.`). El parser original rechazaba estas filas con `Importe vacío o no numérico`.

## Invariantes Preservados
1. **Inmutabilidad Histórica**: Los registros de importación inicial y reintento (`881859f6...`, `a1ea483b...`, `8a6ca4d8...`, `b6024ac0...`), contadores históricos (`71/13` y `59/19`), archivos fuente (`eco_source_files`) e incidentes (`eco_import_issues`) permanecen **100% inalterados**.
2. **Sin Cambios de Esquema ni Migración**: No se modifica la Migración 016 ni 014, ni se crea una Migración 017.
3. **Control por Organización**: La recuperación se ejecuta dentro del tenant activo mediante `private.org_id()`.
4. **Idempotencia Garantizada**: Cada fila a recuperar verifica su `identity_key` en `eco_financial_movements`. Ejecuciones subsecuentes insertan 0 filas sin alterar los totales.

## Estrategia de Recuperación
El script `scripts/recovery/2026-09-bbva-credit-recovery.sql`:
1. Verifica precondiciones estrictas:
   - Movimientos activos de Mayo = 71
   - Movimientos activos de Junio = 59
   - Movimientos activos totales BBVA = 130
2. Inserta exactamente las **24 identidades válidas de crédito**:
   - 9 de Mayo (completando 80 de 84 filas fuente; 4 son filas inválidas del extracto/metadata).
   - 15 de Junio (completando 74 de 78 filas fuente; 4 son filas inválidas del extracto/metadata).
3. Verifica aserciones post-recuperación:
   - Total Mayo = 80
   - Total Junio = 74
   - Total BBVA = 154
4. Realiza `COMMIT` únicamente si todas las aserciones se cumplen al 100%.

## Manual de Ejecución
Ejecutar únicamente bajo supervisión humana en la base de datos DEV tras aprobación del Human Gate.
