import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {renameStatementButtons} from './statement-button-labels.mjs';
const encode=s=>new TextEncoder().encode(s),decode=b=>new TextDecoder().decode(b);
const fixture=name=>new Uint8Array(fs.readFileSync(new URL('./fixtures/'+name,import.meta.url)));
test('DrawingML and VML copies both show the new label without changing actions or formatting',()=>{
 const files={'xl/drawings/drawing3.xml':fixture('statement-button-drawing.xml'),'xl/drawings/vmlDrawing3.vml':fixture('statement-buttons.vml'),'xl/vbaProject.bin':fixture('statement-vba.bin'),'xl/worksheets/sheet1.xml':encode('<sheet>Original data</sheet>')};
 const before={...files},result=renameStatementButtons(files);
 assert.equal(result.buttons,2);
 assert.equal([...decode(files['xl/drawings/drawing3.xml']).matchAll(/<a:t>(.*?)<\/a:t>/g)].map(m=>m[1]).join(''),'모든 명세서 생성');
 const stripText=s=>s.replace(/(<a:t\b[^>]*>)[\s\S]*?(<\/a:t>)/g,'$1$2');
 assert.equal(stripText(decode(files['xl/drawings/drawing3.xml'])),stripText(decode(before['xl/drawings/drawing3.xml'])));
 const actions=s=>[...s.matchAll(/<x:FmlaMacro>(.*?)<\/x:FmlaMacro>/g)].map(m=>m[1]);
 assert.deepEqual(actions(decode(files['xl/drawings/vmlDrawing3.vml'])),actions(decode(before['xl/drawings/vmlDrawing3.vml'])));
 assert.equal(files['xl/vbaProject.bin'],before['xl/vbaProject.bin']);
 assert.equal(files['xl/worksheets/sheet1.xml'],before['xl/worksheets/sheet1.xml']);
 assert.equal(renameStatementButtons(files).changed,false);
});
test('sea captions, split runs and ribbon labels update while unrelated labels remain intact',()=>{
 const drawing=decode(fixture('statement-button-drawing.xml')).replace('LKA 02~100','LKS 02~100');
 const unrelated='<xdr:sp><a:t>현재 명세서 행 맞춤</a:t></xdr:sp>';
 const files={'xl/drawings/drawing1.xml':encode(drawing+unrelated),'customUI/customUI.xml':encode('<button label="LKS 02~100 생성" onAction="CreateInvoiceSheets02To100"/><button label="전체 명세서 행 맞춤"/>')};
 assert.equal(renameStatementButtons(files).buttons,2);
 assert.ok(decode(files['xl/drawings/drawing1.xml']).endsWith(unrelated));
 assert.equal(decode(files['customUI/customUI.xml']),'<button label="모든 명세서 생성" onAction="CreateInvoiceSheets02To100"/><button label="전체 명세서 행 맞춤"/>');
});
