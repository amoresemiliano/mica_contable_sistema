import XLSX from 'xlsx';
import {reportCsv,reportWorkbook,reportSheets,reportFilename,printReportHtml} from '../src/js/core/reporting/exports.js';
import {buildModel,buildReport} from '../src/js/core/reporting/engine.js';
import {reportingData} from './fixtures/reporting.js';
test('XLSX round trip preserves numeric values, manual audit, trace and metadata sheets',()=>{
 const report=buildReport(buildModel(reportingData()),'IVA'),book=reportWorkbook(report,XLSX);
 const reopened=XLSX.read(XLSX.write(book,{type:'buffer',bookType:'xlsx'}),{type:'buffer'});
 expect(reopened.SheetNames).toEqual(['Resumen','Calculos','Fuentes','Manuales','Metadatos']);
 const rows=XLSX.utils.sheet_to_json(reopened.Sheets.Calculos,{header:1});expect(rows.find(r=>r[2]==='IVA CF')[3]).toBe(420);
 expect(reportSheets(report).Manuales[1]).toContain('accountant');expect(reportFilename(report,'xlsx')).toBe('MICA_Empresa_de_prueba_IVA_2026-09.xlsx');
});
test('CSV neutralizes spreadsheet injection and printable PDF escapes imported text',()=>{
 const report=buildReport(buildModel(reportingData()),'IVA');report.company_name='=HYPERLINK("evil")';report.rows[0].label='<script>alert(1)</script>';report.manual_inputs[0].note='=1+1';
 expect(reportCsv(report)).toContain("'=1+1");const html=printReportHtml(report);expect(html).not.toContain('<script>');expect(html).toContain('&lt;script&gt;');
});
