import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareWorkbookFinalization,consumeWorkbookFinalization,FINALIZATION_CONTEXT_ENTRY} from './finalization-preparation.mjs';
import {STYLE_CONTEXT_ENTRY,finishTemplateStyleGuard} from './template-style-guard.mjs';
const enc=new TextEncoder(),dec=new TextDecoder();
const fixture=()=>Object.fromEntries(Object.entries({
 'xl/workbook.xml':'<workbook><sheets><sheet name="물품 입고 내역" sheetId="1" r:id="r1"/></sheets></workbook>',
 'xl/_rels/workbook.xml.rels':'<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>',
 'xl/styles.xml':'<styleSheet><cellXfs count="1"><xf/></cellXfs></styleSheet>',
 'xl/worksheets/sheet1.xml':'<worksheet><sheetData><row r="6"><c r="E6" t="inlineStr"><is><t>수취인불명/TEST</t></is></c><c r="L6"><f>IF(F6="","",MAX(20,C6*F6))</f></c><c r="O6" t="str"><v>A</v></c></row></sheetData></worksheet>',
}).map(([p,s])=>[p,enc.encode(s)]));
test('prepared and older in-flight finalizations produce identical parts and audit',()=>{
 const staged=fixture(),fallback=fixture();
 const prepared=prepareWorkbookFinalization(staged);
 assert.ok(staged[FINALIZATION_CONTEXT_ENTRY]);assert.ok(staged[STYLE_CONTEXT_ENTRY]);
 const consumed=consumeWorkbookFinalization(staged),legacy=consumeWorkbookFinalization(fallback);
 assert.deepEqual(prepared,consumed);assert.deepEqual(consumed,legacy);assert.deepEqual(staged,fallback);
 assert.equal(staged[FINALIZATION_CONTEXT_ENTRY],undefined);assert.equal(consumed.freightMinimumChanged,1);
 assert.match(dec.decode(staged['xl/worksheets/sheet1.xml']),/MAX\(20\*D6,C6\*F6\)/);
 assert.match(dec.decode(staged['xl/worksheets/sheet1.xml']),/<v>F<\/v>/);
 assert.equal(finishTemplateStyleGuard(staged).original_style_definitions_preserved,true);
});
test('reserved or malformed finalization context cannot skip required preparation',()=>{
 const files=fixture();prepareWorkbookFinalization(files);
 assert.throws(()=>prepareWorkbookFinalization(files),/already exists/);
 for(const context of [{version:2},{version:1,captureStage:'source',freightMinimumChanged:-1,calculationChain:{parts:0,relationships:0,content_types:0}}]){
  files[FINALIZATION_CONTEXT_ENTRY]=enc.encode(JSON.stringify(context));
  assert.throws(()=>consumeWorkbookFinalization(files),/Invalid Excel finalization context/);
 }
});
