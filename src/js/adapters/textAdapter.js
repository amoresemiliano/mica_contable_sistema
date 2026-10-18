/** Quote-aware reader retaining physical source lines, including sep directives. */
export function parseDelimitedText(text, options = {}) {
    if (typeof text !== 'string' || !text.trim()) throw new Error('El archivo de texto está vacío o no es válido.');
    text = text.replace(/^\uFEFF/, '');
    const directive = text.match(/^sep=([,;\t])\s*\r?\n/i);
    const first = text.split(/\r?\n/).find(l => l.trim() && !/^sep=/i.test(l)) || '';
    const count = d => { let quoted = false, n = 0; for (const c of first) { if (c === '"') quoted = !quoted; else if (!quoted && c === d) n++; } return n; };
    const delimiter = options.delimiter && options.delimiter !== 'AUTO' ? options.delimiter
        : directive?.[1] || [';', '\t', ','].sort((a,b) => count(b)-count(a))[0];
    const rows = [];
    let row = [], cell = '', quoted = false, line = 1, start = 1;
    const emit = () => {
        row.push(cell);
        if (!(start === 1 && directive) && !(options.ignoreEmptyLines && row.every(c => !c.trim()))) {
            Object.defineProperty(row, 'sourceRowNumber', { value: start }); rows.push(row);
        }
        row = []; cell = ''; start = line + 1;
    };
    if (delimiter === 'NONE') return text.split(/\r?\n/).flatMap((l,i) => {
        if (options.ignoreEmptyLines && !l.trim()) return [];
        const r = [l]; Object.defineProperty(r, 'sourceRowNumber', { value: i+1 }); return [r];
    });
    for (let i=0; i<text.length; i++) {
        const c=text[i];
        if (c === '"') {
            if (quoted && text[i+1] === '"') { cell += '"'; i++; } else quoted = !quoted;
        } else if (c === delimiter && !quoted) { row.push(cell); cell=''; }
        else if (c === '\n') { if (quoted) cell+='\n'; else emit(); line++; }
        else if (c !== '\r' || quoted) cell += c;
    }
    if (quoted) throw new Error('Texto delimitado inválido: comillas sin cerrar.');
    if (cell || row.length) emit();
    return rows;
}
