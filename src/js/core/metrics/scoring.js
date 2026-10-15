export const WEIGHTS = Object.freeze({RENTABILIDAD:25,LIQUIDEZ:20,VENTAS:15,COSTOS:15,FISCAL:15,PERSONAL:10});
export const statusScore = status => ({HEALTHY:85,POSITIVE_SIGNAL:90,WATCH:65,CRITICAL:35})[status] ?? null;
export function scoreHealth(metrics) {
 const pillars=Object.entries(WEIGHTS).map(([code,weight])=>{
  const members=metrics.filter(m=>m.pillar===code),eligible=members.filter(m=>m.score!=null&&m.confidence!=='LOW');
  const score=eligible.length?Math.round(eligible.reduce((n,m)=>n+m.score,0)/eligible.length):null;
  return {code,weight,score,status:score==null?'INSUFFICIENT_DATA':score>=80?'GREEN':score>=50?'YELLOW':'RED',
   confidence:!eligible.length?'UNAVAILABLE':members.some(m=>m.confidence!=='HIGH')?'MEDIUM':'HIGH',
   contribution:score==null?null:score*weight/100,metric_codes:eligible.map(m=>m.code),excluded_metrics:members.filter(m=>!eligible.includes(m)).map(m=>m.code)};
 });
 // No reweighting: a complete index requires all six independent pillars.
 const complete=pillars.every(p=>p.score!=null),score=complete?Math.round(pillars.reduce((n,p)=>n+p.contribution,0)):null;
 return {score,status:score==null?'INSUFFICIENT_DATA':score>=80?'GREEN':score>=50?'YELLOW':'RED',pillars,
  confidence:!complete?'UNAVAILABLE':pillars.some(p=>p.confidence!=='HIGH')?'MEDIUM':'HIGH',excluded_pillars:pillars.filter(p=>p.score==null).map(p=>p.code),
  explanation:complete?'Índice documental; cada contribución se muestra por pilar.':'Índice global no determinable: faltan pilares evaluables. Revisá los indicadores disponibles.',confidence_adjustments:metrics.filter(m=>m.missing.length).map(m=>({code:m.code,reasons:m.missing}))};
}
