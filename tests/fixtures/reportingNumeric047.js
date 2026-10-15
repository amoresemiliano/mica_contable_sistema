// User-supplied historical values, with independently specified expected cents.
export const numeric047Vectors = [
 ['20348.980000000003',2034898],['131588.27000000002',13158827],
 ['277120.32999999996',27712033],['91127.76999999999',9112777],
 ['204778.93000000002',20477893],['95480.48000000001',9548048],
 ['402204.16000000003',40220416],['127990.51000000001',12799051]
];
export const voucher047Vectors = [
 {tipo_cbte:1,sign:1}, {tipo_cbte:3,sign:-1},
 {tipo_cbte:15,sign:1}, {tipo_cbte:17,sign:1}, {tipo_cbte:81,sign:1},
 {tipo_cbte:999,sign:null}
];
export const totalZero047 = Object.freeze({tipo_cbte:17,moneda:'ARS',
 netoGravado:'227598.63',netoNoGravado:'10473.35',exento:'0',
 totalIva:'61451.63',otrosTributos:'0',total:'0.00'});
// Expected RPC projection of that source row (cents); not a SQL runtime simulation.
export const totalZero047Group = Object.freeze({kind:'PURCHASES',month:'2026-09',
 source_type:'eco_normalized_records',currency:'ARS',count:1,
 net:23807198,taxable:22759863,vat:6145163,amount:null,
 missing_net:0,missing_vat:0,missing_amount:1});
