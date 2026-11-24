import test from 'node:test';
import assert from 'node:assert/strict';
import {captureTemplateStyles,assertTemplateStyles,beginTemplateStyleGuard,finishTemplateStyleGuard,STYLE_CONTEXT_ENTRY} from '../supabase/functions/export-shipment-excel/template-style-guard.mjs';
import {preserveTemplateHeaderFonts} from '../supabase/functions/export-shipment-excel/template-header-macros.mjs';
import {repairApprovedTemplateHeaders} from '../supabase/functions/export-shipment-excel/template-header-repair.mjs';
import {headerReference} from '../supabase/functions/export-shipment-excel/template-header-reference.mjs';
const enc=s=>new TextEncoder().encode(s),dec=b=>new TextDecoder().decode(b);
function fixture(name='고객 리스트'){
 return {'xl/workbook.xml':enc(`<workbook><sheets><sheet name="${name}" r:id="r1"/></sheets></workbook>`),'xl/_rels/workbook.xml.rels':enc('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>'),
 'xl/styles.xml':enc('<styleSheet><numFmts count="1"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/></numFmts><fonts count="1"><font><sz val="20"/></font></fonts><fills count="1"><fill/></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0"/><xf numFmtId="164" fontId="0"><alignment horizontal="center"/></xf></cellXfs></styleSheet>'),
 'xl/worksheets/sheet1.xml':enc('<worksheet><cols><col min="1" max="2" width="20"/></cols><sheetData><row r="1" ht="30" customHeight="1"><c r="A1" s="0" t="inlineStr"><is><t>Title</t></is></c><c r="B1" s="1"><v>46344</v></c></row><row r="2"><c r="A2"/></row><row r="3"><c r="A3"/></row><row r="6"><c r="A6"><v>10</v></c></row></sheetData><mergeCells count="1"><mergeCell ref="A2:B2"/></mergeCells></worksheet>')};
}
test('all routes retain title, date, borders, alignment and geometry while values change',()=>{
 for(const name of ['고객 리스트','LKA 01','LKS 01','육로 명세서']){
  const files=fixture(name),before=captureTemplateStyles(files);
  files['xl/worksheets/sheet1.xml']=enc(dec(files['xl/worksheets/sheet1.xml']).replace('Title','New voyage').replace('46344','46345'));
  assert.equal(assertTemplateStyles(files,before).header_formats_preserved,true);
 }
});
test('a date changed to a currency style is rejected even if all formulas are valid',()=>{
 const files=fixture(),before=captureTemplateStyles(files);
 files['xl/styles.xml']=enc(dec(files['xl/styles.xml']).replace('cellXfs count="2"','cellXfs count="3"').replace('</cellXfs>','<xf numFmtId="7"/></cellXfs>'));
 files['xl/worksheets/sheet1.xml']=enc(dec(files['xl/worksheets/sheet1.xml']).replace('r="B1" s="1"','r="B1" s="2"'));
 assert.throws(()=>assertTemplateStyles(files,before),/formatting changed/);
});
test('regenerating the internal discount helper does not change a user template',()=>{
 const files=fixture('_LK_Discount_Identity'),before=captureTemplateStyles(files);
 files['xl/worksheets/sheet1.xml']=enc('<worksheet><sheetData><row r="1"/><row r="3"><c r="H3"><f>1</f><v>0</v></c></row></sheetData></worksheet>');
 assert.equal(assertTemplateStyles(files,before).protected_sheets,0);
});
test('shifting global style definitions, changing fonts and losing merges fail closed',()=>{
 for(const [path,a,b] of [['xl/styles.xml','val="20"','val="11"'],['xl/styles.xml','horizontal="center"','horizontal="left"'],['xl/worksheets/sheet1.xml','A2:B2','A2:C2']]){
  const files=fixture(),before=captureTemplateStyles(files);files[path]=enc(dec(files[path]).replace(a,b));assert.throws(()=>assertTemplateStyles(files,before),/changed/);
 }
});
test('style counts are validated and private manifest is consumed before storage',()=>{
 const files=fixture();beginTemplateStyleGuard(files);assert.ok(files[STYLE_CONTEXT_ENTRY]);assert.equal(finishTemplateStyleGuard(files).protected_header_cells,4);assert.equal(files[STYLE_CONTEXT_ENTRY],undefined);
 files['xl/styles.xml']=enc(dec(files['xl/styles.xml']).replace('cellXfs count="2"','cellXfs count="1"'));assert.throws(()=>captureTemplateStyles(files),/count mismatch/);
});
test('opening and saving retain the user font instead of restoring hard-coded sizes',()=>{
 const source=enc('Public Sub RestoreHeaderFontSizes()\r\n    SetHeaderSize s.Range("C1"), 80\r\nEnd Sub\r\nPublic Sub FitOne()\r\n    Cells(6,1).Value = 1\r\nEnd Sub');
 const fixed=preserveTemplateHeaderFonts(source);assert.doesNotMatch(dec(fixed),/SetHeaderSize/);assert.match(dec(fixed),/Cells\(6,1\).Value = 1/);assert.equal(preserveTemplateHeaderFonts(fixed),null);
});
test('approved reference contains formatting only, repairs legacy headers and respects future uploads',()=>{
 assert.equal(headerReference.source_sha256,'6bdced1d658db44022264164f4deef9193e8b15b0146a0abd8fdc8d358187225');
 assert.doesNotMatch(JSON.stringify(headerReference),/<(?:c |v>|f>|si>)/);
 const files=fixture(),original=dec(files['xl/worksheets/sheet1.xml']);
 assert.equal(repairApprovedTemplateHeaders(files,'base/new-upload.xlsm'),null);assert.equal(dec(files['xl/worksheets/sheet1.xml']),original);
 repairApprovedTemplateHeaders(files,'',{force:true});const once=dec(files['xl/styles.xml']);const content=dec(files['xl/worksheets/sheet1.xml']);
 assert.match(content,/<t>Title<\/t>/);assert.match(content,/<v>46344<\/v>/);assert.match(content,/ref="A2:B2"/);
 repairApprovedTemplateHeaders(files,'',{force:true});assert.equal(dec(files['xl/styles.xml']),once);assert.equal(dec(files['xl/worksheets/sheet1.xml']),content);
});

