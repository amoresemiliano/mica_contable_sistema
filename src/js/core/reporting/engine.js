// Canonical calculation layer, shared by the browser and the trusted Edge service.
// Monetary inputs/outputs are integer ARS cents. No exchange rates or statutory scales inferred.
export const ENGINE_VERSION = 'management-v1';
export const MIN_BENCHMARK_COHORT = 10;
export const REPORT_TYPES = ['IVA','IIBB','RESULTADOS','GANANCIAS'];
const integer = n => Number.isSafeInteger(n);
const cents = n => { if (!integer(n)) throw new Error('Importe fuera del rango seguro de centavos.'); return n; };
const add = values => values.reduce((a,b) => cents(a+cents(b)),0);
const percent = (n,d) => d ? n/d*100 : null;
export const change = (current,previous) => current == null || previous == null || previous===0 ? null : (current-previous)/Math.abs(previous)*100;
const sum = (rows,key) => add(rows.map(r=>r[key]??0));
const ars = r => r.currency==='PES' || r.currency==='ARS';
const rateAmount = (base,rate,coefficient=1) => {
 cents(base);
 if(!Number.isFinite(Number(rate))||Number(rate)<0||!Number.isFinite(coefficient)||coefficient<0)throw new Error('Tasa/coeficiente inválido.');
 const numerator=BigInt(base)*BigInt(Math.round(Number(rate)*100))*BigInt(Math.round(coefficient*1000000));
 const denominator=10000000000n,absolute=numerator<0n?-numerator:numerator;
 const rounded=(absolute+denominator/2n)/denominator;
 return cents(Number(numerator<0n?-rounded:rounded));
};
const monthPattern = /^\d{4}-(0[1-9]|1[0-2])$/;
export function monthsBetween(from,to) {
 const valid=s=>/^\d{4}-\d{2}-\d{2}$/.test(s)&&!Number.isNaN(Date.parse(`${s}T00:00:00Z`))&&new Date(`${s}T00:00:00Z`).toISOString().slice(0,10)===s;
 if (!valid(from)||!valid(to)||from>to) throw new Error('Período inválido.');
 const result=[]; let month=from.slice(0,7);
 while(month<=to.slice(0,7)) { result.push(month); const [y,m]=month.split('-').map(Number); month=`${y+(m===12?1:0)}-${String(m===12?1:m+1).padStart(2,'0')}`; if(result.length>36) throw new Error('Máximo 36 meses.'); }
 return result;
}
const latest = (data,kind,period) => data.inputs.find(i=>i.kind===kind && i.period===period);
const payload = (data,kind,period) => latest(data,kind,period)?.payload;
const ref = (r,field) => ({ source_type:r.source_type,count:r.count,field,filter:{month:r.month,kind:r.kind,category_id:r.category_id??null,activity_id:r.activity_id??null,supplier:r.supplier??null,currency:r.currency,...(r.tax_type?{tax_type:r.tax_type}:{}),...(r.tax_kind?{tax_kind:r.tax_kind}:{}),...(r.jurisdiction?{jurisdiction:r.jurisdiction}:{})} });
const manualRef = i => i ? {source_type:'manual_input',id:i.id,user:i.created_by,timestamp:i.created_at,note:i.note,kind:i.kind,period:i.period,revision:i.revision,count:1} : null;
function line(code,label,value,formula,rows=[],field='net',missing=[],manual=[]) {
 if(value!=null)cents(value);
 return {code,label,value:missing.length?null:value,formula,source_count:rows.reduce((n,r)=>n+r.count,0),sources:rows.map(r=>ref(r,field)),manual:manual.map(manualRef).filter(Boolean),missing:[...new Set(missing)]};
}
export const ALERT_DEFAULTS = Object.freeze({
 SALES_DROP:{category:'FINANCIAL',severity:'WARNING',threshold:15,mode:'previous'},
 EXPENSE_GROWTH:{category:'OPERATING',severity:'WARNING',threshold:20,mode:'previous'},
 NEGATIVE_RESULT:{category:'FINANCIAL',severity:'CRITICAL',threshold:0,mode:'absolute'},
 TWO_NEGATIVE_MONTHS:{category:'FINANCIAL',severity:'CRITICAL',threshold:0,mode:'previous'},
 PAYROLL_SHARE:{category:'OPERATING',severity:'WARNING',threshold:35,mode:'absolute'},
 FISCAL_SPIKE:{category:'FISCAL',severity:'WARNING',threshold:30,mode:'historical'},
 BANK_BALANCE_DROP:{category:'FINANCIAL',severity:'WARNING',threshold:25,mode:'previous'},
 LARGE_UNCLASSIFIED_BANK:{category:'DATA QUALITY',severity:'WARNING',threshold:10000000,mode:'absolute'},
 CLASSIFICATION_COVERAGE:{category:'DATA QUALITY',severity:'WARNING',threshold:80,mode:'absolute'},
 IMPORT_ISSUES:{category:'DATA QUALITY',severity:'WARNING',threshold:0,mode:'absolute'},
 RECORD_ANOMALIES:{category:'DATA QUALITY',severity:'WARNING',threshold:0,mode:'absolute'},
 MARGIN_IMPROVING:{category:'POSITIVE SIGNAL',severity:'POSITIVE',threshold:5,mode:'previous'},
 RECORD_SALES:{category:'POSITIVE SIGNAL',severity:'POSITIVE',threshold:0,mode:'historical'}
});
export const ALERT_LABELS={SALES_DROP:'Caída de ventas',EXPENSE_GROWTH:'Aumento de compras',NEGATIVE_RESULT:'Resultado negativo',TWO_NEGATIVE_MONTHS:'Dos meses negativos',PAYROLL_SHARE:'Personal / ventas',FISCAL_SPIKE:'IVA sobre promedio',BANK_BALANCE_DROP:'Caída del saldo observado',LARGE_UNCLASSIFIED_BANK:'Movimiento grande sin clasificar',CLASSIFICATION_COVERAGE:'Cobertura de clasificación',IMPORT_ISSUES:'Incidencias registradas',RECORD_ANOMALIES:'Anomalías documentales',MARGIN_IMPROVING:'Mejora de margen',RECORD_SALES:'Máximo de ventas'};
export const alertMoneyThreshold=code=>['NEGATIVE_RESULT','TWO_NEGATIVE_MONTHS','LARGE_UNCLASSIFIED_BANK'].includes(code);
export function validateInput(kind,period,p) {
 if (!p || typeof p!=='object'||Array.isArray(p)) throw new Error('Datos inválidos.');
 const keys={IVA_OPENING:['technical','free'],PERIOD_ADJUSTMENT:['employer_contributions','other_income','other_expense','iva_retention','iva_perception','iva_ld_adjustment','iva_compensation','iibb','payroll_not_applicable'],IIBB_CONFIG:['regime','jurisdiction'],CM_COEFFICIENTS:['rows'],ANNUAL_TAX:['rows','confirmed','tax_determined','payments','retentions','prior','opening_equity','consumed'],ALERT_SETTINGS:['rules']};
 if(!keys[kind]||Object.keys(p).some(k=>!keys[kind].includes(k)))throw new Error('Campo manual no admitido.');
 const moneyFields = fields => fields.forEach(k=>{if(p[k]!=null)cents(p[k]);});
 if (['IVA_OPENING','PERIOD_ADJUSTMENT'].includes(kind) && !monthPattern.test(period)) throw new Error('Elegí un mes.');
 if (['CM_COEFFICIENTS','ANNUAL_TAX','IIBB_CONFIG','ALERT_SETTINGS'].includes(kind) && !/^\d{4}$/.test(period)) throw new Error('Elegí un año.');
 if(kind==='IVA_OPENING') { moneyFields(['technical','free']); if(!integer(p.technical)||!integer(p.free)||p.technical<0||p.free<0)throw new Error('Completá ambos saldos iniciales no negativos.'); }
 else if(kind==='PERIOD_ADJUSTMENT') {
  moneyFields(['employer_contributions','other_income','other_expense','iva_retention','iva_perception','iva_ld_adjustment','iva_compensation']);
  for(const k of ['employer_contributions','other_income','other_expense','iva_retention','iva_perception','iva_compensation']) if((p[k]??0)<0)throw new Error('Importe negativo no permitido.');
  if(p.iibb!=null && !Array.isArray(p.iibb))throw new Error('Ajustes IIBB inválidos.');
  if(p.payroll_not_applicable!=null&&typeof p.payroll_not_applicable!=='boolean')throw new Error('Confirmación de nómina inválida.');
  if(new Set((p.iibb||[]).map(r=>r.jurisdiction)).size!==(p.iibb||[]).length)throw new Error('No repitas jurisdicciones IIBB.');
  for(const r of p.iibb||[]) {if(!r.jurisdiction)throw new Error('Falta jurisdicción IIBB.'); for(const k of ['retention','perception','bank_retention','prior','interest','adjustment'])cents(r[k]??0);}
 }
 else if(kind==='IIBB_CONFIG') { if(!['LOCAL','CONVENIO_MULTILATERAL'].includes(p.regime)||(p.regime==='LOCAL'&&!p.jurisdiction))throw new Error('Configurá régimen y jurisdicción.'); }
 else if(kind==='CM_COEFFICIENTS') {
  if(!Array.isArray(p.rows)||!p.rows.length||new Set(p.rows.map(r=>r.jurisdiction)).size!==p.rows.length)throw new Error('Jurisdicciones únicas requeridas.');
  if(p.rows.some(r=>!r.jurisdiction||!Number.isFinite(r.coefficient)||r.coefficient<0||r.coefficient>1||Math.abs(r.coefficient*1000000-Math.round(r.coefficient*1000000))>0.000001)||Math.abs(p.rows.reduce((n,r)=>n+r.coefficient,0)-1)>0.000001)throw new Error('Los coeficientes deben sumar 1 (hasta 6 decimales).');
 }
 else if(kind==='ANNUAL_TAX') {
  if(!Array.isArray(p.rows)||typeof p.confirmed!=='boolean')throw new Error('Datos anuales inválidos.');
  for(const r of p.rows){if(!['income','deduction','asset','liability','adjustment'].includes(r.family)||!r.code||!r.category||!r.currency)throw new Error('Completá familia, concepto, categoría y moneda.');if(r.family==='income'&&!['TAXED','EXEMPT'].includes(r.code))throw new Error('Clasificá renta como TAXED o EXEMPT.');cents(r.amount);if(r.family!=='adjustment'&&r.amount<0)throw new Error('Valuación/importe anual negativo no permitido.'); if(r.original_amount!=null)cents(r.original_amount);}
  moneyFields(['tax_determined','payments','retentions','prior','opening_equity','consumed']);
 }
 else if(kind==='ALERT_SETTINGS') {
  if(!p.rules||typeof p.rules!=='object')throw new Error('Reglas inválidas.');
  for(const [code,r] of Object.entries(p.rules)){if(!ALERT_DEFAULTS[code]||typeof r.enabled!=='boolean'||!Number.isFinite(r.threshold)||r.threshold<0||!['INFO','WARNING','CRITICAL','POSITIVE'].includes(r.severity)||!['previous','historical','absolute'].includes(r.mode))throw new Error('Configuración de alerta inválida.');}
 } else throw new Error('Tipo de entrada desconocido.');
 return p;
}
function validateData(data) {
 if(!data?.organization_id||!Array.isArray(data.groups)||!Array.isArray(data.inputs))throw new Error('Contrato de reportes inválido.');
 for(const r of data.groups){if(!integer(Number(r.count))||Number(r.count)<1)throw new Error('Cantidad inválida.');r.count=Number(r.count); for(const k of ['net','taxable','vat','amount','credit_notes','credit_notes_net','salary_net','sac','income','outflow','largest_unclassified']) if(r[k]!=null)r[k]=cents(Number(r[k]));}
 for(const i of data.inputs){if(i.organization_id!==data.organization_id)throw new Error('Entrada de otra organización.');validateInput(i.kind,i.period,i.payload);}
 for(const a of data.accounts||[])for(const k of ['first','last','minimum','maximum','average'])if(a[k]!=null)a[k]=cents(Number(a[k]));
}
function resultMonth(data,month) {
 const rows=data.groups.filter(r=>r.month===month), used=rows.filter(ars), sales=used.filter(r=>r.kind==='SALES'), purchases=used.filter(r=>r.kind==='PURCHASES'), payroll=used.filter(r=>r.kind==='PAYROLL');
 const adjust=latest(data,'PERIOD_ADJUSTMENT',month), a=adjust?.payload||{};
 const missing=rows.some(r=>!ars(r))?['Hay importes en moneda extranjera sin política de conversión validada.']:[];
 const metric=(code,label,rs,field='net',extra=0)=>line(code,label,add([sum(rs,field),extra]),`SUM(${field}) ${extra?'+ ajuste manual':''}`,rs,field,[...missing,...(!rs.length&&!['other_income','other_expense'].includes(code)?['No hay datos suficientes para calcular este indicador.']:[]),...(rs.some(r=>(field==='net'&&r.missing_net)||(field==='amount'&&r.missing_amount)||(['salary_net','sac','taxable'].includes(field)&&r[field]==null)||(['income','outflow'].includes(field)&&r.missing_amount))?['Faltan importes canónicos.']:[])],extra?[adjust]:[]);
 const salesLine=metric('sales','Ventas netas documentales',sales), purchaseLine=metric('purchases','Compras netas documentales',purchases), grossPayroll=metric('payroll','Remuneración bruta importada',payroll);
 if(!payroll.length&&a.payroll_not_applicable){grossPayroll.value=0;grossPayroll.missing=[];grossPayroll.manual=[manualRef(adjust)];}
 const manualPurchase=used.filter(r=>r.kind==='MANUAL_PURCHASE');
 const incomeRows=used.filter(r=>r.kind==='OTHER_INCOME'),expenseRows=used.filter(r=>r.kind==='OTHER_EXPENSE');
 const otherIncome=metric('other_income','Otros ingresos',incomeRows,'amount',a.other_income??0),otherExpense=metric('other_expense','Otros egresos',expenseRows,'amount',a.other_expense??0);
 const resultMissing=[...salesLine.missing,...purchaseLine.missing,...grossPayroll.missing,...otherIncome.missing,...otherExpense.missing];
 if(a.employer_contributions==null)resultMissing.push('Faltan cargas empleador del período (ingresá 0 si corresponde).');
 if(manualPurchase.length)resultMissing.push('Compras manuales sin neto/IVA discriminado.');
 const result=line('result','Resultado documental antes de impuesto',add([salesLine.value??0,-(purchaseLine.value??0),-(grossPayroll.value??0),-(a.employer_contributions??0),otherIncome.value??0,-(otherExpense.value??0)]),
  'Ventas netas − compras netas − remuneración bruta − cargas manuales + otros ingresos − otros egresos',[...sales,...purchases,...payroll,...incomeRows,...expenseRows],'net',resultMissing,[adjust]);
 const grossSales=line('gross_sales','Ventas antes de notas de crédito',sum(sales,'net')-sum(sales,'credit_notes_net'),'Ventas netas − neto firmado de NC',sales,'net',salesLine.missing);
 const lines=[salesLine,grossSales,metric('credit_notes','Notas de crédito (total comprobantes)',sales,'credit_notes'),
  metric('taxable_sales','Ventas gravadas',sales,'taxable'),line('untaxed_sales','Ventas no gravadas / exentas',sum(sales,'net')-sum(sales,'taxable'),'Ventas netas − gravadas',sales,'net',salesLine.missing),purchaseLine,grossPayroll,
  metric('salary_net','Sueldos netos',payroll,'salary_net'),metric('sac','SAC importado',payroll,'sac'),line('employer_contributions','Cargas empleador ingresadas',a.employer_contributions??null,'Entrada manual',[],'amount',a.employer_contributions==null?['Faltan cargas empleador del período.']:[],[adjust]),otherIncome,otherExpense,result];
 const banks=used.filter(r=>r.kind==='BANK');
 lines.push(metric('bank_flow','Flujo bancario neto',banks,'amount'),metric('bank_income','Ingresos bancarios',banks,'income'),metric('bank_outflow','Egresos bancarios',banks,'outflow'));
 for(const category of new Set(purchases.map(r=>r.category_id??null))){
  const members=purchases.filter(r=>(r.category_id??null)===category),name=data.categories.find(c=>c.id===category)?.name||'Sin clasificar';
  const categoryLine=metric(`expense_category_${category||'unclassified'}`,`Compras · ${name}`,members);
  categoryLine.category_id=category;lines.push(categoryLine);
 }
 return {month,lines,sales:salesLine.value,result:result.value,purchases:purchaseLine.value,payroll:grossPayroll.value,margin:result.value!=null?percent(result.value,salesLine.value):null,
  expense_share:purchaseLine.value!=null?percent(purchaseLine.value,salesLine.value):null,payroll_share:grossPayroll.value!=null?percent(grossPayroll.value,salesLine.value):null,
  bank_flow:lines.find(l=>l.code==='bank_flow').value,classified_count:purchases.filter(r=>r.category_id).reduce((n,r)=>n+r.count,0),purchase_count:purchases.reduce((n,r)=>n+r.count,0)};
}
export function ivaEngine(data) {
 const months=monthsBetween(data.date_from,data.date_to), opening=data.inputs.filter(i=>i.kind==='IVA_OPENING'&&i.period<=months[0]).sort((a,b)=>b.period.localeCompare(a.period))[0];
 let technical=opening?.payload.technical??null,free=opening?.payload.free??null;
 let technicalRows=[],freeRows=[],technicalManual=opening?[opening]:[],freeManual=opening?[opening]:[];
 const result=[];
 if(opening && opening.period<months[0]) { // Caller must include every intervening month in the aggregate range.
  technical=null;free=null;
 }
 for(const month of months) {
  const localOpening=latest(data,'IVA_OPENING',month);
  if(localOpening){technical=localOpening.payload.technical;free=localOpening.payload.free;technicalRows=[];freeRows=[];technicalManual=[localOpening];freeManual=[localOpening];}
  const rows=data.groups.filter(r=>r.month===month),sales=rows.filter(r=>r.kind==='SALES'&&ars(r)),purchases=rows.filter(r=>r.kind==='PURCHASES'&&ars(r));
  const tax=rows.filter(r=>r.kind==='TAX'&&r.tax_type==='IVA'),ret=tax.filter(r=>r.tax_kind==='retencion'),per=tax.filter(r=>r.tax_kind==='percepcion');
  const adjustment=latest(data,'PERIOD_ADJUSTMENT',month),a=adjustment?.payload||{};
  const missing=[];
  if(technical==null||free==null)missing.push('Falta configurar Apertura IVA o incluir todos los meses desde la apertura.');
  if(!sales.length&&!purchases.length)missing.push('No hay comprobantes fiscales importados en este mes.');
  if(rows.some(r=>r.missing_vat && ['SALES','PURCHASES','MANUAL_PURCHASE'].includes(r.kind)))missing.push('Hay comprobantes sin IVA discriminado.');
  if(rows.some(r=>!ars(r)))missing.push('Moneda extranjera pendiente de conversión.');
  const cf=sum(purchases,'vat'),df=sum(sales,'vat'),net=df-cf,previousTechnical=technical,previousFree=free;
  const periodTechnical=technical==null?null:net-technical,available=free==null?null:add([free,sum(ret,'amount'),sum(per,'amount'),a.iva_retention??0,a.iva_perception??0,a.iva_ld_adjustment??0]);
  if(tax.some(r=>!['retencion','percepcion'].includes(r.tax_kind)))missing.push('Hay registros IVA sin tipo retención/percepción confiable.');
  if(rows.some(r=>r.kind==='TAX'&&!r.tax_type))missing.push('Hay registros fiscales sin impuesto identificado; falta resolver su clasificación.');
  const compensation=a.iva_compensation??0;
  if(available!=null&&(available<0||compensation>Math.min(Math.max(0,periodTechnical),available)))missing.push('Compensación IVA excede deuda o LD disponible.');
  technical=missing.length?null:Math.max(0,-periodTechnical);free=missing.length?null:available-compensation;
  const payable=missing.length?null:Math.max(0,periodTechnical)-compensation;
  const make=(code,label,value,formula,rs=[],field='amount',manual=[])=>line(code,label,value,formula,rs,field,missing,manual);
  result.push({month,technical,free,payable,lines:[
   line('iva_cf','IVA CF',cf,'SUM(IVA compras firmado)',purchases,'vat',missing.filter(m=>!m.includes('Apertura'))),
   line('iva_df','IVA DF',df,'SUM(IVA ventas firmado)',sales,'vat',missing.filter(m=>!m.includes('Apertura'))),
   make('technical','Saldo técnico',net,'DF − CF',[...sales,...purchases],'vat'),
   make('technical_prior','Saldo técnico anterior',previousTechnical,'Apertura o arrastre previo',technicalRows,'vat',technicalManual),
   make('technical_period','Saldo técnico del período',periodTechnical,'DF − CF − saldo técnico anterior',[...technicalRows,...sales,...purchases],'vat',technicalManual),
   make('technical_next','Saldo técnico a favor siguiente',technical,'MAX(0, − saldo técnico del período)',[...technicalRows,...sales,...purchases],'vat',technicalManual),
   make('free_prior','Saldo a favor LD anterior',previousFree,'Apertura o arrastre previo',freeRows,'amount',freeManual),
   make('retentions','Retenciones',sum(ret,'amount')+(a.iva_retention??0),'Importadas IVA + ajuste manual',ret,'amount',[adjustment]),
   make('perceptions','Percepciones',sum(per,'amount')+(a.iva_perception??0),'Importadas IVA + ajuste manual',per,'amount',[adjustment]),
   make('ld_adjustment','Ajuste LD',a.iva_ld_adjustment??0,'Entrada manual',[],'amount',[adjustment]),
   make('compensation','Compensación carga manual',compensation,'Instrucción manual limitada a deuda y LD',[],'amount',[adjustment]),
   make('free_next','Saldo a favor LD',free,'LD previo + retenciones + percepciones + ajuste − compensación',[...freeRows,...tax],'amount',[...freeManual,adjustment]),
   make('iva_payable','IVA estimado a pagar',payable,'MAX(0, saldo técnico del período) − compensación',[...technicalRows,...freeRows,...sales,...purchases,...tax],'vat',[...technicalManual,...freeManual,adjustment])],missing});
  technicalRows=[...technicalRows,...sales,...purchases];freeRows=[...freeRows,...tax];
  if(adjustment)freeManual.push(adjustment);
 }
 return result;
}
export function iibbEngine(data) {
 return monthsBetween(data.date_from,data.date_to).map(month=>{
  const year=month.slice(0,4),config=latest(data,'IIBB_CONFIG',year),coeff=latest(data,'CM_COEFFICIENTS',year),adjustment=latest(data,'PERIOD_ADJUSTMENT',month),rows=data.groups.filter(r=>r.month===month);
  const regime=config?.payload.regime,jurisdictions=regime==='LOCAL'?[{jurisdiction:config.payload.jurisdiction,coefficient:1}]:(coeff?.payload.rows||[]),missing=[];
  if(!regime)missing.push('Falta configurar régimen IIBB.');
  if(rows.some(r=>r.kind==='TAX'&&!r.tax_type))missing.push('Hay registros fiscales sin impuesto identificado; falta resolver su clasificación.');
  if(regime==='CONVENIO_MULTILATERAL'&&!jurisdictions.length)missing.push(`Faltan coeficientes CM ${year}.`);
  const sales=rows.filter(r=>r.kind==='SALES'),lines=[];
  if(!sales.length)missing.push('No hay ventas importadas para estimar IIBB.');
  if(sales.some(r=>!r.activity_id||r.net==null||r.missing_net||!ars(r)))missing.push('Ventas sin actividad/base o con moneda pendiente de conversión.');
  for(const j of jurisdictions){
   const jurisdictionMissing=[...missing];let determined=0;
   for(const sale of sales){
    const rates=(sale.rates||[]).filter(r=>r.jurisdiction===j.jurisdiction&&r.activity_id===sale.activity_id);
    if(rates.length!==1){jurisdictionMissing.push(`Falta tasa única vigente para ${sale.activity_id||'actividad sin asignar'} / ${j.jurisdiction}.`);continue;}
    const base=rateAmount(sale.net??0,100,j.coefficient),amount=rateAmount(sale.net??0,Number(rates[0].rate),j.coefficient);determined=add([determined,amount]);
    lines.push({...line('iibb_activity','Base / impuesto por actividad',amount,'Base documental × coeficiente anual × alícuota vigente / 100',[sale],'net',jurisdictionMissing,[config,coeff]),jurisdiction:j.jurisdiction,activity_id:sale.activity_id,activity_name:data.activities.find(a=>a.id===sale.activity_id)?.name||sale.activity_id,base,coefficient:j.coefficient,rate:Number(rates[0].rate),rate_id:rates[0].id});
   }
   const tax=rows.filter(r=>r.kind==='TAX'&&r.tax_type==='IIBB'&&r.jurisdiction===j.jurisdiction),a=(adjustment?.payload.iibb||[]).find(r=>r.jurisdiction===j.jurisdiction)||{};
   const retention=sum(tax.filter(r=>r.tax_kind==='retencion'),'amount')+(a.retention??0),perception=sum(tax.filter(r=>r.tax_kind==='percepcion'),'amount')+(a.perception??0),bank=a.bank_retention??0;
   const net=add([determined,-retention,-perception,-bank,-(a.prior??0),a.interest??0,a.adjustment??0]);
   for(const [code,label,value,formula] of [['base','Base imponible documental',sum(sales.filter(ars),'net')*j.coefficient,'Ventas netas × coeficiente'],['determined','Impuesto determinado estimado',determined,'SUM(impuesto por actividad/tasa)'],['retentions','Retenciones',retention,'Retenciones identificadas + manual'],['perceptions','Percepciones',perception,'Percepciones identificadas + manual'],['bank_retention','Retenciones bancarias',bank,'Entrada manual'],['prior','Saldo anterior a favor',a.prior??0,'Entrada manual'],['interest','Interés',a.interest??0,'Entrada manual'],['adjustment','Ajustes',a.adjustment??0,'Entrada manual'],['iibb_payable','Total estimado a pagar',Math.max(0,net),'MAX(0, determinado − créditos − saldo anterior + interés + ajustes)'],['iibb_credit','Saldo a favor siguiente',Math.max(0,-net),'MAX(0, − saldo neto)']]){
    lines.push({...line(code,label,Math.round(value),formula,[...sales,...tax],'amount',jurisdictionMissing,[config,coeff,adjustment]),jurisdiction:j.jurisdiction});
   }
  }
  return {month,regime,lines,missing:[...new Set([...missing,...lines.flatMap(l=>l.missing)])],payable:missing.length||lines.some(l=>l.missing.length)?null:sum(lines.filter(l=>l.code==='iibb_payable'),'value')};
 });
}
export function annualEngine(data,year) {
 const entry=latest(data,'ANNUAL_TAX',year),p=entry?.payload,rows=p?.rows||[],missing=p?.confirmed?[]:['Este reporte requiere completar y confirmar Datos fiscales anuales.'];
 const total=(family,code)=>add(rows.filter(r=>r.family===family&&(!code||r.code===code)).map(r=>r.amount));
 const income=total('income','TAXED'),deductions=total('deduction'),base=income-deductions,assets=total('asset'),liabilities=total('liability');
 const previous=payload(data,'ANNUAL_TAX',String(Number(year)-1));
 const previousEquity=previous?.confirmed?add(previous.rows.filter(r=>r.family==='asset').map(r=>r.amount))-add(previous.rows.filter(r=>r.family==='liability').map(r=>r.amount)):null;
 const make=(code,label,value,formula,extra=[])=>line(code,label,value,formula,[],'amount',[...missing,...extra],[entry]);
 const lines=rows.map((r,index)=>({...make(`annual_${index}`,`${r.category}: ${r.description||r.code}`,r.amount,'Valuación / importe ARS ingresado manualmente'),family:r.family,currency:r.currency,original_amount:r.original_amount,category:r.category}));
 const determined=p?.tax_determined??null;
 lines.push(make('annual_taxed','Ingresos gravados',income,'SUM(rentas clasificadas gravadas)'),make('annual_exempt','Resultado exento',total('income','EXEMPT'),'SUM(rentas clasificadas exentas)'),
  make('annual_deductions','Deducciones admitidas/personales/quebrantos',deductions,'SUM(deducciones anuales ingresadas)'),make('annual_base','Ganancia neta sujeta a impuesto (auxiliar)',Math.max(0,base),'MAX(0, ingresos gravados − deducciones)'),
  make('annual_determined','Impuesto determinado por contador',determined,'Entrada manual; no se aplica escala legal',determined==null?['Falta impuesto determinado por contador.']:[]),
  make('annual_payable','Impuesto a ingresar',determined==null?null:Math.max(0,determined-(p.payments??0)-(p.retentions??0)-(p.prior??0)),'MAX(0, determinado − pagos − retenciones − saldo anterior)',determined==null?['Falta impuesto determinado.']:[]),
  make('annual_assets','Total bienes (valuación ARS)',assets,'SUM(valuaciones ARS de bienes)'),make('annual_liabilities','Total deudas (ARS)',liabilities,'SUM(deudas ARS)'),
  make('annual_equity','Patrimonio neto final',assets-liabilities,'Bienes − deudas'),make('annual_prior_equity','Patrimonio neto anterior',previousEquity,'Datos anuales confirmados del año anterior',previousEquity==null?['Faltan datos del año anterior.']:[]),
  make('annual_equity_change','Variación patrimonial',previousEquity==null?null:assets-liabilities-previousEquity,'Patrimonio final − patrimonio anterior',previousEquity==null?['Faltan datos del año anterior.']:[]),
  make('annual_consumed','Monto consumido',p?.consumed??null,'Entrada manual',p?.consumed==null?['Falta monto consumido.']:[]),
  make('annual_justification_difference','Diferencia de justificación patrimonial',p?.opening_equity==null||p?.consumed==null?null:assets-liabilities-p.opening_equity+p.consumed-income-total('income','EXEMPT')-total('adjustment'),
   'Patrimonio final − inicial + consumido − ingresos gravados − exentos − cambios patrimoniales ingresados',p?.opening_equity==null||p?.consumed==null?['Faltan patrimonio inicial y/o monto consumido.']:[]));
 return {year,lines,missing,previous_year:String(Number(year)-1)};
}
export function alertEngine(model,settings={rules:{}}) {
 const alerts=[],monthly=model.monthly,current=monthly.at(-1),previous=monthly.at(-2);if(!current)return alerts;
 const historical=monthly.slice(0,-1),mean=key=>{const v=historical.map(m=>m[key]).filter(v=>v!=null);return v.length?v.reduce((a,b)=>a+b,0)/v.length:null;};
 const emit=(code,title,value,comparison,why,source,trigger)=>{const rule={...ALERT_DEFAULTS[code],enabled:true,...settings.rules?.[code]};const unit=['PAYROLL_SHARE','CLASSIFICATION_COVERAGE','MARGIN_IMPROVING'].includes(code)?'percent':['IMPORT_ISSUES','RECORD_ANOMALIES'].includes(code)?'count':'money';if(rule.enabled&&trigger(rule))alerts.push({code,title,...rule,unit,threshold_unit:alertMoneyThreshold(code)?'money':['IMPORT_ISSUES','RECORD_ANOMALIES'].includes(code)?'count':'percent',current_value:value,comparison_value:comparison,explanation:why,why,source});};
 const compare=(code,key)=>({...ALERT_DEFAULTS[code],...settings.rules?.[code]}).mode==='historical'?mean(key):previous?.[key];
 const salesComparison=compare('SALES_DROP','sales'),expenseComparison=compare('EXPENSE_GROWTH','purchases');
 emit('SALES_DROP','Las ventas disminuyeron',current.sales,salesComparison,'La variación de ventas supera el umbral de caída.','sales',r=>change(current.sales,salesComparison)!=null&&change(current.sales,salesComparison)<-r.threshold);
 emit('EXPENSE_GROWTH','Aumentaron las compras',current.purchases,expenseComparison,'El crecimiento de compras supera el umbral configurado.','purchases',r=>change(current.purchases,expenseComparison)>r.threshold);
 emit('NEGATIVE_RESULT','Resultado documental negativo',current.result,0,'El resultado documental del mes es negativo.','result',r=>current.result!=null&&current.result< -r.threshold);
 emit('TWO_NEGATIVE_MONTHS','Dos meses con resultado negativo',current.result,previous?.result,'El mes actual y el anterior muestran pérdida documental.','result',()=>current.result<0&&previous?.result<0);
 emit('PAYROLL_SHARE','Participación de personal elevada',current.payroll_share,previous?.payroll_share,'Remuneración bruta / ventas supera el umbral; faltan cargas si no se ingresaron.','payroll',r=>current.payroll_share!=null&&current.payroll_share>r.threshold);
 const fiscal=model.iva.at(-1)?.payable,historyFiscal=model.iva.slice(0,-1).map(r=>r.payable).filter(v=>v!=null),fiscalAverage=historyFiscal.length?historyFiscal.reduce((a,b)=>a+b,0)/historyFiscal.length:null;
 emit('FISCAL_SPIKE','IVA superior al promedio reciente',fiscal,fiscalAverage,'IVA estimado a pagar supera el promedio de meses disponibles.','iva_payable',r=>change(fiscal,fiscalAverage)>r.threshold);
 const balances=model.accounts.filter(a=>a.first!=null&&a.last!=null),first=balances.length?sum(balances,'first'):null,last=balances.length?sum(balances,'last'):null;
 emit('BANK_BALANCE_DROP','Caída de saldos bancarios observados',last,first,'Variación entre primeras y últimas observaciones disponibles; no es saldo actual certificado.','bank_flow',r=>change(last,first)!=null&&change(last,first)<-r.threshold);
 const large=Math.max(0,...model.groups.filter(r=>r.kind==='BANK'&&!r.category_id).map(r=>r.largest_unclassified??0));
 emit('LARGE_UNCLASSIFIED_BANK','Movimiento bancario grande sin clasificar',large,null,'El mayor movimiento sin categoría supera el umbral monetario en centavos.','bank_flow',r=>large>r.threshold);
 const coverage=percent(current.classified_count,current.purchase_count);
 emit('CLASSIFICATION_COVERAGE','Cobertura de clasificación baja',coverage,null,'Porcentaje de comprobantes de compras con categoría persistida.','purchases',r=>coverage!=null&&coverage<r.threshold);
 emit('IMPORT_ISSUES','Incidencias de importación registradas',model.quality.import_issues,null,'Incidencias registradas en el rango; no implica que todas sigan pendientes.','quality',r=>model.quality.import_issues>r.threshold);
 const anomalies=(model.quality.excluded_amendments??0)+(model.quality.undated??0)+model.groups.filter(r=>!ars(r)||r.missing_net||r.missing_amount).reduce((n,r)=>n+r.count,0);
 emit('RECORD_ANOMALIES','Datos que requieren revisión',anomalies,null,'Enmiendas excluidas, registros sin fecha, importes faltantes o moneda pendiente.','anomalies',r=>anomalies>r.threshold);
 emit('MARGIN_IMPROVING','Mejora del margen documental',current.margin,previous?.margin,'El margen creció por encima del umbral en puntos porcentuales.','result',r=>current.margin!=null&&previous?.margin!=null&&current.margin-previous.margin>r.threshold);
 const max=historical.length?Math.max(...historical.map(m=>m.sales??-Infinity)):null;
 emit('RECORD_SALES','Máximo de ventas en el rango',current.sales,max,'Ventas del mes por encima del máximo de meses anteriores del rango disponible.','sales',r=>max!=null&&current.sales!=null&&current.sales>max*(1+r.threshold/100));
 return alerts;
}
export function buildModel(input) {
 const data=structuredClone(input);validateData(data);
 const monthly=monthsBetween(data.date_from,data.date_to).map(m=>resultMonth(data,m));
 const model={...data,engine_version:ENGINE_VERSION,monthly,iva:ivaEngine(data),iibb:iibbEngine(data)};
 model.annual=annualEngine(data,data.date_to.slice(0,4));
 for(const [code,label] of [['result','Resultado documental acumulado (auxiliar)'],['payroll','Remuneración bruta importada (auxiliar)'],['sac','SAC importado (auxiliar)']]){
  const lines=monthly.filter(m=>m.month.startsWith(data.date_to.slice(0,4))).map(m=>m.lines.find(l=>l.code===code));
  model.annual.lines.push({code:`annual_auto_${code}`,label,value:lines.some(l=>l.value==null)?null:add(lines.map(l=>l.value)),formula:'SUM(datos documentales del ejercicio disponibles); no asigna categoría de renta ni reemplaza datos anuales',source_count:lines.reduce((n,l)=>n+l.source_count,0),sources:lines.flatMap(l=>l.sources),manual:lines.flatMap(l=>l.manual),missing:[]});
 }
 model.alerts=alertEngine(model,payload(data,'ALERT_SETTINGS',data.date_to.slice(0,4))||{rules:{}});
 return model;
}
export function buildReport(model,type,{from=model.date_from,to=model.date_to,generatedAt=new Date().toISOString()}={}) {
 if(!REPORT_TYPES.includes(type))throw new Error('Reporte desconocido.');
 const months=model.monthly.filter(m=>m.month>=from.slice(0,7)&&m.month<=to.slice(0,7));
 const resultSection=code=>['sales','gross_sales','credit_notes','taxable_sales','untaxed_sales'].includes(code)?'VENTAS':code==='purchases'||code.startsWith('expense_category_')?'EGRESOS':['payroll','salary_net','sac','employer_contributions'].includes(code)?'PERSONAL':code==='result'?'RESULTADO':'OTROS';
 const sectionOrder=['VENTAS','EGRESOS','PERSONAL','OTROS','RESULTADO'];
 const rows=type==='RESULTADOS'?months.flatMap(m=>m.lines.filter(l=>!l.code.startsWith('bank_')).map(l=>({...l,month:m.month,section:resultSection(l.code)})).sort((a,b)=>sectionOrder.indexOf(a.section)-sectionOrder.indexOf(b.section))):type==='IVA'?model.iva.filter(m=>m.month>=from.slice(0,7)&&m.month<=to.slice(0,7)).flatMap(m=>m.lines.map(l=>({...l,month:m.month}))):type==='IIBB'?model.iibb.filter(m=>m.month>=from.slice(0,7)&&m.month<=to.slice(0,7)).flatMap(m=>m.lines.map(l=>({...l,month:m.month}))):model.annual.lines.map(l=>({...l,month:model.annual.year}));
 const missing=[...new Set([...rows.flatMap(l=>l.missing),...(type==='IIBB'?model.iibb.flatMap(m=>m.missing):[])])];
 return {organization_id:model.organization_id,company_name:model.organization.name,cuit:model.organization.cuit,type,from,to,source_from:model.date_from,source_to:model.date_to,generated_at:generatedAt,generated_by:model.actor,status:'BORRADOR',engine_version:ENGINE_VERSION,input_hash:model.input_hash,rows,missing,manual_inputs:model.inputs,
  disclaimer:type==='GANANCIAS'?'Auxiliar anual para el contador. No determina automáticamente Ganancias ni Bienes Personales.':'Cálculo documental estimado sobre datos importados; verificar integridad, clasificación y ajustes antes de presentar.'};
}
