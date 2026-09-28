# 036 — Owner core y límites de delegación

Estado: IMPLEMENTED / STATICALLY_VERIFIED. Preparado para revisión manual; no verificado en PostgreSQL. Cero SQL ejecutado, cero commit/push/deploy. No se implementan 037–040.

## Modelo y decisión

Un template reutilizable no identifica al único owner. Se adopta **B**: las once capabilities reservadas salen del template y se resuelven mediante identidad estructural más un conjunto privado de grants. Copiar o asignar `VEGEN_PLATFORM_ADMIN` no copia esa autoridad.

`private.eco_platform_owner` contiene exactamente una fila, con el profile `9563f41e-cd57-42d9-8626-9b04bd6e5863` y auth UUID `c1e16acf-a45c-4e51-a3e5-c95208adc3c6`. Un boolean PK con CHECK impide una segunda fila; los triggers impiden eliminar, reemplazar o truncar la primera. Las FKs preservan los vínculos. El email y `profile.role` no autorizan.

El owner y su asignación de plataforma quedan protegidos también frente a DML de futuras RPCs SECURITY DEFINER. Una transferencia requerirá una migración administrativa excepcional revisada. No hay bypass ordinario para el propio owner. Un administrador de PostgreSQL capaz de deshabilitar triggers o ejecutar DDL sigue siendo parte de la frontera de confianza.

## Clasificación final

| Clase | Regla aplicada a las filas existentes |
| --- | --- |
| OWNER_RESERVED | Los once códigos enumerados abajo; todos deben existir activos con scope PLATFORM. |
| PLATFORM_DELEGABLE | Todo código PLATFORM restante, incluyendo explícitamente ORGANIZATION_UPDATE. |
| ORGANIZATION_DELEGABLE | Todos los códigos con scope ORGANIZATION; no se modifica can_org ni se otorga acceso adicional. |

OWNER_RESERVED: `PLATFORM_MANAGE`, `GLOBAL_USER_MANAGE`, `PLAN_MANAGE`, `ACCESS_ANY_ORG`, `SUPPORT_IMPERSONATE`, `HARD_DELETE_EXCEPTIONAL`, `ORGANIZATION_CREATE`, `ORGANIZATION_ARCHIVE`, `PLATFORM_MIGRATIONS_APPLY`, `PLATFORM_TENANTS_PROVISION`, **`PLATFORM_SYSTEM_MONITOR`**.

`PLATFORM_SYSTEM_MONITOR` se reserva: no se recibió evidencia de un contrato estrictamente de lectura que justifique delegarlo. `ORGANIZATION_UPDATE` queda PLATFORM_DELEGABLE; esto no implementa su delegación ni su alcance futuro.

Los PLATFORM_DELEGABLE conocidos en 019 son `ORGANIZATION_UPDATE`, `GLOBAL_CATALOG_VIEW`, `GLOBAL_CATALOG_MANAGE`, `CATALOG_ASSIGN_ANY_ORG`, `RATE_MANAGE_ANY_ORG`, `REPORT_COMPARE_SCOPED_ORGS`, `REPORT_CONSOLIDATED_SCOPED_ORGS`, `SAAS_ANALYTICS_VIEW`, `AUDIT_PLATFORM_VIEW`.

Los ORGANIZATION_DELEGABLE conocidos en 019/033 son `ORG_VIEW`, `ORG_SETTINGS_VIEW`, `ORG_SETTINGS_MANAGE`, `ORG_MEMBER_VIEW`, `ORG_MEMBER_INVITE`, `ORG_MEMBER_MANAGE`, `ORG_MEMBER_PERMISSION_MANAGE`, `IMPORT_VIEW`, `IMPORT_CREATE`, `IMPORT_RETRY`, `IMPORT_REVIEW`, `RECORD_VIEW`, `RECORD_CLASSIFY`, `RECORD_SOFT_DELETE`, `RECORD_RESTORE`, `PERCEPTION_IMPORT`, `BANK_IMPORT`, `PAYROLL_IMPORT`, `ISSUE_RESOLVE`, `CATALOG_ORG_VIEW`, `REPORT_VIEW`, `REPORT_EXPORT`, `TICKET_CREATE`, `TICKET_VIEW_ORG`, `AUDIT_VIEW_ORG`, `CATALOG_ACTIVITY_MANAGE`, `CATALOG_CATEGORY_MANAGE`. Otros códigos LIVE se clasifican por la regla exhaustiva de scope anterior; no se afirma haber consultado su inventario en esta ejecución.

