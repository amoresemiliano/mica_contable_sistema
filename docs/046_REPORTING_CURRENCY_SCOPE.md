# DEV-MANAGEMENT-REPORTING-CURRENCY-01

15/10/2026. Base: `93ef0fad27f90b0fa42b388daabfb0450a0bc67a`. Rama dev.
Estado: IMPLEMENTED / STATICALLY_VERIFIED. Sin SQL ejecutado, despliegue ni acceso a PROD.
El PO confirma 045 instalado, harness aprobado y Edge/frontend desplegados en DEV.
Los conteos de DEV proceden del diagnóstico suministrado; no se volvieron a consultar remotamente.

## Causa y evidencia de moneda

El motor 045 aceptaba exclusivamente PES/ARS. La vista proyectaba `normalized_payload.moneda`
sin normalizar para comprobantes, por lo que las ventas/compras históricas con `$` se excluían.
Además, `resultMonth` propagaba el faltante de cualquier moneda extranjera a todas las métricas.
Las tarjetas anuales rechazaban cualquier mes nulo, aun sin actividad de esa familia de datos.

Evidencia local: `arcaParser.js` conserva la moneda importada (trim), usa PES como default si está
vacía y persiste `tipoCambio`. Puede sustituir cambio vacío/0 por 1 en determinadas ramas.
`persistenceService.js` también tiene fallback `tipoCambio || 1` al rehidratar.
039c usa la moneda en la identidad fiscal y guarda los valores normalizados sin multiplicarlos
por tipoCambio. Esto demuestra persistencia del campo, no certifica su procedencia/calidad ni
que todo exportador histórico entregue montos en moneda de origen. No se puede autorizar
una conversión fiable únicamente por la existencia de ese campo. No se implementa conversión.

Alias confirmados: PES, ARS, `$` → ARS, con trim y mayúsculas. USD/DOL/EUR y otros códigos
permanecen extranjeros; vacío/null queda sin moneda conocida, nunca se presume peso en reporting.
Los PES fijos de banco/nómina/manual de 045 se proyectan como ARS, conservando su contrato previo.
No se modifican parsers, importaciones, fingerprints, JSON de origen ni registros de negocio.

## Migración y rollback

- [046_reporting_currency_scope.sql](../sql/046_reporting_currency_scope.sql).
- [046_reporting_currency_scope_down.sql](../sql/046_reporting_currency_scope_down.sql).

045 y su rollback permanecen intactos (verificación de hashes de contenido en las pruebas).
046 requiere 045 y rechaza marcador existente, vista ya reparada sin marcador, funciones adicionales
o drift de definición/seguridad. Fija siete hashes canónicos de cuerpo, owner postgres, SECURITY
DEFINER donde corresponde, search_path vacío y ausencia de grants indebidos.

La vista se fija comparando `pg_get_viewdef` de la instalada contra una vista temporal que contiene
la definición completa congelada de 045. PostgreSQL formatea ambos lados del mismo modo; no se
compara el SQL fuente crudo contra una cadena de formato supuesto. Otra copia temporal fija
la definición 046 esperada. Solo cambia la proyección de currency, manteniendo tipos/columnas,
signos, importes, predicados de aceptación/tenant y dependencias.

Se respalda la definición real anterior. CREATE OR REPLACE conserva el OID de la vista, owner y ACL.
El postflight verifica esas propiedades, options, RLS y funciones/grants sin cambios. No se cambia
ningún RPC ni autorización. El rollback rechaza drift, restaura la definición respaldada y elimina
solo el marcador técnico 046; conserva todos los datos y snapshots, incluso los creados después.
La sintaxis fue parseada localmente; compilación/ejecución en PostgreSQL queda para aplicación manual.

## Semántica y alcance por métrica

Cada línea monetaria aporta `status`, `supported_value`, cantidades incluidas/excluidas,
grupos excluidos, moneda e importe de origen separado. Importes fuente extranjeros se mantienen
en centavos de su propia moneda, sin entrar en ninguna suma ARS. La trazabilidad conserva
el valor de moneda usado por el RPC de origen para que el detalle también funcione con datos 045.

| Métrica | Dependencias y tratamiento |
|---|---|
| Ventas, gravadas/no gravadas, NC | Solo SALES; compra USD no afecta ventas en pesos. |
| Compras | PURCHASES/MANUAL_PURCHASE. Total completo nulo si hay exclusiones; subtotal ARS y conteos visibles. |
| Nómina y banco | Solo su respectiva familia. Una factura USD no los invalida. |
| Resultado | Ventas/compras/nómina/manuales/cargas. Omisión USD o componente faltante impide el total; no se presenta un subtotal engañoso de resultado. |
| IVA CF / DF | Cada uno depende de sus propios comprobantes y calidad de IVA. DF sigue visible con compras USD; CF completo queda pendiente. |
| IVA técnico / LD | Arrastres separados. Créditos y apertura conocidos no se borran por un problema de otra línea. Total a pagar conserva sus bloqueos pertinentes. Banco extranjero no afecta IVA. |
| IIBB | Solo ventas, tasas/configuración y créditos fiscales pertinentes. Compras/banco/nómina extranjeros no afectan base ni cierre de IIBB si lo demás está completo. |

