import test from 'node:test';
import assert from 'node:assert/strict';
import {validateWorkbookFormulas} from './workbook-integrity.mjs';
const files=cells=>({'xl/worksheets/sheet1.xml':new TextEncoder().encode(`<worksheet><sheetData><row r="1">${cells}</row></sheetData></worksheet>`)});
test('formula validation keeps shared masters, followers and ordinary caches distinct',()=>{
 const xml='<c r="A1"><f t="shared" si="0" ref="A1:A2">IF(B1=&quot;&lt;f&gt;&quot;,1,0)</f><v>0</v></c><c r="A2"><f t="shared" si="0"/><v/></c><c r="B1"/><c r="C1"><f>SUM(1,2)</f></c>';
 assert.deepEqual(validateWorkbookFormulas(files(xml)),{sheet_count:1,formula_count:3,shared_group_count:1,shared_formula_errors:0});
});
test('single-pass validation still rejects malformed formula groups and duplicate records',()=>{
 const cases=[
  ['<c r="A1"/><c r="A1"/>',/duplicate cell/],
  ['<c r="A1"><f>1</f><f>2</f></c>',/duplicate formula\/cache/],
  ['<c r="A1"><v/><v>2</v></c>',/duplicate formula\/cache/],
  ['<c r="A1"><f t="shared" si="0"/></c>',/0 masters/],
  ['<c r="A1"><f t="shared" si="0" ref="A1:A2">1</f></c><c r="A2"><f t="shared" si="0" ref="A1:A2">2</f></c>',/2 masters/],
  ['<c r="A1"><f t="shared" ref="A1">1</f></c>',/shared formula/],
  ['<c r="A1"><f t="shared" si="0" ref="A1">1</f></c><c r="A2"><f t="shared" si="0"/></c>',/invalid range/],
  ['<c r="A1"><f t="shared" si="0">1</f></c>',/invalid range/],
 ];
 for(const [xml,error] of cases)assert.throws(()=>validateWorkbookFormulas(files(xml)),error);
});
