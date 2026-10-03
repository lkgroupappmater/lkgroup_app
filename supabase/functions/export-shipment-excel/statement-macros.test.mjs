import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {readCompound,writeCompound,decompressVba,compressVba,upgradeStatementMacros} from './statement-macros.mjs';
const bytes=name=>new Uint8Array(fs.readFileSync(new URL('./fixtures/'+name,import.meta.url)));
const text=new TextDecoder('euc-kr');
test('CFB roundtrip preserves every VBA stream, including mini streams',()=>{const c=readCompound(bytes('statement-vba.bin')),next=readCompound(writeCompound(c));for(const entry of c.entries.filter(e=>e.type===2))assert.deepEqual(next.entries.find(e=>e.name===entry.name).data,entry.data,entry.name);});
test('VBA compression covers chunk boundaries and overlapping copies',()=>{for(const length of [1,16,256,4096,9000]){const input=Uint8Array.from({length},(_,i)=>i%173);assert.deepEqual(decompressVba(compressVba(input)),input);}});
test('generator, account refresh and isolation preserve the row-fitting calculation and other buttons',()=>{
 const files={'xl/vbaProject.bin':bytes('statement-vba.bin'),'xl/drawings/button.vml':bytes('statement-buttons.vml'),'xl/worksheets/sheet1.xml':new TextEncoder().encode('<sheet>untouched formulas and numbers</sheet>')};
 const before=readCompound(files['xl/vbaProject.bin']),sheet=files['xl/worksheets/sheet1.xml'],oldButtons=text.decode(files['xl/drawings/button.vml']);
 const result=upgradeStatementMacros(files);assert.ok(result.modules>=2);assert.equal(result.grouped_sheet_guard,true);assert.equal(result.unguarded_group_refresh_found,true);assert.equal(result.buttons,1);assert.equal(files['xl/worksheets/sheet1.xml'],sheet);
 const after=readCompound(files['xl/vbaProject.bin']);
 for(const e of before.entries.filter(e=>e.type===2&&!['Module1','ThisWorkbook','_VBA_PROJECT'].includes(e.name)))assert.deepEqual(after.entries.find(n=>n.name===e.name).data,e.data,e.name);
 const oldCode=text.decode(decompressVba(before.entries.find(e=>e.name==='Module1').data)),newCode=text.decode(decompressVba(after.entries.find(e=>e.name==='Module1').data));
 assert.equal(newCode.split('Public Sub CreateInvoiceSheets02To100()')[0].replace(/    LK(?:EnsureUngrouped|RefreshInvoiceAccount s)\r\n/g,''),oldCode.split('Public Sub CreateInvoiceSheets02To100()')[0]);
 assert.doesNotMatch(newCode,/For i = 2 To 100/);assert.match(newCode,/For Each value In bills/);assert.match(newCode,/s.Range\("N2"\).Value = nm/);assert.match(newCode,/customerName/);assert.match(newCode,/If billCol = 0 Then/);
 const nextButtons=new TextDecoder().decode(files['xl/drawings/button.vml']);assert.match(nextButtons,/모든 명세서 생성/);
 for(const macro of ['FitCurrentInvoiceRows','FitAllInvoiceRows']){const shape=x=>x.match(/<v:shape\b[\s\S]*?<\/v:shape>/g).find(s=>s.includes(macro));assert.equal(shape(new TextDecoder().decode(bytes('statement-buttons.vml'))),shape(nextButtons));}
 const wb=text.decode(decompressVba(after.entries.find(e=>e.name==='ThisWorkbook').data));
 assert.match(wb,/SelectedSheets.Count > 1 Then Exit Sub/);
 const wbBefore=text.decode(decompressVba(before.entries.find(e=>e.name==='ThisWorkbook').data));
 const unchangedRefresh=source=>source.match(/Private Sub RefreshInvoice\b[\s\S]*?End Sub/)[0].replace(/    ' LK_GROUPED_SHEET_GUARD_V1[^\r]*\r\n(?:[^\r]*\r\n){3}/,'');
 assert.equal(unchangedRefresh(wb),unchangedRefresh(wbBefore));
 assert.match(newCode,/LKDefaultAccountFormula/);assert.match(newCode,/wanted = n \+ CLng\(s.Range\("W12"\).Value\) \+ 1/);
 assert.doesNotMatch(newCode,/suffix Like/);assert.match(newCode,/For Each badChar In Array/);
 assert.equal(upgradeStatementMacros(files).changed,false);
});
test('unrelated macro workbooks are not modified',()=>{const b=bytes('statement-vba.bin'),c=readCompound(b);c.entries.find(e=>e.name==='Module1').data=compressVba(new TextEncoder().encode('Attribute VB_Name = "Module1"\r\nPublic Sub SomethingElse()\r\nEnd Sub'));const files={'xl/vbaProject.bin':writeCompound(c)};const original=files['xl/vbaProject.bin'];assert.equal(upgradeStatementMacros(files).present,false);assert.equal(files['xl/vbaProject.bin'],original);});
test('current account-refresh events skip grouped tabs without changing their actions',()=>{
 const c=readCompound(bytes('statement-vba.bin'));
 const source='Attribute VB_Name = "ThisWorkbook"\r\nPrivate Sub Workbook_SheetCalculate(ByVal Sh As Object)\r\n    If TypeOf Sh Is Worksheet Then RefreshKrwAccount Sh\r\nEnd Sub\r\nPrivate Sub Workbook_SheetActivate(ByVal Sh As Object)\r\n    If TypeOf Sh Is Worksheet Then\r\n        If IsInvoiceSheet(Sh) Then\r\n            Sh.Calculate\r\n            RefreshKrwAccount Sh\r\n        End If\r\n    End If\r\nEnd Sub\r\n';
 c.entries.find(e=>e.name==='ThisWorkbook').data=compressVba(new TextEncoder().encode(source));
 const files={'xl/vbaProject.bin':writeCompound(c)};
 const result=upgradeStatementMacros(files);assert.equal(result.grouped_sheet_guard,true);
 const after=new TextDecoder().decode(decompressVba(readCompound(files['xl/vbaProject.bin']).entries.find(e=>e.name==='ThisWorkbook').data));
 assert.equal((after.match(/SelectedSheets.Count > 1 Then Exit Sub/g)||[]).length,2);
 for(const name of ['Workbook_SheetCalculate','Workbook_SheetActivate']){
  const procedure=s=>s.match(new RegExp('Private Sub '+name+'\\b[\\s\\S]*?End Sub'))[0];
  assert.equal(procedure(after).replace(/    ' LK_GROUPED_SHEET_GUARD_V1[^\r]*\r\n(?:[^\r]*\r\n){3}/g,'').replace(/    If TypeOf Sh Is Worksheet Then LKRefreshInvoiceAccount Sh\r\n/g,''),procedure(source));
 }
 assert.equal(upgradeStatementMacros(files).changed,false);
});
