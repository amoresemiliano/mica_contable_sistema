# 039k — Hardening consolidado preparado

MICA `ourzapkjykzlwsjunzmd`. Cero SQL ejecutado; sin commit, push ni deploy. 039j y migraciones anteriores permanecen intactas.

## Call-sites revisados

Se buscaron los seis nombres de tabla y llamadas `.from(...)` en frontend, services y tests JavaScript. No se encontraron SELECT, INSERT, UPDATE ni DELETE directos sobre esas seis tablas en código de aplicación. Las menciones de tests son contratos SQL estáticos; no son escrituras frontend. No fue necesario migrar escrituras ni ampliar autoridad.

`src/js/core/services/administrationService.js` utiliza exclusivamente `mica_admin_read`, `mica_admin_apply` y `mica_invitation` para administración. `persistenceService.js` obtiene permisos/contextos por RPC, incluido `get_my_effective_capabilities`. Esta auditoría es de código local, no una captura de tráfico LIVE.

| Tabla | SELECT directo frontend | INSERT/UPDATE/DELETE frontend | Ruta administrativa |
|---|---|---|---|
| eco_role_templates | No encontrado | No encontrado | RPC |
| eco_role_template_capabilities | No encontrado | No encontrado | RPC |
| eco_platform_role_org_capabilities | No encontrado | No encontrado | RPC |
| eco_user_platform_role | No encontrado | No encontrado | RPC |
| eco_user_platform_capability_overrides | No encontrado | No encontrado | RPC |
| eco_membership_capability_overrides | No encontrado | No encontrado | RPC |

Se conserva SELECT en las dos primeras conforme al contrato solicitado y sólo si el preflight confirma su policy de lectura existente. No se encontró dependencia que justifique SELECT directo en las otras cuatro.

## Matriz final esperada, pendiente de validación LIVE

| Tabla | anon | authenticated | service_role | postgres |
|---|---|---|---|---|
| eco_role_templates | Ninguno | SELECT sujeto a RLS | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |
| eco_role_template_capabilities | Ninguno | SELECT sujeto a RLS | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |
| eco_platform_role_org_capabilities | Ninguno | Ninguno | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |
| eco_user_platform_role | Ninguno | Ninguno | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |
| eco_user_platform_capability_overrides | Ninguno | Ninguno | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |
| eco_membership_capability_overrides | Ninguno | Ninguno | Sin cambios, ocho privilegios | Sin cambios, ocho privilegios |

Los ocho privilegios incluyen MAINTAIN. No se comparan ACL textuales ni orden de grants. La conservación de grants de otros roles se verifica por conjuntos mediante `aclexplode`. Las ACL por columna y grant options no revisadas de anon/authenticated abortan. No cambia ninguna fila funcional, policy, RLS, función, guard, preset, scope o membership.

## Preflight pendiente y validación preparada

El pedido no incluye las definiciones exactas de las policies por tabla y el repositorio no permite certificar su estado LIVE. `sql/039k_policy_manifest.json` deja las seis entradas en null deliberadamente: null significa **pendiente de revisión**, nunca ausencia aceptada de policies. El UP aborta antes de revocar permisos hasta completar ese manifiesto. Una tabla sin policies debe registrarse expresamente como `[]` tras revisión.

1. Ejecutar manualmente `sql/039k_preflight_readonly.sql` en el proyecto canónico. Revisar y copiar sus arrays de policies, por tabla, al manifiesto; confirmar owner/RLS, autoridad y guards y las asignaciones root/Marianela.
2. Regenerar offline con `node scripts/generate039kAcl.mjs`, revisar y volver a ejecutar tests. Sólo entonces considerar `sql/039k_harden_structural_acl.sql` para aplicación.
3. Después del UP ejecutar manualmente `tests/db/039k_harden_structural_acl.sql`. Exige 42501 para escritura directa de ambos roles en cada tabla, incluido DELETE de grants root; comprueba SELECT permitido/prohibido, creación y edición de preset por RPC root, y ejecuta la lógica de harness 039j/039i/039h/039g en savepoints. Termina con ROLLBACK.
4. El mismo harness ejercita DOWN en un savepoint. Para rollback real, aplicar el DOWN 039k antes de 039j: valida primero las seis tablas instaladas y luego restaura los ocho privilegios anteriores de anon/authenticated.

La confirmación de que Marianela conserva operación de empresas/usuarios tenant/importaciones y root su administración RPC es una comprobación preparada en el harness, no un resultado LIVE afirmado. Los tests estáticos comprueban alcance y preservación histórica; no sustituyen ejecutar PostgreSQL.

## Deuda separada

`eco_organization_members` y `eco_user_profiles` no se alteran en 039k. Sus policies históricas, rutas de login/profile/self-service y dependencias SQL deben revisarse por separado antes de modificar ACL. Tampoco se afirma que toda tabla histórica de autorización quede cerrada: esta fase cubre sólo las seis enumeradas; eco_capabilities conserva el hardening previo de 039j.
