import { supabase } from './supabaseClient.js';
export const reportingService = {
 async request(body) {
  const {data,error}=await supabase.functions.invoke('mica-reporting',{body});
  if(error){let message=error.message;try{message=(await error.context?.json())?.error||message;}catch{}throw new Error(message||'Servicio de reportes no disponible.');}
  if(!data||data.error)throw new Error(data?.error||'Respuesta de reportes inválida.');
  return data;
 },
 async detail(org,from,to,filter,offset=0,snapshot=null) {
  const {data,error}=await supabase.rpc('mica_reporting_detail',{p_expected_org:org,p_from:from,p_to:to,p_filter:filter,p_offset:offset,p_limit:100,p_snapshot:snapshot});
  if(error)throw new Error(error.message);
  if(data?.organization_id!==org||!Array.isArray(data.rows)||data.rows.some(r=>r.organization_id!==org))throw new Error('Detalle de otra organización.');
  return data;
 },
 async history(org,from,to,type,snapshot=null) {
  const {data,error}=await supabase.rpc('mica_reporting_history',{p_expected_org:org,p_from:from,p_to:to,p_type:type,p_snapshot:snapshot});
  if(error)throw new Error(error.message);
  if(snapshot&&data?.organization_id!==org)throw new Error('Cierre fuera del contexto.');
  return data;
 }
};
