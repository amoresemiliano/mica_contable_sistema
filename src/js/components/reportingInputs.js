import {escapeHtml as e,formatMoney} from '../core/reporting/exports.js';
import {ALERT_DEFAULTS,ALERT_LABELS,alertMoneyThreshold,validateInput} from '../core/reporting/engine.js';
export const INPUT_LABELS={IVA_OPENING:'Apertura IVA',PERIOD_ADJUSTMENT:'Ajustes del período',IIBB_CONFIG:'Régimen IIBB',CM_COEFFICIENTS:'Coeficientes CM anuales',ANNUAL_TAX:'Datos fiscales anuales',ALERT_SETTINGS:'Umbrales de alertas'};
const moneyFields={
 IVA_OPENING:[['technical','Saldo técnico a favor inicial'],['free','Saldo libre disponibilidad inicial']],
 PERIOD_ADJUSTMENT:[['employer_contributions','Cargas empleador (no aportes retenidos)'],['other_income','Otros ingresos adicionales'],['other_expense','Otros egresos adicionales'],['iva_retention','Ajuste retenciones IVA'],['iva_perception','Ajuste percepciones IVA'],['iva_ld_adjustment','Ajuste LD IVA'],['iva_compensation','Compensación IVA instruida']],
 ANNUAL_TAX:[['tax_determined','Impuesto determinado por contador'],['payments','Pagos a cuenta / anticipos'],['retentions','Retenciones Ganancias confirmadas'],['prior','Saldo anterior a favor'],['opening_equity','Patrimonio inicial (valuación ARS)'],['consumed','Monto consumido']]
};
const moneyInput=(key,label,value)=>`<label>${e(label)} (ARS)<input name="${e(key)}" inputmode="decimal" type="number" step="0.01" value="${value==null?'':value/100}"></label>`;
const cell=(key,value='',type='text')=>`<td><input data-field="${key}" type="${type}" ${type==='number'?'step="any"':''} value="${e(value)}" aria-label="${e(key)}"></td>`;
export function inputRow(kind,row={}) {
 if(kind==='CM_COEFFICIENTS')return `<tr data-input-row>${cell('jurisdiction',row.jurisdiction)}${cell('coefficient',row.coefficient??'','number')}<td><button type="button" data-remove-row>Quitar</button></td></tr>`;
 if(kind==='PERIOD_ADJUSTMENT')return `<tr data-input-row>${cell('jurisdiction',row.jurisdiction)}${['retention','perception','bank_retention','prior','interest','adjustment'].map(k=>cell(k,row[k]==null?'':row[k]/100,'number')).join('')}<td><button type="button" data-remove-row>Quitar</button></td></tr>`;
 if(kind==='ANNUAL_TAX')return `<tr data-input-row><td><select data-field="family" aria-label="Familia">${[['income','Renta'],['deduction','Deducción'],['asset','Bien'],['liability','Deuda'],['adjustment','Cambio patrimonial']].map(([v,l])=>`<option value="${v}" ${row.family===v?'selected':''}>${l}</option>`).join('')}</select></td>${cell('code',row.code||'TAXED')}${cell('category',row.category||'Tercera')}${cell('description',row.description)}${cell('amount',row.amount==null?'':row.amount/100,'number')}${cell('currency',row.currency||'ARS')}${cell('original_amount',row.original_amount==null?'':row.original_amount/100,'number')}<td><button type="button" data-remove-row>Quitar</button></td></tr>`;
 return '';
}
export function inputEditor(data,kind,period) {
 const entry=data.inputs.find(i=>i.kind===kind&&i.period===period),p=entry?.payload||{};
 const heads=kind==='CM_COEFFICIENTS'?['Jurisdicción canónica','Coeficiente (0–1)']:kind==='PERIOD_ADJUSTMENT'?['Jurisdicción','Retenciones ARS','Percepciones ARS','Ret. bancarias ARS','Saldo previo a favor ARS','Interés ARS','Ajuste ARS']:['Familia','Concepto','Categoría de renta/bien/deducción','Descripción','Valuación/importe ARS','Moneda original','Importe original'];
 let content=(moneyFields[kind]||[]).map(([k,l])=>moneyInput(k,l,p[k])).join('');
 if(kind==='PERIOD_ADJUSTMENT')content+=`<label class="mr-span"><input type="checkbox" name="payroll_not_applicable" ${p.payroll_not_applicable?'checked':''}> Confirmo que este período no tiene nómina (no reemplaza una importación faltante).</label>`;
 if(kind==='IIBB_CONFIG')content+=`<label>Régimen<select name="regime"><option value="">Seleccionar…</option><option value="LOCAL" ${p.regime==='LOCAL'?'selected':''}>Contribuyente local</option><option value="CONVENIO_MULTILATERAL" ${p.regime==='CONVENIO_MULTILATERAL'?'selected':''}>Convenio multilateral</option></select></label><label>Jurisdicción local (nombre exacto del catálogo de alícuotas)<input name="jurisdiction" value="${e(p.jurisdiction)}"></label>`;
 if(['CM_COEFFICIENTS','PERIOD_ADJUSTMENT','ANNUAL_TAX'].includes(kind)){
  const rows=kind==='PERIOD_ADJUSTMENT'?p.iibb||[]:p.rows||[];
  content+=`<div class="mr-table-wrap mr-span"><table><thead><tr>${heads.map(h=>`<th>${e(h)}</th>`).join('')}<th></th></tr></thead><tbody data-input-rows>${rows.map(r=>inputRow(kind,r)).join('')}</tbody></table></div><button type="button" data-add-row>Agregar ${kind==='PERIOD_ADJUSTMENT'?'ajuste IIBB':'fila'}</button>`;
 }
 if(kind==='ANNUAL_TAX')content+=`<p class="mr-span">Rentas: concepto TAXED (gravada) o EXEMPT (exenta); categoría Primera/Segunda/Tercera/Cuarta. Deducciones: concepto y categoría configurables (Art. 30, hijos, quebrantos, seguros, etc.). Bienes/deudas: valuación ARS explícita, moneda e importe originales separados. No se aplica escala legal automática.</p><label class="mr-span"><input name="confirmed" type="checkbox" ${p.confirmed?'checked':''}> Confirmo la clasificación fiscal y las valuaciones anuales ingresadas.</label>`;
 if(kind==='ALERT_SETTINGS')content+=`<div class="mr-table-wrap mr-span"><table><thead><tr><th>Regla</th><th>Activa</th><th>Umbral (% / puntos; movimiento grande en ARS)</th><th>Comparación</th><th>Severidad</th></tr></thead><tbody>${Object.entries(ALERT_DEFAULTS).map(([code,defaults])=>{const r={...defaults,enabled:true,...p.rules?.[code]};return `<tr data-rule="${code}"><th>${e(ALERT_LABELS[code])}</th><td><input type="checkbox" data-field="enabled" ${r.enabled?'checked':''} aria-label="Activar ${code}"></td><td><input type="number" step="any" min="0" data-field="threshold" value="${alertMoneyThreshold(code)?r.threshold/100:r.threshold}" aria-label="Umbral ${code}"></td><td><select data-field="mode">${['absolute','previous','historical'].map(m=>`<option ${r.mode===m?'selected':''} value="${m}">${{absolute:'Absoluta',previous:'Anterior',historical:'Histórica'}[m]}</option>`).join('')}</select></td><td><select data-field="severity">${['INFO','WARNING','CRITICAL','POSITIVE'].map(s=>`<option ${s===r.severity?'selected':''}>${s}</option>`).join('')}</select></td></tr>`;}).join('')}</tbody></table></div>`;
 return `<form data-input-form data-kind="${kind}" data-period="${period}" data-revision="${entry?.revision||0}" class="mr-input-form"><h3 class="mr-span">${INPUT_LABELS[kind]} · ${e(period)}</h3><p class="mr-span">${entry?`Revisión ${entry.revision} · usuario ${e(entry.created_by)} · ${e(entry.created_at)} · ${e(entry.note)}`:'Sin datos ingresados. Los campos vacíos no se consideran saldos iniciales cero.'}</p>${content}<label class="mr-span">Nota / respaldo<input name="note" maxlength="2000" value="${e(entry?.note)}"></label><button type="submit" class="btn-primary">Guardar nueva revisión</button><p class="mr-span mr-caption">Los ajustes se suman a lo importado. Ingresá solo diferencias: evitá repetir importes de comprobantes o percepciones existentes.</p></form>`;
}
export function parseMoney(value) {
 if(value==null||value==='')return null;
 const text=String(value).trim();if(!/^-?\d+(\.\d{1,2})?$/.test(text))throw new Error('Usá importes con hasta dos decimales.');
 const result=Math.round(Number(text)*100);if(!Number.isSafeInteger(result))throw new Error('Importe fuera de rango.');return result;
}
export function collectInput(form) {
 const kind=form.dataset.kind,p={};
 for(const [key] of moneyFields[kind]||[]){const v=parseMoney(form.elements.namedItem(key).value);if(v!=null)p[key]=v;}
 const rows=[...form.querySelectorAll('[data-input-row]')].map(tr=>Object.fromEntries([...tr.querySelectorAll('[data-field]')].map(input=>{const key=input.dataset.field;return [key,input.type==='number'?key==='coefficient'?Number(input.value):parseMoney(input.value):input.value.trim()];})));
 if(kind==='IVA_OPENING'&&(!('technical' in p)||!('free' in p)))throw new Error('Completá ambos saldos de apertura.');
 if(kind==='IIBB_CONFIG'){p.regime=form.elements.namedItem('regime').value;p.jurisdiction=form.elements.namedItem('jurisdiction').value.trim();}
 if(kind==='CM_COEFFICIENTS')p.rows=rows;
 if(kind==='PERIOD_ADJUSTMENT'){p.iibb=rows;p.payroll_not_applicable=form.elements.namedItem('payroll_not_applicable').checked;}
 if(kind==='ANNUAL_TAX'){p.rows=rows;p.confirmed=form.elements.namedItem('confirmed').checked;}
 if(kind==='ALERT_SETTINGS')p.rules=Object.fromEntries([...form.querySelectorAll('[data-rule]')].map(tr=>{const get=k=>tr.querySelector(`[data-field="${k}"]`);const code=tr.dataset.rule;return [code,{enabled:get('enabled').checked,threshold:alertMoneyThreshold(code)?parseMoney(get('threshold').value):Number(get('threshold').value),mode:get('mode').value,severity:get('severity').value}];}));
 validateInput(kind,form.dataset.period,p);
 return {kind,period:form.dataset.period,payload:p,revision:Number(form.dataset.revision),note:form.elements.namedItem('note').value};
}
