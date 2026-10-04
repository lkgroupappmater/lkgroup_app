import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {readCompound,decompressVba,upgradeStatementMacros} from './statement-macros.mjs';
import {addStatementTabColors} from './statement-tab-colors.mjs';
const encode=s=>new TextEncoder().encode(s),decode=b=>new TextDecoder().decode(b);
test('tab color extends the existing generator with no extra VBA procedure or button',()=>{
 const source='Public Sub CreateInvoiceSheets02To100()\r\n    CreateCurrentVoyageInvoiceSheets\r\nEnd Sub\r\nPublic Sub CreateCurrentVoyageInvoiceSheets()\r\n    For Each value In bills\r\n        FitOne s\r\n    Next value\r\nEnd Sub\r\n';
 const updated=decode(addStatementTabColors(encode(source)));
 assert.deepEqual([...updated.matchAll(/(?:Sub|Function) (\w+)/g)].map(m=>m[1]),[...source.matchAll(/(?:Sub|Function) (\w+)/g)].map(m=>m[1]));
 assert.match(updated,/s\.Tab\.Color = deliveryCell\.DisplayFormat\.Interior\.Color/);
 assert.match(updated,/StrComp\(Trim\$\(CStr\(customers\.Cells\(r, billCol\)\.Value2\)\), nm, vbTextCompare\)/);
 assert.match(updated,/Set deliveryCell = customers\.Cells\(r, billCol \+ 4\)/);
 assert.match(updated,/s\.Tab\.ColorIndex = xlColorIndexNone/);
 assert.equal(addStatementTabColors(encode(updated)),null);
 assert.equal(updated.replace('    Dim deliveryCell As Range, deliveryText As String\r\n','').replace(/        ' LK_DELIVERY_TAB_COLORS_V1[\s\S]*?        Next r\r\n/,''),source);
});
test('real workbook upgrades contain one tab-color block and retain the original button entry point',()=>{
 const files={'xl/vbaProject.bin':new Uint8Array(fs.readFileSync(new URL('./fixtures/statement-vba.bin',import.meta.url)))};
 upgradeStatementMacros(files);
 const c=readCompound(files['xl/vbaProject.bin']),source=decode(decompressVba(c.entries.find(e=>e.name==='Module1').data));
 assert.equal((source.match(/LK_DELIVERY_TAB_COLORS_V1/g)||[]).length,1);
 assert.equal((source.match(/Public Sub CreateInvoiceSheets02To100\(\)/g)||[]).length,1);
 assert.equal((source.match(/Public Sub CreateCurrentVoyageInvoiceSheets\(\)/g)||[]).length,1);
 assert.ok(Math.max(...source.split('\n').map(line=>line.length))<1023);
 assert.equal(upgradeStatementMacros(files).changed,false);
});
