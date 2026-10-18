# DEV-MANAGEMENT-REPORTING-01 — auditoría y diseño

Fecha: 14/10/2026. Base: `f216d14463c28bb331d4bdb8090143ede604c31c`, rama dev.
Auditoría de contratos del repositorio; no se consultó ni ejecutó SQL en ninguna base.
Los volúmenes y el esquema instalado actual no pueden certificarse bajo esa restricción.
La migración verificará dependencias y rechazará instalación parcial antes de escribir.

## 1. Evidencia canónica

| Contrato | Evidencia | Capacidad / limitación |
|---|---|---|
| Comprobantes | 010, 011, 014, 039, 039c, 043; eco_normalized_records + eco_import_rows | fecha, total, CUIT, tipo_cbte, netoGravado, totalIva, exento, netoNoGravado, moneda, tipoCambio; clasificación tipada category_id/activity_id. Excluir borrados, duplicados y posibles enmiendas sin resolver. |
| Percepciones/retenciones | 012, 039c, parsers perceptionFormats/ivaPerceptionParser | Importe persistido, fuente y tipo explícitos. ARBA no identifica por sí sola provincia ni impuesto Ganancias. No inferirlos. No sumar otrosTributos como percepción IVA. |
| Banco | 013, 026, bankParser | monto, debit/credit, fecha, cuenta, saldo opcional. Sin conciliación persistida ni evidencia de integridad de todos los extractos. Saldo observado, nunca caja disponible certificada. |
| Nómina | 013, 026, salaryParser | período, remunerativo, noRemunerativo, SAC y neto. Cargas empleador no están garantizadas. Neto no es costo laboral. |
| Manual | 039c private.eco_manual_records | PURCHASE sin neto/IVA desglosado; INTERNAL Ingreso/Gasto por imputación. Autoría y fecha persistidas. |
| Categorías / actividades | 014, 032–034 | catálogos canónicos y asignación tipada. No hay asignación contable fiable por texto libre. |
| Alícuotas IIBB | 041, 042 | definición Platform y asignación a organización con vigencia; reutilizar, nunca duplicar tasa. |
| Empresa / permisos | 038–042 | CUIT y nombre, contexto activo, require_039_action, REPORT_VIEW / REPORT_EXPORT; edición manual mediante MANUAL_MOVEMENT_EDIT; cierre mediante ambos permisos. Sin permisos paralelos. |
| Reportes | búsqueda de CREATE TABLE en migraciones | No existen aperturas, coeficientes CM anuales, ajustes fiscales anuales, snapshots ni umbrales de alertas. |
| UI actual | index.html, ui.js renderClientDashboard | Dos secciones con mismo ID y cálculos de totales acumulados en cliente. Se sustituyen por una Gerencia y una sección Reportes; shell conservado. |

## 2. Matriz de entrega

A = automático con datos persistidos; B = requiere clasificación/configuración; C = ingreso manual; D = futuro/no fiable.
Todos los automáticos se presentan como cobertura de los datos importados, no certificación de completitud.

