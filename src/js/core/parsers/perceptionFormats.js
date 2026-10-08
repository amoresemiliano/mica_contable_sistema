import { parseDelimitedText } from '../../adapters/textAdapter.js';
import { parseArbaText } from './arbaParser.js';
import { parseIvaPerceptions } from './ivaPerceptionParser.js';
import { perceptionDate, perceptionAmount } from './perceptionNormalization.js';

export const cleanHeader = v => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
const compact = /^(\d{3})(\d{2}-\d{8}-\d)(\d{2}\/\d{2}\/\d{4})([ \d]{12})([A-Z])([A-Z0-9])(\d{8},\d{2})$/;
const complete = /^(\d{11})([ \d]{8})(\d{8})(\d{4})([ \d]{13}\.\d{2})([ \d]{13}\.\d{2})([A-Z]{2})$/;
const retention = /^(\d{5})(\d{2}-\d{8}-\d)(\d{2}\/\d{2}\/\d{4})(\d{4})(\d{21})([A-Z]) (\d{19})(\d{13},\d{2})$/;
const positional = r => r.length===8 && /^\d{3}$/.test(String(r[0])) && /^\d+$/.test(String(r[1])) && /^\d{11}$/.test(String(r[2])) && /^\d{4}-\d{2}-\d{2}$/.test(String(r[4])) && /^\d+$/.test(String(r[5])) && /^\d+$/.test(String(r[6])) && perceptionAmount(r[7])!==null;
const activeRows = rows => rows.filter(r => r.some(c => String(c ?? '').trim()));
const confidence = (rows,predicate) => {
    const valid=rows.filter(predicate).length;
    return rows.length>0 && (valid/rows.length>=0.8 || (valid>=2 && rows.length-valid===1));
};

/** Content contracts only: filenames, customers and extensions never dispatch parsers. */
export function detectPerceptionFormat({ text, rows } = {}) {
    if (!rows && typeof text==='string') {
        try { rows=parseDelimitedText(text); } catch { return { id:'UNKNOWN' }; }
    }
    rows=activeRows(rows || []);
    for (let i=0;i<Math.min(rows.length,10);i++) {
        const h=rows[i].map(cleanHeader);
        if (h.includes('cuit') && h.includes('fecha percepcion') && h.includes('monto percibido') && h.includes('base calculo'))
            return { id:'CABA_RENTAS_CSV_EXPORT', header:rows[i], sourceType:'PERCEPCIONES_ARBA' };
        if (h.some(x=>x.includes('cuit')) && h.some(x=>x.includes('fecha')) && h.some(x=>x.includes('importe') || x.includes('monto')))
            return { id:'IVA_DELIMITED_HEADERED', sourceType:'PERCEPCIONES_IVA' };
    }
    if (confidence(rows,positional)) return { id:'IVA_DELIMITED_POSITIONAL', sourceType:'PERCEPCIONES_IVA' };
    if (typeof text!=='string' || rows.some(r=>r.length>2)) return { id:'UNKNOWN' };
    const lines=text.split(/\r?\n/).map(l=>l.replace(/\r$/,'')).filter(l=>l.trim());
    for (const [id,regex] of [['SIFERE_FIXED_A',compact],['SIFERE_FIXED_B',complete],['RETENTION_FIXED_C',retention]])
        if (confidence(lines,l=>regex.test(l))) return { id, sourceType:'PERCEPCIONES_ARBA' };
    if (confidence(lines,l=>l.length===70 && parseArbaText(l)[0]?.normalizedData)) return { id:'CURRENT_ARBA_FIXED', sourceType:'PERCEPCIONES_ARBA' };
    return { id:'UNKNOWN' };
}