Reportes Resultados/IVA materialmente incompletos no pueden REVISARSE/CERRARSE. La validación
se ejecuta en el endpoint confiable con el motor compartido; no depende de botones del navegador.
RECORD_ANOMALIES conserva las exclusiones USD, sin contar `$`/PES/ARS como anomalías de moneda.

## Sin actividad frente a datos faltantes

- AVAILABLE: existen importes canónicos completos para la métrica.
- NO_ACTIVITY: cero registros de esa familia en ese mes, con evidencia de la misma familia en
  el conjunto consultado. Es cero dentro del universo de datos importados, no certificación de
  ausencia de actividad real ni completitud de extractos/DDJJ.
- NO_DATA: no hay evidencia de esa familia en el período consultado, o falta el dato requerido.
- INCOMPLETE: hay datos relevantes pero se excluyeron monedas/importes o falta una dependencia.

Las tarjetas anuales suman los meses NO_ACTIVITY como cero. No convierten NO_DATA/INCOMPLETE
en totales completos. Ejemplo: una factura no prueba presencia del dataset bancario; banco
permanece NO_DATA si no hay movimientos bancarios en todo el período.

## UI, archivos e historia

Compras indica “ARS incluido” cuando muestra subtotal parcial y expone “137 comprobantes de
compra en ARS incluidos / 4 excluidos”, con causa precisa. Resultado explica los cuatro USD,
y margen/puente siguen esa dependencia sin atribuirla a falta de cargas cuando no corresponde.
Los importes de detalle USD se muestran con USD, nunca con formato ARS. Categorías y fuentes
del subtotal conservan moneda y exclusiones en el drill-down.
XLSX/CSV/PDF incluyen estado, subtotal ARS, conteos, moneda de fuente y resumen de importes
excluidos en moneda original. Ningún archivo convierte un subtotal parcial en total definitivo.

Se conserva `engine_version=management-v1`, porque es la familia aceptada por los contratos
instalados; nuevos cálculos incluyen `calculation_revision=currency-scope-046` en modelo,
reporte y metadatos exportados. No se recalculan ni reescriben cierres históricos. La vista
de snapshot sigue usando sus fuentes y valores congelados, con las monedas originales.

## Verificación local

Fixture sintética con los conteos suministrados (no son importes reales de DEV):
4 SALES `$`, 137 PURCHASES `$`, 4 PURCHASES USD, 83 BANK PES, 1 PAYROLL PES,
14 TAX ARBA y 50 TAX IVA. Los ARBA sin impuesto/jurisdicción fiable conservan su faltante;
este WP no inventa su clasificación para hacer desaparecer alertas fiscales.

107 pruebas enfocadas aprobadas en 10 suites. Incluyen alias, tipos de faltante, anualización,
no conversión incluso con tipoCambio, IVA independiente, IIBB independiente, cierre rechazado
cuando corresponde/permitido en reporte independiente y aislamiento de tenant.
Suite amplia: 824 aprobadas y los mismos 9 fallos históricos de hashes de migraciones anteriores.
Los nombres de fallo se compararon con la evidencia de la entrega anterior; no hay fallas nuevas.
Parser local: 25 sentencias SQL y 4 bloques PL/pgSQL; no ejecución SQL.
Node verifica sintaxis JS/entrypoint TS; git diff --check.
Edge headless local, Supabase sustituido por stub: anualización y valores independientes,
137/4 incluidas/excluidas, advertencia precisa de resultado, detalle USD sin conversión,
ausencia de overflow móvil, revocación y snapshots del recorrido existente.
Capturas locales: `scratch/currency046-desktop.png`, `scratch/currency046-mobile.png`.

```text
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --runTestsByPath tests/reportingCurrency046.test.js tests/reportingEngine.test.js tests/reportingServer.test.js tests/reportingExports.test.js tests/reportingSql.test.js tests/ui/panelGerencial.test.js tests/services/classification039e.test.js tests/ui/moduleAccess039.test.js tests/ui/realDomIntegration.test.js tests/perceptionFileReuse044.test.js
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests --json --outputFile scratch/currency046-tests.json
node tests/browser/management-reporting.mjs
git diff --check
```

## Aceptación DEV pendiente de operación posterior

1. Aplicación humana de 046: preflight/postflight deben pasar; no se reimportan datos ni se cambia 045.
2. Posterior despliegue autorizado de Edge mica-reporting y frontend del mismo commit; regenerar
   vistas previas para usar la misma revisión. Este trabajo NO ejecuta ese despliegue.
3. Demo Norte / año 2026: cuatro ventas en ARS, 83 movimientos bancarios y nómina disponible donde
   exista importe canónico. Compras: 137 incluidas, cuatro USD excluidas. Revisar los importes reales.
4. Resultados/IVA: subtotal y fuentes visibles; cierre rechazado por omisión USD. IIBB no debe
   mencionar compras USD como causa; puede seguir pendiente por tasas/actividad/créditos faltantes.
5. Alternar empresa y abrir un cierre anterior: aislamiento, importes y moneda congelados conservados.

Preparado para migración y despliegue DEV en ese orden, con validación runtime posterior.
No se afirma DEV_RUNTIME_VERIFIED para la reparación; tampoco se afirma que 046 esté instalada.
