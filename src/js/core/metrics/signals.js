const templates={
 SALES_DECLINE:['Las ventas documentadas bajaron significativamente.','Validá la cobertura de ventas y revisá las actividades que explican la caída.'],
 NEGATIVE_RESULT:['El resultado documental completo es negativo.','Revisá las compras, personal y ajustes que explican el resultado.'],
 PURCHASE_TO_SALES_PRESSURE:['Las compras pesan más sobre las ventas frente a su referencia.','Revisá las categorías de compra y validá la cobertura de ventas.'],
 PAYROLL_PRESSURE:['Personal crece más que ventas y su peso aumentó frente a su referencia.','Revisá la evolución de personal y ventas; no implica ineficiencia de la dotación.'],
 BANK_FLOW_RECOVERY:['El flujo bancario volvió a ser positivo.','Revisá los cobros y pagos que explican la recuperación.'],
 SALES_DOWN_COSTS_UP:['Las ventas bajaron mientras las compras crecieron.','Revisá las principales compras y validá que todas las ventas estén importadas.'],
 EXPENSES_GROW_FASTER_THAN_SALES:['Las compras crecieron más que las ventas.','Compará las categorías de compra con el período anterior.'],
 SALES_FLAT_PAYROLL_UP:['Las ventas se mantienen mientras crece personal.','Revisá la evolución de personal y ventas antes de incorporar costos fijos.'],
 NEGATIVE_FLOW_WITH_PROFIT:['Resultado documental positivo con flujo bancario negativo.','Compará cobros y pagos; el resultado documental no equivale a efectivo.'],
 POSITIVE_FLOW_NEGATIVE_RESULT:['Flujo bancario positivo con resultado documental negativo.','Revisá el origen de los ingresos bancarios y las compras documentadas.'],
 THREE_MONTH_SALES_DECLINE:['Tres meses consecutivos de caída de ventas.','Validá las cargas de ventas y revisá las actividades con mayor caída.'],
 TWO_NEGATIVE_RESULT_MONTHS:['Dos meses con resultado documental negativo.','Revisá compras y personal en los meses señalados.'],
 HIGH_SUPPLIER_CONCENTRATION:['Concentración de compras: posible dependencia de proveedores.','Revisá alternativas y condiciones de los cinco proveedores principales.'],
 LOW_CLASSIFICATION_COVERAGE:['Hay compras pendientes de clasificación.','Clasificá los comprobantes pendientes para mejorar el análisis.'],
 FISCAL_PRESSURE_SPIKE:['La proporción de IVA sobre ventas aumentó frente a su historia.','Validá créditos, saldo inicial y composición de las ventas.'],
 BANK_OUTFLOW_SPIKE:['Los egresos bancarios aumentaron frente a su historia.','Revisá los movimientos y su clasificación.'],
 IMPROVING_MARGIN:['Mejoró el margen documental.','Revisá qué compras y ventas explican la mejora.'],
 RECORD_SALES:['Máximo de ventas en la historia comparable disponible.','Identificá las actividades que sostienen este crecimiento.'],
 COST_CONTROL_IMPROVING:['Las compras pesan menos sobre las ventas.','Revisá si la mejora se sostiene en las principales categorías.'],
 MISSING_CRITICAL_DATA:['El diagnóstico tiene información pendiente.','Completá las fuentes y ajustes indicados antes de sacar conclusiones.'],
 FOREIGN_CURRENCY_EXCLUSIONS:['Hay operaciones fuera del cálculo ARS.','Definí una política de conversión validada para estas operaciones.'],
 RECURRING_NEGATIVE_FLOW:['Hay dos meses consecutivos con flujo bancario negativo.','Revisá cobros y pagos de los meses afectados.']
};
export const SIGNAL_CATALOG=Object.freeze(templates);
export function buildSignals(metrics,monthly) {
 const get=code=>metrics.find(m=>m.code===code),v=code=>get(code)?.value;
 const signals=[];
 const emit=(code,codes,positive=false)=>{
  const evidence=codes.map(get).filter(Boolean);if(!evidence.length)return;
  if(!['MISSING_CRITICAL_DATA','FOREIGN_CURRENCY_EXCLUSIONS'].includes(code)&&evidence.some(m=>m.value==null||['LOW','UNAVAILABLE'].includes(m.confidence)))return;
  const [explanation,action]=templates[code];
  signals.push({code,metric_codes:codes,status:positive?'POSITIVE_SIGNAL':'WATCH',confidence:evidence.some(m=>m.confidence!=='HIGH')?'MEDIUM':'HIGH',explanation,
   recommended_actions:[{rule:code,text:action}],severity:positive?0:evidence.some(m=>m.status==='CRITICAL')?3:2,deterioration:evidence.some(m=>m.trend?.change< -15||m.code==='sales_change'&&m.value< -15||['purchase_change','payroll_change'].includes(m.code)&&m.value>15)?1:0,persistence:code.includes('MONTH')||code.includes('RECURRING')?2:1,
   financial_relevance:Math.max(0,...evidence.map(m=>Math.abs(m.unit==='ARS_CENTS'?m.value||0:0))),actionability:1});
 };
 const sales=v('sales_change'),cost=v('purchase_change'),pay=v('payroll_change');
 if(sales<0&&cost>0)emit('SALES_DOWN_COSTS_UP',['sales_change','purchase_change']);
 else if(cost>sales&&cost>10)emit('EXPENSES_GROW_FASTER_THAN_SALES',['sales_change','purchase_change']);
 else if(sales< -15)emit('SALES_DECLINE',['sales_change']);
 else if(get('purchase_share')?.status==='WATCH')emit('PURCHASE_TO_SALES_PRESSURE',['purchase_share']);
 if(sales!=null&&Math.abs(sales)<=5&&pay>10)emit('SALES_FLAT_PAYROLL_UP',['sales_change','payroll_change']);
 else if(sales!=null&&pay>sales&&get('payroll_share')?.status==='WATCH')emit('PAYROLL_PRESSURE',['payroll_share','payroll_change','sales_change']);
 if(v('result')>0&&v('bank_flow')<0)emit('NEGATIVE_FLOW_WITH_PROFIT',['result','bank_flow']);
 if(v('result')<0&&v('bank_flow')>0)emit('POSITIVE_FLOW_NEGATIVE_RESULT',['result','bank_flow']);
 if(monthly.length>=4&&monthly.slice(-4).every(m=>m.sales!=null)&&monthly.slice(-3).every((m,i)=>m.sales<monthly.slice(-4)[i].sales))emit('THREE_MONTH_SALES_DECLINE',['sales']);
 if(monthly.length>=2&&monthly.slice(-2).every(m=>m.result!=null&&m.result<0))emit('TWO_NEGATIVE_RESULT_MONTHS',['result']);
 else if(v('result')<0)emit('NEGATIVE_RESULT',['result']);
 if(monthly.length>=2&&monthly.slice(-2).every(m=>m.bank_flow!=null&&m.bank_flow<0))emit('RECURRING_NEGATIVE_FLOW',['bank_flow']);
 if(v('supplier_top3')>70)emit('HIGH_SUPPLIER_CONCENTRATION',['supplier_top3']);
 if(v('unclassified_share')>20)emit('LOW_CLASSIFICATION_COVERAGE',['unclassified_share']);
 if(get('iva_share')?.status==='WATCH')emit('FISCAL_PRESSURE_SPIKE',['iva_share']);
 if(get('bank_outflow')?.status==='WATCH')emit('BANK_OUTFLOW_SPIKE',['bank_outflow']);
 if(v('margin_change')>=5)emit('IMPROVING_MARGIN',['margin_change'],true);
 if(get('sales')?.record)emit('RECORD_SALES',['sales'],true);
 if(v('purchase_share_change')<=-5)emit('COST_CONTROL_IMPROVING',['purchase_share_change'],true);
 if(v('bank_flow')>0&&get('bank_flow')?.comparison.value<0)emit('BANK_FLOW_RECOVERY',['bank_flow'],true);
 // A persistent decline supersedes a single-period decline recommendation.
 if(signals.some(s=>s.code==='THREE_MONTH_SALES_DECLINE')){const single=signals.findIndex(s=>s.code==='SALES_DECLINE');if(single>=0)signals.splice(single,1);}
 const criticalGaps=metrics.filter(m=>['sales','purchases','result','payroll','employer_contributions','bank_flow','iva_share','iibb_share'].includes(m.code)&&m.missing.length);
 if(criticalGaps.length)emit('MISSING_CRITICAL_DATA',criticalGaps.map(m=>m.code));
 if(metrics.some(m=>m.exclusions.length))emit('FOREIGN_CURRENCY_EXCLUSIONS',metrics.filter(m=>m.exclusions.length).map(m=>m.code));
 return signals;
}
export function rankPriorities(signals) {
 return signals.filter(s=>s.status!=='POSITIVE_SIGNAL').map(s=>({...s,rank_score:s.severity*4+s.persistence*2+(s.deterioration||0)+s.actionability+(s.confidence==='HIGH'?2:1)+(s.financial_relevance>0?1:0)}))
  .sort((a,b)=>b.rank_score-a.rank_score||a.code.localeCompare(b.code)).slice(0,5);
}
