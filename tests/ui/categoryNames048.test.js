import {readFileSync} from 'node:fs';
import {jest} from '@jest/globals';
import {categoryNameKey,cleanCategoryName,equivalentCategory,duplicateCategoryMessage} from '../../src/js/core/categoryNames.js';
test.each(['Telefonía','  TELEFONIA  ','Telefoni\u0301a','\tTelefonía\u00a0'])('canonicalizes %s',name=>expect(categoryNameKey(name)).toBe('telefonia'));
test('normalizes repeated spaces and preserves distinct category types',()=>{
 expect(cleanCategoryName('  Honorarios\t\n Profesionales ')).toBe('Honorarios Profesionales');
 const existing={id:'canonical',name:'HONORARIOS PROFESIONALES',category_type:'EXPENSE'};
 expect(equivalentCategory(existing,' Honorarios  profesionales ','EXPENSE')).toBe(true);
 expect(equivalentCategory(existing,'Honorarios Profesionales','INCOME')).toBe(false);
});
const ui=readFileSync('src/js/ui.js','utf8');
test.each([['EXPENSE',false],['INCOME',true]])('actual creation UI validates equivalence within %s',async(type,shouldCreate)=>{
 const start=ui.indexOf('window.submitTaxCategoryForm =');const end=ui.indexOf('\n};',start)+3;
 const elements={
  'tax-category-name':{value:'  TELEFONIA '},'tax-category-type':{value:type},'tax-category-desc':{value:''},
  'btn-save-tax-category':{},'tax-category-feedback':{style:{}},'form-tax-category':{dataset:{}}
 };
 const store={canManageGlobalCatalog:()=>true,taxCategories:[{id:'canonical',name:'Telefonía',category_type:'EXPENSE'}],
  activeOrganizationId:null,isCatalogPlatformContext:()=>true,createTaxCategory:jest.fn(async()=>({id:'new'}))};
 const window={};
 new Function('window','document','appStore','UIManager','alert','cleanCategoryName','equivalentCategory','duplicateCategoryMessage',ui.slice(start,end))(
  window,{getElementById:id=>elements[id]},store,{render(){},closeModal(){}},()=>{},cleanCategoryName,equivalentCategory,duplicateCategoryMessage);
 await window.submitTaxCategoryForm();
 expect(store.createTaxCategory.mock.calls.length).toBe(shouldCreate?1:0);
 if(!shouldCreate)expect(elements['tax-category-feedback'].innerText).toBe(duplicateCategoryMessage);
});
test('prior SQL and reporting engines are not part of the explicit merge',()=>{
 const migration=readFileSync('sql/048_canonicalize_tax_categories.sql','utf8');
 expect(migration).not.toMatch(/UPDATE\s+(?:private\.)?eco_report_/i);
 expect(migration).toContain('eco_tax_categories_canonical_name_048_key');
});
