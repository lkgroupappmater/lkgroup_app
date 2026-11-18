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
