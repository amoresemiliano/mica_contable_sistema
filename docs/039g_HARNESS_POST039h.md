# Harness 039g posterior a 039h

Sólo cambia el harness independiente 039g y su soporte de tests. No se modifica ninguna migración ni los harness 039h/039i/039j/039k. No se ejecutó SQL local ni LIVE.

El fixture operativo usa ADMINISTRACION_OPERATIVA_MICA, conserva scopes explícitos y rechaza memberships artificiales. La asignación de ACCOUNTING_SUPERADMIN se prueba exclusivamente como error 42501. Se preservan creación/edición, importadores, guards root y precedencia DENY; se agregan comprobaciones de falta de capability y de DENY con ACCESS_ANY_ORG del root. Todo queda dentro de BEGIN/ROLLBACK.

Auditoría de harness:

- 039h/039i/039j/039k: el preset histórico aparece como estado previo, snapshot o acción negativa; la operación actual utiliza el preset operativo. No se regeneran ni cambian estos archivos.
- 039h_membership_roundtrip: reproduce deliberadamente el estado anterior y prueba UP/DOWN; no es un harness para ejecutar sobre el estado final instalado.
- 039c: referencia ACCOUNTING_SUPERADMIN en un intento de invitación incompatible que debe fallar.
- 030_assignment_activation y 039b_operational_access_and_ux: conservan expectativas históricas de ACCOUNTING_SUPERADMIN activo/asignable. No son compatibles con el contrato post-039h. Se reportan como históricos; no se modifican dentro de este ajuste limitado a 039g.

La fuente previa de 039g queda congelada en tests/fixtures/039g_pre039h_harness.sql para el generador 039i. El archivo de fixtures no es un harness actual ejecutable. Esta separación evita regenerar 039i–039k a partir de un contrato posterior.

Validación local: suite Jest completa (incluye contratos estáticos 039g/h/i/j/k), node --check, comprobación de generadores sin escritura y git diff --check. Ejecutar el SQL actualizado en PostgreSQL sigue siendo una validación manual pendiente; los tests JS no prueban ejecución SQL.
