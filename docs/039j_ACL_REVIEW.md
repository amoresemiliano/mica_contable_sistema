# 039j — ACL de capabilities

Preparado y verificado estáticamente. No se ejecutó SQL.

El precheck LIVE aportado confirma ocho privilegios (incluido MAINTAIN) para anon/authenticated sobre `eco_capabilities`, pese a disponer únicamente de una policy SELECT para authenticated. Un UPDATE con ACL válida y sin filas visibles por RLS puede devolver cero filas sin error. 039j elimina esa autoridad SQL de escritura y mantenimiento y conserva SELECT bajo la policy existente.

La misma migración pendiente 039j comprueba los ocho privilegios efectivos de los cuatro roles mediante `has_table_privilege()`. No exige orden, representación ni grantor de la ACL. Rechaza autoridad de delegación no revisada para anon/authenticated y ACL por columna; el postcheck detecta accesos heredados/PUBLIC que impidan el hardening. Los errores de autoridad identifican rol y privilegio. Owner, RLS, policy y definiciones/estado de triggers se conservan. `aclexplode()` y diferencias de conjuntos, sin orden ni serialización, comprueban que los grants de los demás roles no cambien.

Revisión separada de otras tablas estructurales:

| Tabla | Evidencia LIVE disponible en esta tarea | Acción 039j |
|---|---|---|
| eco_role_templates | No aportada; pendiente de consulta readonly | Ningún cambio |
| eco_role_template_capabilities | No aportada; pendiente de consulta readonly | Ningún cambio |
| eco_platform_role_org_capabilities | No aportada; pendiente de consulta readonly | Ningún cambio |
| eco_user_platform_role | No aportada; pendiente de consulta readonly | Ningún cambio |

El script readonly preparado enumera ACL explícitas, permisos efectivos (incluidos heredados/PUBLIC), policies y ACL por columna de las cinco tablas. Sin ejecutarlo no se afirma que las otras cuatro tengan el mismo defecto.

Comprobaciones manuales preparadas:

1. Revisar `sql/039j_preflight_readonly.sql` en el proyecto canónico; resolver diferencias antes del UP.
2. Aplicar `sql/039j_harden_capabilities_acl.sql`. Sólo revoca privilegios de anon/authenticated en eco_capabilities y crea su backup privado.
3. Ejecutar `tests/db/039j_harden_capabilities_acl.sql`: comprueba autoridad efectiva (incluido MAINTAIN) y errores 42501 reales para UPDATE/INSERT/DELETE/TRUNCATE de ambos roles. Integra la lógica de 039i/039h y los controles 039g adaptados al preset operativo vigente, sin editar archivos históricos. En esta copia las ACL de funciones se comparan mediante conjuntos. Las pruebas de DELETE del owner/grants root, fuera del hardening 039j, exigen ausencia de mutación y distinguen por NOTICE si hubo 42501 o cero filas: no presentan cero filas como denegación SQL. La prueba de UPDATE de eco_capabilities mantiene el requisito estricto de 42501.
4. El mismo harness comprueba DOWN en un savepoint y hace ROLLBACK de todo. DOWN exige primero el estado efectivo instalado, restaura los ocho privilegios previos de anon/authenticated y valida el resultado con `has_table_privilege()`. No reconstruye una serialización ni modifica postgres/service_role. Para una reversión real, usar el DOWN 039j antes de otros DOWN.

No se ejecutaron esos pasos. No hubo commit, push ni deploy.