La nueva columna es NOT NULL, sin default, y tiene CHECK de compatibilidad con scope. Las altas futuras deben indicar su clase. El guard impide crear otra capability reservada, renombrar códigos o alterar ID/scope/clase mediante CRUD ordinario.

## Helper nuevo y cambio de autoridad

```sql
CREATE FUNCTION private.is_platform_owner()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS (
    SELECT 1 FROM private.eco_platform_owner o JOIN public.eco_user_profiles p ON p.id=o.user_profile_id
    WHERE o.auth_user_id=auth.uid() AND p.auth_user_id=o.auth_user_id AND p.is_active IS TRUE
      AND p.id=private.current_profile_id());
$$;
```

`private.can_platform(text)` conserva firma, owner y ACL. Para una capability existente/activa PLATFORM, la rama reservada exige el helper anterior y una fila en `private.eco_owner_reserved_capabilities`. Para las otras capabilities queda idéntico el algoritmo anterior: DENY > ALLOW > grant base > false. Jest compara ese tramo con 019, no sólo palabras clave.

La RPC pública `get_capability_delegation_contract()` devuelve `code`, `scope`, `delegation_class`, `is_delegable`. Exige sesión y perfil activo; sólo el owner recibe metadata reservada, siempre con `is_delegable=false`. No es una autorización para asignar permisos. La UI queda fuera de 036.

## Integridad y ACL

- Triggers BEFORE INSERT/UPDATE bloquean capabilities reservadas en templates, overrides de plataforma, bridges, overrides de membership y la tabla legacy. Cubren reemplazo de capability_id y cualquier actualización/reactivación de filas. El FK real de legacy se descubre en catálogo; no se inventan columnas ni se altera su semántica GRANT/REVOKE.
- Los grants nuevos deben ser compatibles con su scope; los templates no pueden cambiar de scope. La clonación sólo puede copiar los grants delegables restantes.
- Triggers protegen el profile owner, su asignación de plataforma y su template activo; protegen identidad, grants privados y baseline frente a INSERT/UPDATE/DELETE/TRUNCATE.
- Ningún nuevo helper privado se expone a anon/authenticated. Se eliminan también grants recibidos por default ACL. La RPC de metadata sólo otorga EXECUTE a authenticated.
- No hay cambios de grants de contadora, can_org, memberships, usuarios u organizaciones operacionales en el up/down. El harness sí usa fixtures transaccionales que terminan en ROLLBACK.

## Preflight, baseline y rollback

El up valida objetos ausentes, columnas/tipos, claves únicas, FKs de identidad/template y capabilities, identidad/actividad del owner y template, grants esperados, asignación de contadora y ausencia de autoridad reservada ajena. Bloquea las tablas de entrada mientras audita e instala los guards. Cualquier inconsistencia aborta antes del primer CREATE/ALTER/DELETE.

Se exige la definición de `can_platform` revisada en 019: MD5 del cuerpo normalizando CR y whitespace exterior, firma, SECURITY DEFINER, STABLE y search_path vacío. Se exige que el ejecutor sea su propietario para conservar el acceso privado del definer. En el cierre pre-aplicación el usuario confirmó LIVE MD5 `bb8759cafcc9ba64d92b549b485d3411`, owner `postgres`, SECURITY DEFINER, STABLE y search_path vacío. Evidencia suministrada por el usuario; el agente no ejecutó SQL.

