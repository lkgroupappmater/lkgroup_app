import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {fitStatementButtons,addStatementDefaultTabs} from './statement-presentation.mjs';
import {renameStatementButtons} from './statement-button-labels.mjs';
import {addSpecialStatementButtons} from './statement-special.mjs';
import {upgradeStatementMacros,readCompound,decompressVba} from './statement-macros.mjs';
import {applyTaxStatementColors,stripStatementPresentation} from './statement-tax-colors.mjs';
const enc=s=>new TextEncoder().encode(s),dec=b=>new TextDecoder().decode(b);
test('36-point captions fit the existing all button and a taller two-line special button',()=>{
 const shape=fs.readFileSync(new URL('./fixtures/statement-button-drawing.xml',import.meta.url),'utf8');
 const files={
  'xl/drawings/drawing1.xml':enc(`<xdr:wsDr><xdr:twoCellAnchor><xdr:from><xdr:col>15</xdr:col><xdr:row>12</xdr:row></xdr:from><xdr:to><xdr:col>18</xdr:col><xdr:row>14</xdr:row></xdr:to>${shape}<xdr:clientData fPrintsWithSheet="0"/></xdr:twoCellAnchor></xdr:wsDr>`),
  'xl/drawings/vmlDrawing1.vml':new Uint8Array(fs.readFileSync(new URL('./fixtures/statement-buttons.vml',import.meta.url))),
 };
 renameStatementButtons(files);addSpecialStatementButtons(files);
 const before=dec(files['xl/drawings/vmlDrawing1.vml']);assert.equal(fitStatementButtons(files),2);
 const xml=dec(files['xl/drawings/drawing1.xml']),anchors=[...xml.matchAll(/<xdr:twoCellAnchor\b[\s\S]*?<\/xdr:twoCellAnchor>/g)].map(m=>m[0]);
 assert.match(anchors[0],/<xdr:row>12<\/xdr:row>/);assert.match(anchors[0],/<xdr:row>14<\/xdr:row>/);
 for(const m of xml.matchAll(/\bsz="(\d+)"/g))assert.equal(m[1],'3600');
 assert.deepEqual([...anchors[1].matchAll(/<a:t>([^<]+)<\/a:t>/g)].map(m=>m[1]),['대량 및 특이','명세서 생성']);
 assert.match(anchors[1],/<xdr:row>15<\/xdr:row>/);assert.match(anchors[1],/<xdr:row>18<\/xdr:row>/);
 const vml=dec(files['xl/drawings/vmlDrawing1.vml']);assert.match(vml,/size="720"/);
 const actions=s=>[...s.matchAll(/<x:FmlaMacro>(.*?)<\/x:FmlaMacro>/g)].map(m=>m[1]);assert.deepEqual(actions(vml),actions(before));
 assert.equal(fitStatementButtons(files),0);
});
test('generated invoice tabs test real content before yellow, delivery and tax precedence',()=>{
 const files={'xl/vbaProject.bin':new Uint8Array(fs.readFileSync(new URL('./fixtures/statement-vba.bin',import.meta.url)))};
 upgradeStatementMacros(files);const c=readCompound(files['xl/vbaProject.bin']),source=dec(decompressVba(c.entries.find(e=>e.name==='Module1').data));
 assert.match(source,/If LKInvoiceHasContent\(s\) Then\r\n            s.Tab.Color = RGB\(255, 255, 0\)/);
 assert.match(source,/If LKInvoiceIsTax\(s\) Then s.Tab.Color = RGB\(191, 191, 191\)\r\n        End If/);
 assert.match(source,/Not item.HasFormula And Not IsError\(item.Value2\)/);
 assert.equal((source.match(/Private Function LKInvoiceHasContent/g)||[]).length,1);
 assert.equal(addStatementDefaultTabs(new TextEncoder().encode(source)),null);
 assert.equal(upgradeStatementMacros(files).changed,false);
});
test('saved tabs distinguish blank forms, cargo, manual entries, delivery and zero-rated tax',()=>{
 const names=['고객 리스트','물품 입고 내역','LKA 01','LKA 02','LKA 03','LKA 04','LKA 05','LKA 06','Row data'];
 const files={
  'xl/workbook.xml':enc(`<workbook><sheets>${names.map((name,i)=>`<sheet name="${name}" r:id="r${i}"/>`).join('')}</sheets></workbook>`),
  'xl/_rels/workbook.xml.rels':enc(`<Relationships>${names.map((_,i)=>`<Relationship Id="r${i}" Target="worksheets/sheet${i}.xml"/>`).join('')}</Relationships>`),
  'xl/styles.xml':enc('<styleSheet><dxfs count="1"><dxf><fill><patternFill patternType="solid"><fgColor rgb="FFFFC000"/></patternFill></fill></dxf></dxfs></styleSheet>'),
 };
 const cell=(ref,value,f='')=>`<c r="${ref}" t="str">${f?`<f>${f}</f>`:''}<v>${value}</v></c>`;
 const sheet=(body,color='FFFFFF00')=>`<worksheet><sheetPr codeName="Sheet">${color?`<tabColor rgb="${color}"/>`:''}</sheetPr><sheetData>${body}</sheetData><pageMargins/></worksheet>`;
 files['xl/worksheets/sheet0.xml']=enc(sheet(cell('A4','LKA 03')+cell('DM4','지방배송')).replace('<pageMargins/>','<conditionalFormatting sqref="E4:E20"><cfRule dxfId="0" priority="1"><formula>$DM4="지방배송"</formula></cfRule></conditionalFormatting><pageMargins/>'));
 files['xl/worksheets/sheet1.xml']=enc(sheet(cell('N6','LKA 02')+cell('N7','LKA 03')+cell('R7','지방배송')+cell('N8','LKA 04')+cell('P8','영세율 세금계산서')));
 for(let i=2;i<8;i++)files[`xl/worksheets/sheet${i}.xml`]=enc(sheet(cell('N2',names[i])+cell('R6','16')+cell('A6','1')+cell('B6',i===6?'Manual cargo':'','')+cell('W14','Default bank account')));
 files['xl/worksheets/sheet8.xml']=enc(sheet(cell('B6','Utility'),'FF0000FF'));
 const before={...files};applyTaxStatementColors(files);
 const colors=[2,3,4,5,6,7].map(i=>dec(files[`xl/worksheets/sheet${i}.xml`]).match(/<tabColor rgb="([^"]+)"\/>/)?.[1]||null);
 assert.deepEqual(colors,[null,'FFFFFF00','FFFFC000','FFBFBFBF','FFFFFF00',null]);
 assert.equal(files['xl/worksheets/sheet8.xml'],before['xl/worksheets/sheet8.xml']);
 for(const p in files)if(p.startsWith('xl/worksheets/'))assert.equal(stripStatementPresentation(dec(files[p])),stripStatementPresentation(dec(before[p])));
 assert.equal(applyTaxStatementColors(files),0);
});
