import fs from 'fs';
import path from 'path';
import { detectFileFormat } from '../../src/js/core/adapters/fileAdapter.js';

import { fileURLToPath } from 'url';
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesDir = path.join(__dirname, '../fixtures');

describe('FileAdapter Format Detection', () => {
    it('detects OOXML_XLSX based on signature', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'synthetic_arca_compras.xlsx'));
        const format = detectFileFormat({
            arrayBuffer: buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
            fileName: 'compras.xlsx'
        });
        expect(format).toBe('OOXML_XLSX');
    });

    it('detects OLE2_BIFF based on signature', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'synthetic_arca_retenciones.xls'));
        const format = detectFileFormat({
            arrayBuffer: buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
            fileName: 'retenciones.xls'
        });
        expect(format).toBe('OLE2_BIFF');
    });

    it('throws error on mismatch between extension and signature', () => {
        // A file with .xlsx extension but TEXT content
        const buffer = fs.readFileSync(path.join(fixturesDir, 'mismatch.xlsx'));
        expect(() => {
            detectFileFormat({
                arrayBuffer: buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
                fileName: 'mismatch.xlsx'
            });
        }).toThrow(/Inconsistencia/);
    });

    it('falls back to extension if no signature matches (TXT)', () => {
        const format = detectFileFormat({
            fileName: 'arba.txt'
        });
        expect(format).toBe('TEXT_FIXED_WIDTH');
    });
});
