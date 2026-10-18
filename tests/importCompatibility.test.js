import fs from 'node:fs';
import { parseDelimitedText } from '../src/js/adapters/textAdapter.js';
import { detectFileFormat } from '../src/js/core/adapters/fileAdapter.js';
import { detectPerceptionFormat, parsePerceptionInput } from '../src/js/core/parsers/perceptionFormats.js';
import { perceptionDate, perceptionAmount } from '../src/js/core/parsers/perceptionNormalization.js';
import { parseBankRows } from '../src/js/core/parsers/bankParser.js';
import { createSheetJsAdapter } from '../src/js/core/adapters/sheetJsAdapter.js';
import * as XLSX from 'xlsx';
const fixture = name => fs.readFileSync(new URL(`./fixtures/import-compat/${name}`,import.meta.url),'utf8');
const input = name => {const text=fixture(name); return {text,arrayBuffer:new TextEncoder().encode(text).buffer,fileName:name};};

describe('Content contracts for real import structures (artificial identities)',()=>{
 test.each([
  ['known-text.xls','CABA_RENTAS_CSV_EXPORT',1,'CABA','percepcion'],
  ['positional.csv','IVA_DELIMITED_POSITIONAL',2,'NACIONAL (IVA)','percepcion'],
  ['compact.txt','SIFERE_FIXED_A',2,'CABA','percepcion'],
  ['complete.txt','SIFERE_FIXED_B',2,'CABA','percepcion'],
  ['retention.txt','RETENTION_FIXED_C',1,'ARBA','retencion']
 ])('%s detects and normalizes (%s)',(name,id,count,jurisdiction,tipo)=>{
  const parsed=parsePerceptionInput({text:fixture(name)});
  expect(parsed.format.id).toBe(id); expect(parsed.items).toHaveLength(count);
  expect(parsed.items.every(r=>!r.errors.length)).toBe(true);
  expect(parsed.items[0].normalizedData).toMatchObject({monto:123.45,jurisdiction,tipo,cuit:'30999999991'});
  expect(parsed.items[0].rawRow).toBeTruthy();
  expect(parsePerceptionInput({text:fixture(name)}).format).toEqual(parsed.format);
 });
 test('known text Excel mismatch is narrow; arbitrary text Excel fails closed',()=>{
  expect(detectFileFormat(input('known-text.xls'))).toBe('TEXT_DELIMITED');
  expect(()=>detectFileFormat({fileName:'fake.xls',text:'arbitrary fake text',arrayBuffer:new TextEncoder().encode('arbitrary fake text').buffer})).toThrow(/Inconsistencia/);
  expect(detectFileFormat({fileName:'unknown.txt',text:'unknown text',arrayBuffer:new TextEncoder().encode('unknown text').buffer})).toBe('UNKNOWN');
  expect(detectFileFormat({fileName:'unknown.csv',text:'a,b,c\nx,y,z',arrayBuffer:new TextEncoder().encode('a,b,c\nx,y,z').buffer})).toBe('UNKNOWN');
  expect(()=>detectFileFormat({fileName:'fake.xlsx',arrayBuffer:new Uint8Array([80,75,3,4,0,0,0,0]).buffer})).toThrow(/OOXML/);
 });
 test('semicolon wins over fixed width and changing filename changes no parser',()=>{
  expect(detectFileFormat(input('positional.csv'))).toBe('TEXT_DELIMITED');
  expect(detectPerceptionFormat({text:fixture('positional.csv'),fileName:'not-iva.txt'}).id).toBe('IVA_DELIMITED_POSITIONAL');
 });
 test('sep directive, quoted comma, escaped quote, multiline value, physical trace',()=>{
  const rows=parseDelimitedText('sep=,\n\na,b,c\n"a,b","line\nnext","quote""here"\n1,2,3');
  expect(rows[2]).toEqual(['a,b','line\nnext','quote"here']);
  expect(rows[2].sourceRowNumber).toBe(4); expect(rows[3].sourceRowNumber).toBe(6);
  expect(()=>parseDelimitedText('a,b\n"bad,quote')).toThrow(/comillas/);
  const p=parsePerceptionInput({text:fixture('known-text.xls')}); expect(p.items[0].sourceRowNumber).toBe(4);
  expect(p.items[0].normalizedData.razonSocial).toBe('Agente, Sintetico');
 });
 test('malformed row stages errors while good rows survive',()=>{
  const text=fixture('complete.txt')+fixture('complete.txt').split('\n')[0].replace('20260716','20260231');
  const p=parsePerceptionInput({text}); expect(p.items.filter(r=>r.normalizedData)).toHaveLength(2);
  expect(p.items[2].errors).toContain('Fecha inválida.'); expect(p.items[2].sourceRowNumber).toBe(3);
 });
 test('compact document type is separate from amount; leading blank reference is supported',()=>{
  const p=parsePerceptionInput({text:fixture('compact.txt')});
  expect(p.items.map(r=>r.normalizedData.monto)).toEqual([123.45,125.4]);
  expect(p.items[1].normalizedData.audit).toMatchObject({marker:'F',documentType:'A'});
  expect(parsePerceptionInput({text:fixture('complete.txt')}).items[1].normalizedData.comprobante.trim()).toBe('0000002');
 });
 test.each(['16/07/2026','20260716','2026-07-16'])('date %s is calendar checked',v=>expect(perceptionDate(v)).toBe('16/07/2026'));
 test.each(['20260231','31/02/2026','2026-13-01'])('bad date %s',v=>expect(perceptionDate(v)).toBeNull());
 test.each([['1.234,56',1234.56],['1234.56',1234.56],['001234,56',1234.56],['12.4',12.4],['12garbage',null]])('amount %s', (v,n)=>expect(perceptionAmount(v)).toBe(n));
 test('unknown structure and zero valid mismatch are rejected',()=>{
  expect(()=>parsePerceptionInput({text:'random text'})).toThrow(/desconocido/);
  const text=fixture('known-text.xls').replace('16/07/2026','31/02/2026');
  expect(()=>detectFileFormat({text,arrayBuffer:new TextEncoder().encode(text).buffer,fileName:'fake.xls'})).toThrow();
 });
});
describe('English bank contract supplements Spanish and BBVA',()=>{
 test('spreadsheet drops blanks as before but carries physical row provenance',()=>{
  const workbook=XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(workbook,XLSX.utils.aoa_to_sheet(JSON.parse(fixture('bank-summary.json'))),'Movements');
  const rows=createSheetJsAdapter(XLSX).workbookToRows(XLSX.write(workbook,{type:'array',bookType:'xlsx'}));
  expect(rows).toHaveLength(5);expect(rows[2].sourceRowNumber).toBe(4);expect(rows.sourceRowCount).toBe(6);
  expect(parseBankRows(rows)[0].sourceRowNumber).toBe(5);
 });
 test('summary ignored; signed movement, balance, reference, date and line retained',()=>{
  const rows=JSON.parse(fixture('bank-summary.json'));const p=parseBankRows(rows);
  expect(p).toHaveLength(2); expect(p[0].sourceRowNumber).toBe(5);
  expect(p[0].normalizedData).toMatchObject({fecha:'2026-05-01',monto:27510,tipo:'credit',saldo:33103.3,referencia:'ref001'});
  expect(p[1].normalizedData).toMatchObject({fecha:'2026-05-06',monto:33226.67,tipo:'debit',saldo:0});
 });
 test('invalid English calendar stages an error',()=>{
  const rows=JSON.parse(fixture('bank-summary.json'));rows[4][0]='31-02-2026';
  expect(parseBankRows(rows)[0].errors).toContain('Fecha inválida.');
 });
 test('existing Spanish header keeps its established representation',()=>{
  const p=parseBankRows([['Fecha','Concepto','Importe'],['29-05-2026','Comision','-500.00']]);
  expect(p[0].normalizedData).toMatchObject({fecha:'29-05-2026',monto:500,tipo:'debit'});
 });
});
