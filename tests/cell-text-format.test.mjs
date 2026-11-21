import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as fflate from 'fflate';
import {inlineRichTextStrings,preserveCellText,richTextBody,richTextValue} from '../supabase/functions/export-shipment-excel/cell-text-format.mjs';
import {captureTemplateStyles,assertTemplateStyles} from '../supabase/functions/export-shipment-excel/template-style-guard.mjs';
import {applyCustomerIdWorkbook} from '../supabase/functions/export-shipment-excel/customer-id-workbook.mjs';
const enc=s=>new TextEncoder().encode(s),dec=b=>new TextDecoder().decode(b);
const rich='<r><rPr><b/><sz val="20"/><color rgb="FFFF0000"/><rFont val="맑은 고딕"/></rPr><t>Kor-Lao Sea 22항차 고객 리스트 (</t></r><r><rPr><b/><sz val="20"/><color rgb="FF000000"/><rFont val="Phetsarath OT"/></rPr><t>ລາຍການລູກຄ້າ</t></r><r><t>)</t></r>';
function fixture(){return {
 '[Content_Types].xml':enc('<Types></Types>'),
 'xl/workbook.xml':enc('<workbook><sheets><sheet name="고객 리스트" sheetId="1" r:id="r1"/><sheet name="지방배송" sheetId="2" r:id="r2"/></sheets></workbook>'),
 'xl/_rels/workbook.xml.rels':enc('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/></Relationships>'),
 'xl/styles.xml':enc('<styleSheet><fonts count="1"><font><sz val="11"/></font></fonts><cellXfs count="1"><xf fontId="0" numFmtId="0"/></cellXfs></styleSheet>'),
 'xl/sharedStrings.xml':enc('<sst><si>'+rich+'</si></sst>'),
 'xl/worksheets/sheet1.xml':enc('<worksheet><sheetData><row r="1"><c r="A1" s="0" t="s"><v>0</v></c></row></sheetData></worksheet>'),
 'xl/worksheets/sheet2.xml':enc('<worksheet><sheetData><row r="1"><c r="A1" s="0" t="s"><v>0</v></c></row><row r="3"><c r="A3"><v>1</v></c><c r="B3" t="inlineStr"><is><t>Test Customer</t></is></c><c r="E3" t="inlineStr"><is><t>02011112222</t></is></c><c r="F3" s="0" t="s"><v>0</v></c><c r="G3" t="inlineStr"><is><t>Address</t></is></c><c r="H3" t="inlineStr"><is><t>사용</t></is></c></row></sheetData></worksheet>')
};}
const get=(files,path,ref)=>dec(files[path]).match(new RegExp(`<c\\b[^>]*r="${ref}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0];
test('unchanged shared and inline mixed text keeps every font, size and colour run',()=>{
 const files=fixture(),before=captureTemplateStyles(files);inlineRichTextStrings(files);
 const original=get(files,'xl/worksheets/sheet1.xml','A1');
 assert.equal(richTextBody(original),rich);
 assert.equal(preserveCellText(original,richTextValue(rich)),original);
 assert.equal(assertTemplateStyles(files,before).protected_rich_text_cells,3);
});
test('changing only a voyage number keeps Korean and Lao run formatting',()=>{
 const files=fixture();inlineRichTextStrings(files);const before=captureTemplateStyles(files);
 const original=get(files,'xl/worksheets/sheet1.xml','A1');
 const changed=preserveCellText(original,richTextValue(rich).replace('22항차','123항차'));
 assert.match(changed,/123항차/);assert.match(changed,/<color rgb="FF000000"\/><rFont val="Phetsarath OT"\/>/);
 assert.match(changed,/<sz val="20"\/>/);
 files['xl/worksheets/sheet1.xml']=enc(dec(files['xl/worksheets/sheet1.xml']).replace(original,()=>changed));
 assert.equal(assertTemplateStyles(files,before).rich_text_formats_preserved,true);
});
test('delivery DB refresh with the same carrier does not flatten its original text',()=>{
 const files=fixture();inlineRichTextStrings(files);const original=get(files,'xl/worksheets/sheet2.xml','F3'),before=captureTemplateStyles(files);
 applyCustomerIdWorkbook(files,{customers:[],aliases:[],controls:[],deliveries:[{id:1,source_row:3,delivery_number:1,delivery_type:'province',customer_name:'Test Customer',phone:'02011112222',local_company:richTextValue(rich),destination_address:'Address',active:true}]},{managedDelivery:true,preserveDeliveryLayout:true});
 assert.equal(get(files,'xl/worksheets/sheet2.xml','F3'),original);
 assert.equal(assertTemplateStyles(files,before).rich_text_formats_preserved,true);
});
test('the final guard rejects flattened delivery or customer text even when cell styles match',()=>{
 for(const path of ['xl/worksheets/sheet1.xml','xl/worksheets/sheet2.xml']){
  const files=fixture();inlineRichTextStrings(files);const before=captureTemplateStyles(files);
  files[path]=enc(dec(files[path]).replace('<is>'+rich+'</is>','<is><t>'+richTextValue(rich)+'</t></is>'));
  assert.throws(()=>assertTemplateStyles(files,before),/rich text formatting removed/);
 }
});
test('the actual exporter text update preserves rich title runs',async()=>{
 const root=new URL('../supabase/functions/export-shipment-excel/',import.meta.url);
 let source=fs.readFileSync(new URL('index.ts',root),'utf8').split('Deno.serve(')[0];
 const imports={};for(const m of source.matchAll(/^import\s*\{([^}]+)\}\s*from\s*'([^']+)';/gm)){
  const mod=m[2]==='npm:fflate@0.8.2'?fflate:m[2].startsWith('./')?await import(new URL(m[2],root)):null;if(!mod)continue;
  for(const name of m[1].split(',').map(s=>s.trim()))imports[name]=mod[name];
 }
 const context=vm.createContext({...imports,console,TextEncoder,TextDecoder,Uint8Array,Map,Set,Intl});
 vm.runInContext(stripTypeScriptTypes(source.replace(/^import[^;]+;\s*/gm,'')),context);
 context.files=fixture();inlineRichTextStrings(context.files);
 const before=captureTemplateStyles(context.files);
 vm.runInContext(`seedCustomerListFromShipments(files,[],'kr_la_sea','23')`,context);
 const changed=get(context.files,'xl/worksheets/sheet1.xml','A1');
 assert.match(changed,/23항차/);assert.match(changed,/Phetsarath OT/);assert.equal(assertTemplateStyles(context.files,before).rich_text_formats_preserved,true);
});
