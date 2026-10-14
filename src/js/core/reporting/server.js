import { buildModel,buildReport,validateInput,REPORT_TYPES,ENGINE_VERSION,monthsBetween,alertEngine } from './engine.js';

// Dependency injection keeps the exact trusted server path locally testable without DB execution.
export function createReportingHandler({authenticate,userClient,serviceClient,allowedOrigins=[],now=()=>new Date().toISOString()}) {
 return async request=>{
  const origin=request.headers.get('origin');
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
  if(origin && !allowedOrigins.includes(origin))return new Response(JSON.stringify({error:'Origen no autorizado.'}),{status:403,headers});
  if(origin)Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'});
  if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
  if(request.method!=='POST')return new Response(JSON.stringify({error:'Método no permitido.'}),{status:405,headers});
  try {
   const authorization=request.headers.get('authorization');
   if(!authorization?.startsWith('Bearer '))return new Response(JSON.stringify({error:'Sesión requerida.'}),{status:401,headers});
   const user=await authenticate(authorization.slice(7));
   if(!user?.id)return new Response(JSON.stringify({error:'Sesión inválida.'}),{status:401,headers});
   const raw=await request.text();if(raw.length>262144)throw new Error('Solicitud demasiado grande.');
   const body=JSON.parse(raw),client=userClient(authorization);
   const rpc=async(name,args)=>{const {data,error}=await client.rpc(name,args);if(error)throw new Error(error.message);return data;};
   const context=await rpc('get_my_operational_context',{}),org=context?.organization_id;
   if(!org||org!==body.organization_id)throw new Error('El contexto de empresa cambió.');
   const from=body.from,to=body.to;monthsBetween(from,to);
   const dataArgs={p_expected_org:org,p_from:from,p_to:to,p_export:['export','review','close','reopen'].includes(body.action)};
   let data=await rpc('mica_reporting_data',dataArgs);
   if(data.organization_id!==org)throw new Error('Respuesta de otra organización.');
   if(body.action==='input') {
    validateInput(body.kind,body.period,body.payload);
    if(!Number.isInteger(body.revision)||body.revision<0)throw new Error('Revisión inválida.');
    const {data:written,error}=await serviceClient.rpc('mica_reporting_service',{p_subject:user.id,p_expected_org:org,p_action:'input',p_data:{kind:body.kind,period:body.period,payload:body.payload,note:body.note||'',revision:body.revision}});
    if(error)throw new Error(error.message);return new Response(JSON.stringify(written),{headers});
   }
   const selectedData=data;
   // Carry-forward requires the entire chain from the latest explicit opening.
   const opening=data.inputs.filter(i=>i.kind==='IVA_OPENING'&&i.period<=from.slice(0,7)).sort((a,b)=>b.period.localeCompare(a.period))[0];
   if(opening && opening.period<from.slice(0,7)) {
    const expanded=`${opening.period}-01`;
    const distance=(Number(to.slice(0,4))-Number(expanded.slice(0,4)))*12+Number(to.slice(5,7))-Number(expanded.slice(5,7));
    if(distance<36)data=await rpc('mica_reporting_data',{...dataArgs,p_from:expanded});
   }
   if(data.organization_id!==org)throw new Error('Respuesta de otra organización.');
   if(body.action==='data'){
    const model=buildModel(selectedData),expanded=buildModel(data);
    model.iva=expanded.iva.filter(m=>m.month>=from.slice(0,7)&&m.month<=to.slice(0,7));
    model.trace_from=data.date_from;model.trace_to=data.date_to;
    const nextDay=new Date(`${to}T00:00:00Z`);nextDay.setUTCDate(nextDay.getUTCDate()+1);
    if(!from.endsWith('-01')||nextDay.getUTCDate()!==1){
     const warning='El filtro contiene meses parciales; elegí meses completos para estimar impuestos.';
     for(const month of [...model.iva,...model.iibb]){month.payable=null;month.missing.push(warning);for(const line of month.lines){line.missing.push(warning);if(['iva_payable','iibb_payable'].includes(line.code))line.value=null;}}
    }
    model.alerts=alertEngine(model,selectedData.inputs.find(i=>i.kind==='ALERT_SETTINGS'&&i.period===to.slice(0,4))?.payload||{rules:{}});
    return new Response(JSON.stringify({model}),{headers});
   }
   if(!REPORT_TYPES.includes(body.type))throw new Error('Tipo de reporte inválido.');
   if(body.type==='GANANCIAS'&&(from.slice(5)!=='01-01'||to.slice(5)!=='12-31'||from.slice(0,4)!==to.slice(0,4)))throw new Error('Ganancias requiere un ejercicio anual completo.');
   if(['IVA','IIBB'].includes(body.type)) {
    const end=new Date(`${to}T00:00:00Z`);end.setUTCDate(end.getUTCDate()+1);
    if(!from.endsWith('-01')||end.getUTCDate()!==1)throw new Error('Los reportes fiscales requieren meses completos.');
   }
   const report=buildReport(buildModel(data),body.type,{from,to,generatedAt:now()});
   if(['preview','export'].includes(body.action))return new Response(JSON.stringify({report}),{headers});
   if(!['review','close','reopen'].includes(body.action))throw new Error('Acción inválida.');
   if(body.action!=='reopen'&&body.input_hash!==report.input_hash)throw new Error('Cambiaron los datos: regenerá la vista previa.');
   if(['review','close'].includes(body.action)&&report.missing.length)throw new Error('Completá los datos faltantes antes de revisar/cerrar el reporte.');
   const {data:written,error}=await serviceClient.rpc('mica_reporting_service',{p_subject:user.id,p_expected_org:org,p_action:body.action,
    p_data:{type:body.type,from,to,source_from:data.date_from,source_to:data.date_to,input_hash:report.input_hash,engine_version:ENGINE_VERSION,calculated:report,note:body.note||''}});
   if(error)throw new Error(error.message);
   return new Response(JSON.stringify({...written,report:{...report,status:body.action==='close'?'CERRADO':body.action==='review'?'REVISADO':'BORRADOR'}}),{headers});
  } catch(error) {
   return new Response(JSON.stringify({error:error instanceof Error?error.message:'No se pudo generar el reporte.'}),{status:400,headers});
  }
 };
}