| Métricas / campos solicitados | Clase | Regla |
|---|---|---|
| Ventas brutas, NC, netas, gravadas, exentas/no gravadas | A | NC por códigos explícitos; normalizar signo sin doble negación. Moneda extranjera queda excluida y señalada hasta política de conversión validada. |
| MoM, YoY, YTD, promedio, mejor/peor mes, tendencias 3/6/12, run-rate | A | Fechas y comparación explícitas; denominador cero ⇒ no disponible; run-rate es proyección aritmética. |
| Distribución por actividad; compras por categoría, proveedor, participación, Top 10, variaciones | B | category_id/activity_id canónicos; sin clasificar separado y cobertura visible. |
| Ventas por jurisdicción | D | Factura no contiene atribución jurisdiccional fiable; CM distribuye base configurada, no ventas observadas por provincia. |
| Resultado mensual/acumulado/comparativo, margen, egresos/ventas, meses positivos/negativos | A/B | Resultado documental antes de impuesto y cargas faltantes; nunca resultado contable definitivo. |
| Personal/ventas, sueldo bruto, neto, SAC | A | Nómina importada; distinguir costo bruto de sueldo neto. |
| Cargas sociales, sueldo+cargas, impuestos/gastos manuales | C | Cargas y ajustes documentados por período; no sumar aportes retenidos como cargas empleador. |
| EBITDA, punto de equilibrio, costos recurrentes, ratios de liquidez/DSO/DPO/CCC | D | Faltan costos fijos/variables, devengamientos, cuentas a cobrar/pagar y vencimientos. |
| Ingresos/egresos/flujo banco, grandes movimientos | A | credit menos debit; no duplicar como ventas/gastos en resultados. |
| Saldo inicial/final/mínimo/máximo/promedio | A parcial | Por cuenta, saldos observados; orden intradía ambiguo ⇒ inicial/final no disponibles; promedio de observaciones, no promedio diario. |
| Caja disponible, saldo actual certificado, burn/cobertura futura | D | Extractos incompletos y sin caja; mostrar flujo negativo observado, no prometer cobertura. |
| Comisiones/impuestos/retenciones banco | B | Clasificación explícita; sin heurísticas sobre descripción. |
| Conciliación %, monto, pendientes y antigüedad | D | Sin contrato canónico de conciliación persistida. |
| IVA CF/DF/saldo técnico/evolución | A | neto de NC; IVA ausente bloquea determinación, no cero silencioso. |
| IVA retenciones/percepciones | A/B | Tipo e impuesto explícitos. Ajustes manuales separados, impedir doble conteo de representaciones. |
| Apertura técnica/LD, compensación, ajustes IVA | C | Configuración inicial con período; arrastre mensual determinista; compensación limitada a deuda y LD disponible. |
| IVA a pagar/LD | A+C | Requiere apertura y cobertura; fórmula documentada debajo. |
| IIBB ventas/base actividad/tasa/impuesto | B | Régimen explícito, actividad por factura, tasa canónica vigente única; base documental estimada. |
| CM provincia/coeficiente/base jurisdiccional | C+B | Coeficientes por año y jurisdicción, sumatoria 1, alícuota por vigencia. |
| IIBB retenciones/percepciones/banco, saldo anterior/interés/ajustes | A/B/C | Solo impuesto y jurisdicción explícitos; entradas manuales para faltantes y sin duplicar. |
| Proporción IVA de referencia IIBB | D | No se suministró fórmula de negocio verificable. |
| Ganancias resultado acumulado y retenciones identificadas | A | Datos documentales auxiliares; sin inferir categoría de renta. |
| Ganancias categorías 1–4, ingresos gravados/exentos, deducciones, SAC, quebrantos, pagos/anticipos/saldos | C/B | Datos anuales tipados y extensibles; la clasificación fiscal anual la confirma el contador. |
| Ganancia sujeta, impuesto determinado/a ingresar | C+B | Determinado ingresado/configurado por contador; sin escalas legales inventadas. Base calculada solo con componentes explícitos. |
| Bienes/deudas por categoría, ARS/USD, patrimonio inicial/final | C | Valuación ARS explícita y moneda original; no sumar monedas distintas. |
| Justificación patrimonial: consumo, herencias, amortizaciones, ventas, diferencias, otros cambios | C | Campos anuales auditados; fórmula y diferencias visibles, sin autoexplicar faltantes. |
| Datos empleado individual | D | Importación consolidada. |
| Contexto mercado, inflación, tasas, FX | D | Adaptador previsto sin conector ni datos ficticios. |
| Benchmark pares | D | Cohorte mínima conceptual 10; sin consultas entre organizaciones ni cifras simuladas. |
| Alertas financieras/fiscales/calidad/positivas | A/B | Reglas deterministas, umbrales org y comparativos; no activar reglas sin sus datos. |

## 3. Contratos de cálculo y persistencia

Un motor JS puro versionado (`management-v1`) compartido por Gerencia, Reportes y función Edge.
Recibe agregados del servidor, nunca toda la historia ni estado de formularios. Dinero en centavos
enteros; redondeo explícito al aplicar tasas. Fuente, cantidad, fórmula, filtros de drill-down y
faltantes acompañan cada línea. Aggregate RPC agrupa por mes/tipo/categoría/actividad/moneda y
proveedor; detalle paginado de 100, máximo 200 filas por solicitud. Rango máximo 36 meses.

Migración aditiva 045 (este nuevo WP): tablas privadas de entradas versionadas (ámbito/período/tipo,
payload, actor, timestamp, nota), snapshots inmutables y eventos de estado. RLS activada,
sin acceso directo. Una revisión nueva nunca borra la anterior. Configuraciones: IVA_OPENING,
PERIOD_ADJUSTMENT, IIBB_CONFIG, CM_COEFFICIENTS, ANNUAL_TAX, ALERT_SETTINGS.
Se reutilizan catálogos/alícuotas existentes. Rollback deshabilita RPCs y conserva tablas/historia.

La función Edge usa el JWT del usuario para leer agregados y autorizar edición/exportación.
El cierre se recalcula en servidor con el mismo motor, y solo service_role puede persistir
el resultado calculado; verifica hash de entradas, contexto y permisos antes del insert.
No se confía en valores calculados enviados por el navegador. Snapshots guardan entradas,
salidas, versión, fuentes resumidas, metadatos y autor. BORRADOR no implica revisión.
REVISADO requiere acción expresa; CERRADO no cambia con reclasificaciones futuras.
Reapertura crea evento/version nueva y deja intacto el snapshot anterior.

## 4. UI

