# DEV-MANAGEMENT-REPORTING-01 — entrega

15/10/2026. Estado: IMPLEMENTED / STATICALLY_VERIFIED / READY_FOR_MANUAL_CHECK.
Base: `f216d14463c28bb331d4bdb8090143ede604c31c`. Rama: dev.
Diseño previo: [auditoría y matriz](DEV_MANAGEMENT_REPORTING_01_DESIGN.md).
No se ejecutó SQL, no hubo despliegue y no se accedió a PROD.

## Resultado

Gerencia tiene cinco vistas, ocho tarjetas simultáneas, filtros de fecha y comparación,
períodos rápidos (mes/trimestre/año/YTD/3/6/12 meses), sparklines, series, barras,
waterfall, categorías/proveedores/actividades, nómina y 13 reglas de alertas explicables.
Categorías muestran participación y variación contra el período elegido. Falta de datos
aparece como no disponible; las cifras se presentan como documentales/estimadas.
Se eliminó el HTML duplicado y el cálculo histórico sobre arrays operativos del navegador.
Los módulos usan agregados del servidor y mantienen la navegación/autorización existente.

Reportes: IVA, IIBB LOCAL/CM, Estado de Resultados y auxiliar Ganancias/Bienes Personales.
Comparten el motor `management-v1` con Gerencia y con el endpoint de servidor.
Se incorporan seis formularios: apertura IVA, ajustes mensuales, régimen IIBB,
coeficientes CM anuales, datos fiscales anuales y umbrales de alertas.
XLSX principal (cinco hojas con cálculos/fuentes/manuales/metadatos), CSV UTF-8 y PDF
mediante el diálogo de impresión del navegador. No se añadió una biblioteca de gráficos.

Cada línea expone fórmula, fuente, cantidad, filtros de detalle y autoría de entradas
manuales. El detalle devuelve IDs persistidos por páginas de 100 (máximo 200 por RPC).
El arrastre IVA incluye fuentes de los meses anteriores y exige cadena completa desde
una apertura explícita. No se consume LD sin compensación instruida por el contador.
IIBB usa tasas canónicas por fecha de cada segmento agregado; una tasa ausente o ambigua
bloquea la estimación. NC resta mediante signo explícito y valor absoluto, sin doble negación.
Moneda extranjera y tipos de comprobante no reconocidos impiden inventar cifras ARS.

Los cierres guardan entradas, cálculo, motor, hash, versión, actor y manifiesto de fuentes.
Tablas append-only con triggers que rechazan UPDATE/DELETE. Reapertura registra evento y
deja intacta la versión anterior. Una vista previa de un período cerrado carga su snapshot;
reclasificar datos posteriores no cambia sus valores ni su drill-down.
El servidor recalcula al cerrar: ignora cifras calculadas enviadas por el cliente.
El hash se verifica dentro de la transacción, bloqueando cambios concurrentes de fuentes
durante la captura. Cambio de empresa o revocación de REPORT_VIEW invalida solicitudes y UI.

## Límites explícitos de esta versión

- Resultado documental antes de impuesto: no sustituye un cierre contable. Cargas empleador
  faltantes se ingresan manualmente; sueldo neto/SAC informativos no se suman otra vez al bruto.
- Compras manuales sin IVA/neto discriminados bloquean determinación; no se deduce IVA del total.
- Percepciones sin impuesto/jurisdicción fiable requieren resolver clasificación; `otrosTributos`
  no se utiliza como percepción IVA. Ajustes deben representar diferencias, evitando doble conteo.
- Ganancias/Bienes Personales es un auxiliar anual híbrido. No aplica escalas legales ni calcula
  automáticamente el impuesto sobre bienes. Valuaciones ARS y datos anuales los confirma el contador.
- Saldos bancarios son observaciones por cuenta; promedio de observaciones, no promedio diario.
  Orden intradía ambiguo impide primero/último. No hay conciliación ni caja certificada.
- EBITDA, equilibrio, DSO/DPO, ratios corrientes, contexto de mercado y pares permanecen no disponibles.
  Cohorte mínima conceptual 10; ningún endpoint consulta otras organizaciones para benchmarks.
- Volumen real, esquema instalado y rendimiento de DEV no se midieron: el PO prohibió SQL remoto.
  El parser verifica sintaxis, no sustituye ejecución de PostgreSQL con el esquema real.

## Persistencia y seguridad

Migración: [045_management_reporting.sql](../sql/045_management_reporting.sql).
Rollback: [045_management_reporting_down.sql](../sql/045_management_reporting_down.sql).
Harness preparado, NO ejecutado: [045_management_reporting.sql](../tests/db/045_management_reporting.sql).

045 verifica propietario, dependencias, hashes canónicos de contexto/permiso, columnas tipadas,
capacidades activas e instalación parcial. No reemplaza ninguna función ni tasa previa.
RLS habilitada en tablas privadas, sin grants directos a PUBLIC/anon/authenticated.
REPORT_VIEW permite lectura; REPORT_EXPORT exportación; MANUAL_MOVEMENT_EDIT más REPORT_VIEW
permite entradas; revisión/cierre/reapertura requieren además REPORT_EXPORT. No se otorgaron
capacidades nuevas. Lecturas incluyen detalle contable de la empresa activa bajo REPORT_VIEW.