El baseline privado guarda `pg_get_functiondef`, propietario, ACL exacta y filas completas de los grants retirados. Su contenido no se publica por RPC. El down restaura esa definición y las filas originales, verifica owner/ACL y elimina únicamente objetos 036 sin CASCADE. Como el up no modifica la ACL del helper, se preserva incluso el caso ACL NULL; el down aborta si hubo cambios posteriores de ACL/owner. También aborta si se asignó el template del owner a otro perfil después de 036: restaurar los grants antiguos en ese caso volvería a delegar el núcleo. La clasificación previa se restaura eliminando la columna que obligatoriamente no existía antes.

Checks LIVE finales confirmados por el usuario:

1. Las únicas tablas con FK a eco_capabilities son las cinco contempladas por 036, incluida la legacy. El preflight mantiene la comprobación de columnas y constraints al aplicar.
2. Los once grants reservados existen exclusivamente en VEGEN_PLATFORM_ADMIN, UUID `6331de19-de61-43fb-98cd-7d24f2235359`; no hay grants en otros templates, asignados o no.
3. El contrato de can_platform coincide con los atributos y MD5 indicados arriba. No se modifica el up 036 durante este cierre.

Los blockers LIVE previamente enumerados quedan resueltos según esa evidencia. El preflight sigue siendo obligatorio al aplicar. No se afirma que 036 esté aplicada ni que el harness DB haya pasado. Un error deja la transacción abortada: se debe cerrar con ROLLBACK antes de otra operación manual.

Auditoría del down: todos los triggers 036 se eliminan explícitamente antes de sus funciones; los tres frozen privados se eliminan también antes de sus tablas. Se restaura can_platform usando el baseline antes de retirar sus dependencias nuevas; la RPC de metadata se retira antes de is_platform_owner, los helpers antes de las tablas privadas y el CHECK antes de delegation_class. Las referencias dinámicas a las cinco tablas de grants tienen sus cinco DROP TRIGGER explícitos. No se usa CASCADE. La comprobación es estática, sin ejecutar rollback.

035a registra exclusivamente la normalización ya aplicada manualmente: defaults y cuatro filas con el tuple completo CIF/ES/EUR/Europe/Madrid pasan a CUIT/AR/ARS/America/Argentina/Buenos_Aires. Los scripts `sql/035a_normalize_argentina_organization_defaults.sql` y su `_down.sql` son registro histórico y no se deben ejecutar. No asignan IDs, names, legal_name, trade_name, tax_id ni is_active. El down es la inversa del baseline de cuatro filas; sin IDs históricos no puede demostrar procedencia después de cambios posteriores. Ambos abortan ante un conteo o tuple diferente, bajo lock transaccional. Los guards son controles añadidos al registro; no se afirma que formaran parte del SQL manual original.

## Archivos y evidencia

- SQL completo: `sql/036_owner_core_and_delegation_guard.sql`.
- Rollback completo: `sql/036_owner_core_and_delegation_guard_down.sql`.
- Harness SQL Editor: `tests/db/036_owner_core.sql`, autocontenido, sin variables psql, JWT simulado, assertions públicas bajo authenticated y ROLLBACK final. Preparado, **no ejecutado**.
- Jest: `tests/services/ownerCore036.test.js`, más hashes de los up/down 031–035 en `tests/fixtures/036_preexisting_migrations.sha256.json`.
- Diffs de revisión: `scratch/036-can-platform.diff` y `scratch/036-owner-core-review.diff`.

Jest completo del cierre: 35 suites / 428 tests pasan. No hay script de build en package.json; frontend sin modificaciones. Esto no demuestra compilación SQL ni comportamiento real de triggers. `git diff --check` se complementa con revisión de whitespace de todos los archivos nuevos, porque aún son untracked. Los archivos 031–035 y el up 036 permanecen idénticos byte a byte.

Aceptación manual pendiente, sin ejecución por el agente: revisar preflight y diff; aplicar up en DEV sólo cuando se decida hacerlo; ejecutar el harness completo y exigir el NOTICE final seguido de ROLLBACK; revisar separadamente el down contra el baseline. El rollback está preparado para recuperación, no es una operación ejecutada ni un paso automático del test.
