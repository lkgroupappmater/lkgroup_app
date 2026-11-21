import test from 'node:test';
import assert from 'node:assert/strict';
import {approvedFontReference as reference} from '../supabase/functions/export-shipment-excel/approved-font-reference.mjs';
import {repairApprovedWorkbookFonts} from '../supabase/functions/export-shipment-excel/approved-font-repair.mjs';
import {captureTemplateStyles,assertTemplateStyles,styleTables,beginTemplateStyleGuard,refreshDeliveryStyleGuard,finishTemplateStyleGuard} from '../supabase/functions/export-shipment-excel/template-style-guard.mjs';
import {applyCustomerIdWorkbook} from '../supabase/functions/export-shipment-excel/customer-id-workbook.mjs';
const enc=s=>new TextEncoder().encode(s),dec=b=>new TextDecoder().decode(b);
const c=(ref,value,style=0)=>`<c r="${ref}" s="${style}" t="inlineStr"><is><t>${value}</t></is></c>`;
function fixture(){return {
 '[Content_Types].xml':enc('<Types/>'),
 'xl/workbook.xml':enc('<workbook><sheets><sheet name="고객 리스트" sheetId="1" r:id="r1"/><sheet name="물품 입고 내역" sheetId="2" r:id="r2"/><sheet name="지방배송" sheetId="3" r:id="r3"/><sheet name="시내배송" sheetId="4" r:id="r4"/></sheets></workbook>'),
 'xl/_rels/workbook.xml.rels':enc('<Relationships>'+[1,2,3,4].map(n=>`<Relationship Id="r${n}" Target="worksheets/sheet${n}.xml"/>`).join('')+'</Relationships>'),
 'xl/styles.xml':enc('<styleSheet><fonts count="1"><font><b/><sz val="28"/><color rgb="FFFF0000"/><name val="Wrong font"/></font></fonts><fills count="1"><fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/></patternFill></fill></fills><borders count="1"><border><left style="thin"/></border></borders><cellStyleXfs count="1"><xf fontId="0" numFmtId="0"/></cellStyleXfs><cellXfs count="1"><xf fontId="0" numFmtId="164" fillId="0" borderId="0" xfId="0"><alignment horizontal="center" wrapText="1"/></xf></cellXfs></styleSheet>'),
 'xl/worksheets/sheet1.xml':enc('<worksheet><cols><col min="1" max="5" width="25"/></cols><sheetData><row r="1" ht="33">'+c('A1','A route title')+'</row><row r="2">'+c('A2','Date')+'</row></sheetData><mergeCells count="1"><mergeCell ref="A1:E1"/></mergeCells></worksheet>'),
 'xl/worksheets/sheet2.xml':enc('<worksheet><sheetData><row r="1">'+c('B1','Cargo title')+'</row><row r="2">'+c('D2','Company')+'<c r="R2" s="0"><f>1+2</f><v>3</v></c></row></sheetData></worksheet>'),
 'xl/worksheets/sheet3.xml':enc('<worksheet><sheetData><row r="3"><c r="A3"><v>1</v></c>'+c('B3','Original Customer')+c('C3','Original Payer')+c('D3','Receiver')+c('E3','02011112222')+c('F3','HAL')+c('G3','Original address')+c('H3','사용')+'</row><row r="4">'+c('F4','ANS')+c('G4','Alternative address')+c('H4','')+'</row></sheetData><mergeCells count="1"><mergeCell ref="B3:B4"/></mergeCells></worksheet>'),
 'xl/worksheets/sheet4.xml':enc('<worksheet><sheetData><row r="3">'+c('B3','City Customer')+c('D3','City Receiver')+'</row></sheetData></worksheet>'),
 'xl/vbaProject.bin':new Uint8Array([1,2,3,4])
};}
function font(files,path,ref){const xml=dec(files[path]),cell=xml.match(new RegExp(`<c\\b[^>]*r="${ref}"[^>]*>`))[0],styles=styleTables(dec(files['xl/styles.xml'])),xf=styles.cellXfs[Number(cell.match(/\bs="(\d+)"/)?.[1]||0)];return {xf,font:styles.fonts[Number(xf.match(/\bfontId="(\d+)"/)?.[1]||0)]};}
test('uses the supplied customer/delivery fonts and the normal original cargo header only',()=>{
 const files=fixture(),vba=files['xl/vbaProject.bin'].slice(),before=styleTables(dec(files['xl/styles.xml']));
 const report=repairApprovedWorkbookFonts(files,'',{force:true});assert.ok(report.changed_cells>0);
 assert.equal(report.version,'2026-11-22.approved-fonts-v1');
 for(const [path,ref,size,name] of [['sheet1','A1',22,'맑은 고딕'],['sheet2','B1',16,'Malgun Gothic'],['sheet2','D2',9,'Malgun Gothic'],['sheet3','B3',11,'Phetsarath'],['sheet4','B3',11,'돋움']]){
  const got=font(files,`xl/worksheets/${path}.xml`,ref);assert.match(got.font,new RegExp(`<sz val="${size}"`));assert.match(got.font,new RegExp(name));assert.match(got.xf,/numFmtId="164"/);assert.match(got.xf,/horizontal="center" wrapText="1"/);
 }
 assert.match(dec(files['xl/worksheets/sheet2.xml']),/<f>1\+2<\/f><v>3<\/v>/);
 assert.match(dec(files['xl/worksheets/sheet1.xml']),/ht="33"/);assert.match(dec(files['xl/worksheets/sheet1.xml']),/A1:E1/);
 assert.deepEqual(files['xl/vbaProject.bin'],vba);
 const after=styleTables(dec(files['xl/styles.xml']));for(const table of ['fills','borders','cellStyleXfs'])assert.deepEqual(after[table],before[table]);
 const once=structuredClone(files);assert.equal(repairApprovedWorkbookFonts(files,'',{force:true}).changed_cells,0);assert.deepEqual(files,once);
});
test('does not impose the repair on future uploaded templates or copy customer data',()=>{
 const files=fixture(),before=structuredClone(files);assert.equal(repairApprovedWorkbookFonts(files,'2026-11-23T00:00:00Z'),null);assert.deepEqual(files,before);
 assert.doesNotMatch(JSON.stringify(reference),/<(?:c |v>|f>|t>|si>)/);assert.doesNotMatch(JSON.stringify(reference),/storage_paths|source_sha256|customer_name|phone_display/);
});
test('DB delivery edits keep customer font, carrier alternatives and merged layout',()=>{
 const files=fixture();repairApprovedWorkbookFonts(files,'',{force:true});const before=captureTemplateStyles(files);
 const original=font(files,'xl/worksheets/sheet3.xml','B3');
 applyCustomerIdWorkbook(files,{customers:[],aliases:[],controls:[],deliveries:[{id:7,source_no:1,original_source_no:1,source_row:3,delivery_type:'province',customer_name:'변경 고객 / Changed',alternate_name:'ຜູ້ຮັບ / Receiver',phone:'02033334444',phone_display:'020-3333-4444',paid_by:'Changed payer',local_company:'HAL',destination_address:'New delivery address',active:true}]},{managedDelivery:true,preserveDeliveryLayout:true});
 const xml=dec(files['xl/worksheets/sheet3.xml']);for(const value of ['변경 고객','Changed','Receiver','020-3333-4444','New delivery address','ANS','Alternative address'])assert.ok(xml.includes(value),value);
 assert.match(xml,/B3:B4/);assert.equal(font(files,'xl/worksheets/sheet3.xml','B3').font,original.font);assert.ok(assertTemplateStyles(files,before).delivery_fonts_preserved);
});
test('font remapping is rejected even when existing style definitions have not changed',()=>{
 const files=fixture();repairApprovedWorkbookFonts(files,'',{force:true});const before=captureTemplateStyles(files);
 files['xl/worksheets/sheet3.xml']=enc(dec(files['xl/worksheets/sheet3.xml']).replace(/(<c r="B3" s=")\d+/, '$1'+'0'));
 assert.throws(()=>assertTemplateStyles(files,before),/delivery font changed/);
});
test('copying the approved common delivery sheet refreshes the font guard baseline',()=>{
 const files=fixture();beginTemplateStyleGuard(files);
 repairApprovedWorkbookFonts(files,'',{force:true,onlyDelivery:true});refreshDeliveryStyleGuard(files);
 assert.ok(finishTemplateStyleGuard(files).delivery_fonts_preserved);
});