El escritor privilegiado solo admite service_role y vuelve a comprobar permisos/contexto del
subject autenticado. El endpoint verifica el JWT con auth.getUser y obtiene el contexto en servidor;
un navegador no puede elegir actor ni escribir el snapshot calculado. No hay secretos en frontend.
El rollback retira RPCs/vista, conserva tablas y triggers de historia. No es un borrado de datos;
su reinstalación requiere restauración revisada de contratos, no repetir 045 sobre tablas retenidas.

## Dependencia de entorno, preparada sin ejecutar

Se añadió la función Edge `supabase/functions/mica-reporting/index.ts` porque el proyecto estático
no tenía servidor de cálculo compartido. Importa exactamente el motor JS del frontend.
El futuro operador de DEV debe habilitarla con las variables normales del proyecto Supabase
(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`) y definir
`MICA_REPORTING_ALLOWED_ORIGINS` con los orígenes exactos de DEV, separados por comas.
El endpoint rechaza orígenes no incluidos. No incluir URLs PROD ni secretos en el repositorio.
No se ejecutaron comandos de configuración/despliegue. Sin migración y función Edge habilitadas,
los nuevos módulos no pueden operar contra DEV. El proyecto no recibió configuración remota.

## Evidencia local

Comandos utilizados (sin ejecución SQL):

```text
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --roots tests --json --outputFile scratch/management-reporting-tests.json
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand --runTestsByPath tests/reportingEngine.test.js tests/reportingServer.test.js tests/reportingExports.test.js tests/reportingSql.test.js tests/ui/panelGerencial.test.js tests/services/classification039e.test.js tests/ui/moduleAccess039.test.js tests/ui/realDomIntegration.test.js tests/perceptionFileReuse044.test.js
node tests/browser/management-reporting.mjs
git diff --check
```

Suite amplia: 796 aprobadas, 9 fallidas por hashes históricos. Una copia local de git HEAD base
reprodujo los mismos nueve nombres de fallo (734 aprobadas, 9 fallidas en sus archivos disponibles).
El primer archivo afectado, `sql/009_supabase_native_auth.sql`, tiene SHA-256
`56a5716b8b8ae6676a7d50f53a88681b004b656e4c896c98c444fb9f462bd06f` tanto en base como en el
árbol actual; los manifests esperan `74da6cead124530f0f2e38891119d2ee44c5bc43b025125e9905944016e3e708`.
No se alteraron esos manifests ni los SQL históricos para ocultar fallas.
Las pruebas de clasificación ahora cargan Comprobantes/Bancos explícitamente; Gerencia ya no
descarga datasets operativos. Se conservó su cobertura de guardado, readback y contexto.

Pruebas enfocadas: 77 aprobadas en 9 suites (incluye tarjeta/fórmula/trazabilidad de los ocho KPIs).
Parser pglast: 44 sentencias SQL y 10 bloques PL/pgSQL, incluyendo rollback/harness; sin ejecutarlos.
Node verifica sintaxis JS y el entrypoint TypeScript con strip-types.
Edge headless local: cinco vistas, ocho KPIs, vista previa IVA, seis formularios, cierre y detalle
inmutables tras cambio de fuente, revocación y ausencia de overflow a 390 px. Servicio sintético
inyectado y módulo Supabase sustituido por stub; ningún SQL ni llamada remota.
Capturas locales: `scratch/reporting-desktop.png`, `scratch/reporting-mobile.png`,
`scratch/management-mobile.png`. No forman parte del despliegue.

## Aceptación manual DEV pendiente

Solo después de autorización operativa posterior y aplicación humana de 045 / habilitación Edge:

1. Ejecutar el harness preparado en DEV como su propietario privilegiado; debe terminar en ROLLBACK,
   rechazando org arbitraria, anon, escritor directo y modificación de historia.
2. Con dos empresas reales de prueba, alternar contexto con una solicitud pendiente: borrar cifras
   anteriores y verificar que detalle/exportación pertenecen a la empresa activa.
3. Usar factura + NC y nómina: NC resta, banco no duplica ventas, categorías provienen de IDs;
   cargas faltantes y monedas no soportadas aparecen como no disponible.
4. Configurar Apertura IVA y dos meses: comprobar técnico/LD/compensación/arrastre con fuentes previas;
   probar compensación excesiva y tasa IIBB ambigua, ambas deben impedir determinación/cierre.
5. Configurar LOCAL y CM con dos actividades/provincias y coeficientes anuales distintos; revisar
   tasa vigente, base, coeficiente, créditos y saldos en XLSX. Coeficientes deben sumar 1.
6. Cerrar un reporte, reclasificar una fuente y volver a abrir vista previa/exportación: conservar
   la versión cerrada y sus IDs; reapertura expresa deja un evento y permite una versión nueva.

Preparado para revisión/aplicación manual de migración DEV. Despliegue funcional condicionado a
esa instalación, configuración de Edge y aceptación runtime. No se certifica DEV_RUNTIME_VERIFIED.
