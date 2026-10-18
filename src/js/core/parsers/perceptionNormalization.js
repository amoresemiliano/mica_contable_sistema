export function perceptionDate(value) {
    const s=String(value ?? '').trim(); let y,m,d;
    if (/^\d{8}$/.test(s)) [y,m,d]=[s.slice(0,4),s.slice(4,6),s.slice(6)];
    else if (/^\d{4}-\d{2}-\d{2}$/.test(s)) [y,m,d]=s.split('-');
    else if (/^\d{2}\/\d{2}\/\d{4}$/.test(s)) [d,m,y]=s.split('/');
    else return null;
    const date=new Date(Date.UTC(+y,+m-1,+d));
    return date.getUTCFullYear()===+y && date.getUTCMonth()===+m-1 && date.getUTCDate()===+d ? `${d}/${m}/${y}` : null;
}
export function perceptionAmount(v) {
    if (typeof v === 'number') return Number.isFinite(v) ? v : null;
    let s=String(v ?? '').trim();
    if (/^[+-]?\d{1,3}(\.\d{3})+,\d{2}$/.test(s)) s=s.replace(/\./g,'').replace(',','.');
    else if (/^[+-]?\d+(?:[,.]\d+)?$/.test(s)) s=s.replace(',','.');
    else return null;
    const n=Number(s); return Number.isFinite(n) ? n : null;
}