Gerencia: barra persistente empresa activa / Desde / Hasta / Mes-Trimestre-Año-YTD /
comparar anterior-interanual. Navegación Resumen, Resultados, Tesorería, Fiscal, Análisis.
Resumen: 8 tarjetas, valores/faltantes, deltas y sparklines; tendencia mensual, waterfall,
categorías, alertas explicables. Resultados: series comparativas y categorías/proveedores.
Tesorería: flujo y saldos observados por cuenta; Fiscal: IVA/IIBB y faltantes;
Análisis: tendencias, cobertura y arquitectura benchmark explícitamente no disponible.
SVG nativo accesible + tablas alternativas; sin nuevas dependencias de gráficos.

Reportes: tipo/período → vista previa con fórmula y procedencia → XLSX/CSV/PDF imprimible.
Formularios: Apertura IVA; ajustes mensuales; régimen IIBB; coeficientes CM por año;
Datos fiscales anuales por categoría/renta/bienes/deudas/deducciones/ajustes; umbrales de alertas.
Archivos XLSX incluyen Resumen, Cálculos, Fuentes, Entradas manuales y Metadatos.
Estados/versiones e historial de cierres/reapertura. Drill-down reutilizable paginado.
ARS es-AR; fecha DD/MM/YYYY; faltante no se representa como cero.

## 5. Catálogo de alertas

SALES_DROP, EXPENSE_GROWTH, NEGATIVE_RESULT, TWO_NEGATIVE_MONTHS, PAYROLL_SHARE,
FISCAL_SPIKE, BANK_BALANCE_DROP, LARGE_UNCLASSIFIED_BANK, CLASSIFICATION_COVERAGE,
IMPORT_ISSUES, RECORD_ANOMALIES, MARGIN_IMPROVING, RECORD_SALES.
Cada regla tiene categoría, severidad por defecto, umbral, enabled y modo de comparación.
Organización puede ajustar esos parámetros; valores actuales/comparados y causa visibles.
Reglas sin evidencia se omiten; no se equipara omisión con ausencia de problemas.

## 6. Fórmulas

- Neto documental = neto gravado + no gravado + exento, NC = -abs(importes).
- Resultado documental = ventas netas − compras netas − remuneración bruta − cargas ingresadas
  + otros ingresos manuales − otros egresos manuales. Banco no se suma nuevamente.
- IVA: técnico = DF − CF; técnico del período = técnico − crédito técnico previo;
  crédito técnico siguiente = max(0, -técnico del período).
  LD disponible = LD previo + retenciones + percepciones + ajustes LD.
  deuda técnica = max(0,técnico del período). Compensación aplicada explícita, entre 0 y
  min(deuda técnica, LD disponible); a pagar = deuda técnica − compensación;
  LD siguiente = LD disponible − compensación. No consumir LD automáticamente sin instrucción.
- IIBB LOCAL: suma(base de cada actividad × tasa vigente/100).
  CM: suma(base actividad × coeficiente jurisdicción del año × tasa vigente/100).
  Ajustes por jurisdicción/período: determinado − retenciones − percepciones − retención banco
  − saldo previo + interés + ajuste; separar saldo a favor de total a pagar.
  Cambio de tasa intramensual se calcula por fecha efectiva antes de agregar.
- Ganancias: base = ingresos gravados por categoría − deducciones admitidas − deducciones
  personales − quebrantos (solo datos anuales confirmados); impuesto determinado manual;
  a ingresar = max(0,determinado − pagos a cuenta − retenciones − saldo anterior).
  Bienes: total de valuaciones ARS; patrimonio = bienes − deudas; comparación anual separada.
  Sin escalas legales ni determinación automática de Bienes Personales en este WP.

## 7. Seguridad, implementación y aceptación

REPORT_VIEW habilita lectura; REPORT_EXPORT habilita archivos; MANUAL_MOVEMENT_EDIT además
de REPORT_VIEW habilita entrada manual/configuración; cierre/revisión/reapertura requieren además
REPORT_EXPORT. Se reutilizan permisos existentes; no se otorgan permisos nuevos automáticamente.
Cada RPC comprueba contexto confirmado y organización esperada. No ofrece UUID arbitrario como
autoridad. Edge ignora organización/actor de payload en cierre: obtiene contexto autorizado.
Cambios de empresa invalidan solicitudes pendientes, borran resultados/detalles y obligan a recargar.

Secuencia: auditoría → migración/contratos → motor compartido y pruebas → UI y exportaciones →
pruebas de seguridad/estado, parser SQL/PLpgSQL sin ejecución, diff → commit/push dev.
No desplegar ni ejecutar SQL. Verificación runtime queda pendiente de aplicación humana de migración
y despliegue autorizado posterior. Manual DEV: dos empresas aisladas; NC resta; apertura IVA arrastra;
CM suma 1/tasas vigentes; XLSX trazable; cierre inmutable tras reclasificar.
