export function reportingData(overrides={}) {
 const org='11111111-1111-4111-8111-111111111111';
 const input=(kind,payload,period='2026-09')=>({id:`input-${kind}-${period}`,organization_id:org,kind,period,payload,revision:1,created_by:'accountant',created_at:'2026-10-01T10:00:00Z',note:'Respaldo de prueba'});
 const group=(kind,values={})=>({month:'2026-09',kind,count:1,source_type:kind==='PAYROLL'||kind==='BANK'?'eco_financial_movements':'eco_normalized_records',category_id:kind==='PURCHASES'?'office':null,activity_id:kind==='SALES'?'activity-a':null,supplier:'Proveedor de prueba',jurisdiction:null,currency:'PES',tax_type:null,tax_kind:null,net:null,taxable:null,vat:null,amount:null,credit_notes:null,credit_notes_net:null,salary_net:null,sac:null,missing_net:0,missing_vat:0,missing_amount:0,rates:[],...values});
 return {organization_id:org,organization:{name:'Empresa de prueba',cuit:'30700000001'},actor:'accountant',date_from:'2026-09-01',date_to:'2026-09-30',input_hash:'canonical-input-hash',
  groups:[group('SALES',{count:2,net:900000,taxable:900000,vat:189000,amount:1089000,credit_notes:-121000,credit_notes_net:-100000,rates:[{id:'rate-caba',activity_id:'activity-a',jurisdiction:'CABA',rate:3},{id:'rate-ba',activity_id:'activity-a',jurisdiction:'BUENOS AIRES',rate:4}]}),
   group('PURCHASES',{net:200000,taxable:200000,vat:42000,amount:242000}),
   group('PAYROLL',{net:100000,amount:100000,salary_net:80000,sac:10000}),
   group('BANK',{amount:300000,income:500000,outflow:200000,largest_unclassified:200000}),
   group('TAX',{amount:5000,tax_type:'IVA',tax_kind:'retencion'}),group('TAX',{amount:10000,tax_type:'IVA',tax_kind:'percepcion'})],
  inputs:[input('IVA_OPENING',{technical:20000,free:30000}),input('PERIOD_ADJUSTMENT',{employer_contributions:20000,other_income:5000,other_expense:10000,iva_compensation:25000,iibb:[{jurisdiction:'CABA',retention:1000,perception:2000,bank_retention:3000,prior:4000,interest:500,adjustment:0}]}),input('IIBB_CONFIG',{regime:'LOCAL',jurisdiction:'CABA'},'2026')],
  accounts:[{account:'0001',observations:2,first:500000,last:800000,minimum:500000,maximum:800000,average:650000}],categories:[{id:'office',name:'Oficina'}],activities:[{id:'activity-a',name:'Servicios'}],quality:{import_issues:0,excluded_amendments:0,undated:0},...overrides};
}
