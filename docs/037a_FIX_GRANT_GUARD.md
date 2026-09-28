# 037a: corrección del trigger compartido de grants

La expresión SQL con `TG_TABLE_NAME=... AND ...NEW.role_template_id` obliga a
resolver una columna que no existe en `eco_membership_capability_overrides`.
El `AND` no protege la resolución del campo del registro. El hotfix separa
bridge y membership mediante ramas PL/pgSQL; membership sólo valida scope
ORGANIZATION. Las otras tres ramas y la barrera OWNER_RESERVED se conservan.

El UP reemplaza únicamente `private.guard_036_grant()`. El preflight exige
el cuerpo defectuoso de 036 (MD5 normalizado), firma, lenguaje, volatilidad,
SECURITY DEFINER, search_path vacío y ejecución por el owner de la función.
Guarda `pg_get_functiondef`, OID, owner y ACL en una tabla privada con RLS y
sin permisos para otros roles. CREATE OR REPLACE conserva owner, ACL y OID;
el script lo comprueba. No recrea triggers ni modifica grants existentes.

El DOWN rechaza cambios posteriores de definición, owner, ACL u OID antes
de restaurar la definición LIVE capturada. Elimina sólo su tabla de respaldo,
sin CASCADE. Es rollback histórico: reintroduce deliberadamente el error 42703.

El harness 036 no insertaba un override membership ORGANIZATION válido;
sus rechazos de OWNER_RESERVED salían antes de la rama defectuosa. Ahora
incluye INSERT/UPDATE ALLOW/DENY. El harness 037a cubre también scopes
incompatibles, capabilities reservadas y las ramas de templates, bridge y
platform overrides. Ambos usan BEGIN/ROLLBACK. El harness 037a necesita una
membership existente y capabilities MICA indicadas en sus consultas iniciales;
no presupone TENANT_ADMIN ni crea usuarios/memberships.

Verificación manual pendiente (ningún SQL fue ejecutado por el agente):

1. Revisar UP y DOWN; el preflight debe abortar ante cualquier cuerpo inesperado.
2. Tras aplicación manual autorizada de 037a, el harness 037a debe terminar sin
   error y ejecutar su ROLLBACK final.
3. Revalidar los harnesses 036 y 037 después del hotfix, sin reaplicar sus UP.

Jest valida contratos estáticos; no prueba la ejecución del trigger en PostgreSQL.
