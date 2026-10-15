import {reportingData} from './reporting.js';

// Synthetic amounts. Record counts/currency spelling match the supplied DEV diagnostic.
export function reportingCurrency046Data({annual=true}={}) {
    const data=reportingData();
    const template=kind=>structuredClone(data.groups.find(r=>r.kind===kind));
    const sales=Array.from({length:4},(_,i)=>({...template('SALES'),count:1,supplier:`Venta sintética ${i}`,currency:'$',net:100000,taxable:100000,vat:21000,amount:121000,credit_notes:null,credit_notes_net:null}));
    const purchases=Array.from({length:137},(_,i)=>({...template('PURCHASES'),count:1,supplier:`Compra sintética ARS ${i}`,currency:'$',net:1000,taxable:1000,vat:210,amount:1210}));
    const foreign=Array.from({length:4},(_,i)=>({...template('PURCHASES'),count:1,supplier:`Compra sintética USD ${i}`,currency:'USD',net:10000,taxable:10000,vat:2100,amount:12100,tipoCambio:1234.56}));
    const banks=Array.from({length:83},(_,i)=>({...template('BANK'),count:1,supplier:`Banco sintético ${i}`,currency:'PES',amount:i<50?1000:-1000,income:i<50?1000:0,outflow:i<50?0:1000,largest_unclassified:1000}));
    const payroll={...template('PAYROLL'),currency:'PES',net:15000,amount:15000,salary_net:10000,sac:1000};
    const taxes=[...Array.from({length:14},(_,i)=>({...template('TAX'),supplier:`ARBA ${i}`,tax_type:null,jurisdiction:'ARBA',amount:100})),...Array.from({length:50},(_,i)=>({...template('TAX'),supplier:`IVA ${i}`,tax_type:'IVA',tax_kind:'percepcion',amount:100}))];
    data.groups=[...sales,...purchases,...foreign,...banks,payroll,...taxes];
    data.organization.name='Demo Norte (fixture sintética)';
    data.inputs.find(i=>i.kind==='PERIOD_ADJUSTMENT').payload={employer_contributions:2000};
    if(annual){data.date_from='2026-01-01';data.date_to='2026-12-31';data.inputs.find(i=>i.kind==='IVA_OPENING').period='2026-01';}
    return data;
}