import {repairStatementNotices,captureStatementNotices} from '../supabase/functions/export-shipment-excel/statement-notice-format.mjs';
import {styleTables} from '../supabase/functions/export-shipment-excel/template-style-guard.mjs';
function noticeFixture({anchor=1,peer=1,custom=false}={}) {
 const files=fixture('LKS 02'),row=42;
 const styles='<styleSheet><fonts count="2"><font><sz val="11"/></font><font><b/><sz val="28"/></font></fonts><cellXfs count="3"><xf fontId="0" fillId="4" borderId="2"/><xf fontId="1" borderId="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf fontId="1"><alignment horizontal="right"/></xf></cellXfs></styleSheet>';
 files['xl/styles.xml']=enc(styles);
 files['xl/sharedStrings.xml']=enc('<sst><si><t>* 모든 비용은 원본 안내를 따릅니다</t></si></sst>');
 files['xl/worksheets/sheet1.xml']=enc('<worksheet><sheetData><row r="42" ht="41" customHeight="1"><c r="A42" s="'+anchor+'" t="s"><v>0</v></c>'+Array.from('BCDEFGHIJKLMN',c=>'<c r="'+c+row+'" s="'+(c==='H'&&custom?2:peer)+'"/>').join('')+'</row></sheetData><mergeCells count="1"><mergeCell ref="A42:N42"/></mergeCells></worksheet>');
 return files;
}
test('footer guard detects a default font, lost alignment, changed text and changed height below a moved total',()=>{
 const files=noticeFixture(),source=captureTemplateStyles(files),sheet='xl/worksheets/sheet1.xml',original=dec(files[sheet]);
 assert.equal(assertTemplateStyles(files,source).protected_statement_notices,1);
 for(const [a,b] of [['r="A42" s="1"','r="A42" s="0"'],['r="A42" s="1"','r="A42" s="2"'],['ht="41"','ht="13"']]){
  files[sheet]=enc(original.replace(a,b));
  assert.throws(()=>assertTemplateStyles(files,source),/statement notice/);
 }
 files[sheet]=enc(original);files['xl/sharedStrings.xml']=enc('<sst><si><t>* Edited in transit</t></si></sst>');
 assert.throws(()=>assertTemplateStyles(files,source),/statement notice/);
});
test('a lost merge anchor recovers its original row font and alignment without changing the other cells or its other styles',()=>{
 const files=noticeFixture({anchor:0}),sheet='xl/worksheets/sheet1.xml',original=dec(files[sheet]);
 const repair=()=>repairStatementNotices(files,styleTables(dec(files['xl/styles.xml'])));
 assert.equal(repair(),1);
 const corrected=captureStatementNotices(files)[0].notices[0];
 assert.equal(dec(files[sheet]),original.replace('r="A42" s="0"','r="A42" s="'+corrected.style+'"'));
 const xf=styleTables(dec(files['xl/styles.xml'])).cellXfs[corrected.style];
 assert.match(xf,/fontId="1"/);assert.match(xf,/horizontal="center"/);
 assert.match(xf,/fillId="4" borderId="2"/);
 assert.equal(repair(),0);
 for(const args of [{anchor:2},{anchor:0,custom:true},{anchor:0,peer:0}]){
  const other=noticeFixture(args),before=structuredClone(other);
  assert.equal(repairStatementNotices(other,styleTables(dec(other['xl/styles.xml']))),0);
  assert.deepEqual(other,before);
 }
});