function stage(rawRow, sourceRowNumber, fields, format, context) {
    const errors=[], fecha=perceptionDate(fields.fecha), monto=perceptionAmount(fields.monto);
    const cuit=String(fields.cuit ?? '').replace(/\D/g,'');
    if (!/^\d{11}$/.test(cuit)) errors.push('CUIT inválido.');
    if (!fecha) errors.push('Fecha inválida.');
    if (!(monto>0)) errors.push('Importe inválido.');
    return { rawRow, sourceRowNumber, errors, warnings:[], batchId:context.batchId || null,
        normalizedData:errors.length ? null : { ...fields, cuit, fecha, period:`${fecha.slice(6)}-${fecha.slice(3,5)}`,
            monto, amount:monto, importe:monto, razonSocial:fields.razonSocial || '', audit:{ format, ...(fields.audit || {}) } } };
}
export function parsePerceptionInput({ text, rows }, context={}) {
    rows=rows || parseDelimitedText(text);
    const format=detectPerceptionFormat({text,rows}); let items=[];
    if (format.id==='UNKNOWN') throw new Error('Formato de percepciones desconocido o estructura insuficiente.');
    if (format.id==='CURRENT_ARBA_FIXED') items=parseArbaText(text,context);
    else if (format.id==='IVA_DELIMITED_HEADERED') items=parseIvaPerceptions(rows,context);
    else if (format.id==='CABA_RENTAS_CSV_EXPORT' || format.id==='IVA_DELIMITED_POSITIONAL') {
        const start=format.header ? rows.indexOf(format.header)+1 : 0;
        for (let i=start;i<rows.length;i++) {
            const r=rows[i]; if (!r.some(c=>String(c ?? '').trim())) continue;
            const caba=!!format.header;
            const headers=caba ? format.header.map(cleanHeader) : [];
            const field=fragment=>r[headers.findIndex(h=>h.includes(fragment))];
            const f=caba ? { cuit:field('cuit'),razonSocial:field('razon social'),fecha:field('fecha percepcion'),comprobante:field('certificado') || field('n° comprobante'),monto:field('monto percibido'),baseCalculo:perceptionAmount(field('base calculo')),
                jurisdiction:'CABA',fuente:'RENTAS_CIUDAD',tipo:'percepcion',regimen:field('norma'),sucursal:'',audit:{tipoComprobante:field('tipo comprobante'),numeroComprobante:r[headers.findIndex(h=>h.includes('comprobante')&&!h.includes('tipo')&&!h.includes('fecha'))],fechaComprobante:field('fecha comprobante')} }
                : { cuit:r[2],fecha:r[4],comprobante:r[6],monto:r[7],jurisdiction:'NACIONAL (IVA)',fuente:'IVA',tipo:'percepcion',audit:{regimen:r[0],operacion:r[1],tipoComprobante:r[5]} };
            const item=stage(r,r.sourceRowNumber || i+1,f,format.id,context);
            if (r.length!==(caba?11:8) && !(caba && r.length===12 && r[11]==='')) { item.errors.push('Cantidad de campos inválida.'); item.normalizedData=null; }
            items.push(item);
        }
    } else {
        const regex={SIFERE_FIXED_A:compact,SIFERE_FIXED_B:complete,RETENTION_FIXED_C:retention}[format.id];
        text.split(/\r?\n/).map(l=>l.replace(/\r$/,'')).forEach((line,i)=> {
            if (!line.trim()) return;
            const m=line.match(regex);
            if (!m) { items.push({rawRow:line,sourceRowNumber:i+1,normalizedData:null,errors:['Estructura de registro inválida.'],warnings:[]}); return; }
            let f;
            if (format.id==='SIFERE_FIXED_A') f={cuit:m[2],fecha:m[3],monto:m[7],comprobante:m[4].trim(),regimen:m[1],sucursal:'',audit:{marker:m[5],documentType:m[6]}};
            else if (format.id==='SIFERE_FIXED_B') f={cuit:m[1],comprobante:m[2].trim(),fecha:m[3],monto:m[6].trim(),baseCalculo:perceptionAmount(m[5].trim()),regimen:m[4],sucursal:'',audit:{marker:m[7]}};
            else f={cuit:m[2],fecha:m[3],monto:m[8],comprobante:m[5],regimen:m[1],sucursal:m[4],audit:{marker:m[6],reference:m[7]}};
            Object.assign(f,{jurisdiction:format.id==='RETENTION_FIXED_C'?'ARBA':'CABA',fuente:format.id==='RETENTION_FIXED_C'?'ARBA':'RENTAS_CIUDAD',tipo:format.id==='RETENTION_FIXED_C'?'retencion':'percepcion'});
            items.push(stage(line,i+1,f,format.id,context));
        });
    }
    return {format,items};
}
