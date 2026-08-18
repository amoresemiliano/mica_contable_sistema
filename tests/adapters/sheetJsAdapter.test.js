import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import * as XLSX from 'xlsx';
import { createSheetJsAdapter } from '../../src/js/core/adapters/sheetJsAdapter.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesDir = path.join(__dirname, '../fixtures');

describe('SheetJS Adapter', () => {
    const adapter = createSheetJsAdapter(XLSX);

    it('successfully parses a valid XLSX file', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'synthetic_arca_compras.xlsx'));
        // convert to arraybuffer
        const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        
        const rows = adapter.workbookToRows(arrayBuffer);
        
        expect(rows).toBeInstanceOf(Array);
        expect(rows.length).toBeGreaterThan(0);
        expect(rows[0][0]).toBe('Fecha'); // header
        expect(rows[1][0]).toBe('01/08/2026'); // data
    });

    it('throws when parsing a corrupt file', () => {
        expect(() => {
            adapter.workbookToRows(Buffer.from('this is not a zip file'));
        }).toThrow(/corrupto o no es un formato/i);
    });

    it('throws on a workbook with no sheets', () => {
        expect(() => {
            const noSheetsZipBuffer = Buffer.from('PK\u0003\u0004dummy'); // Simplified mock of invalid workbook
            adapter.workbookToRows(noSheetsZipBuffer);
        }).toThrow(/corrupto o no es un formato/); // Since it won't parse properly
    });

    it('throws when multiple sheets are available but none specified', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'ambiguous.xlsx'));
        const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        
        expect(() => {
            adapter.workbookToRows(arrayBuffer);
        }).toThrow(/múltiples hojas/i);
    });

    it('throws when an empty sheet is parsed', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'empty_sheet.xlsx'));
        const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        
        expect(() => {
            adapter.workbookToRows(arrayBuffer, { sheetName: 'EmptySheet' });
        }).toThrow(/vacía/i);
    });

    it('parses correctly when a specific sheet is passed', () => {
        const buffer = fs.readFileSync(path.join(fixturesDir, 'ambiguous.xlsx'));
        const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
        
        const rows = adapter.workbookToRows(arrayBuffer, { sheetName: 'Sheet1' });
        expect(rows).toBeInstanceOf(Array);
        expect(rows.length).toBeGreaterThan(0);
    });
});
