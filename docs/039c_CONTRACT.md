# 039c — Contrato preparado, no aplicado

| Importador | Requisitos | Habilitado |
|---|---|---|
| percepcion | RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + PERCEPTION_IMPORT | Sí |
| banco | RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + BANK_IMPORT | Sí |
| sueldo | RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + PAYROLL_IMPORT | Sí |
| recibido | RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + FISCAL_DOCUMENT_IMPORT | Sí |
| emitido | RECORD_VIEW + IMPORT_VIEW + IMPORT_CREATE + FISCAL_DOCUMENT_IMPORT | Sí |

| Capability | Runtime preparado | Presets |
|---|---|---|
| MANUAL_MOVEMENT_VIEW | ACTIVE | Root técnico MICA, Administración general MICA, Administrador de organización, Contador / operador contable |
| MANUAL_MOVEMENT_CREATE | ACTIVE | Root técnico MICA, Administración general MICA, Administrador de organización, Contador / operador contable |
| MANUAL_MOVEMENT_EDIT | ACTIVE | Root técnico MICA, Administración general MICA, Administrador de organización, Contador / operador contable |
| MANUAL_MOVEMENT_SOFT_DELETE | ACTIVE | Root técnico MICA, Administración general MICA, Administrador de organización, Contador / operador contable |
| FISCAL_DOCUMENT_IMPORT | ACTIVE | Root técnico MICA, Administración general MICA, Administrador de organización, Contador / operador contable, Operador de importaciones |
