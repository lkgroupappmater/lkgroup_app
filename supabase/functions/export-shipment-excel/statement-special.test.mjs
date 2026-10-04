import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {hasSpecialRemark,addSpecialStatementButtons} from './statement-special.mjs';
import {renameStatementButtons} from './statement-button-labels.mjs';
import {upgradeStatementMacros,readCompound,decompressVba} from './statement-macros.mjs';
test('routine discounts and Kakao advance sharing alone do not select a special statement',()=>{
 for(const value of ['', '할인율 10%', '라선협 할인 20% 적용', '대표 고정 할인 100% 적용', '카톡 선공유', '한국 카톡 명세서 선공유 및 온라인 결재 / 라선협 할인 5% 적용'])assert.equal(hasSpecialRemark(value),false,value);
 for(const value of ['지방배송(선결제)','시내배송','영세율 세금 계산서','일반 과세 세금계산서','별도 계좌 확인','카톡 선공유 / 집안 전달','할인율 10% / 금액 확인 필요','특별할인 $20','123456789'])assert.equal(hasSpecialRemark(value),true,value);
});
test('extra button is a visible, nonprinting shape with one new action and no duplicate legacy ID',()=>{
 const shape=fs.readFileSync(new URL('./fixtures/statement-button-drawing.xml',import.meta.url),'utf8');
 const original=`<xdr:wsDr><xdr:twoCellAnchor><xdr:from><xdr:col>15</xdr:col><xdr:row>12</xdr:row></xdr:from><xdr:to><xdr:col>18</xdr:col><xdr:row>14</xdr:row></xdr:to>${shape}<xdr:clientData fPrintsWithSheet="0"/></xdr:twoCellAnchor></xdr:wsDr>`;
 const files={'xl/drawings/drawing1.xml':new TextEncoder().encode(original)};
 renameStatementButtons(files);const before=new TextDecoder().decode(files['xl/drawings/drawing1.xml']);
 assert.equal(addSpecialStatementButtons(files),1);
 const after=new TextDecoder().decode(files['xl/drawings/drawing1.xml']);
 assert.ok(after.includes('대량 및 특이 명세서 생성'));
 assert.ok(after.includes('macro="[0]!CreateBulkSpecialInvoiceSheets"'));
 assert.equal(after.replace(/<xdr:twoCellAnchor editAs="absolute">[\s\S]*?<\/xdr:twoCellAnchor>/,''),before);
 const ids=[...after.matchAll(/<xdr:cNvPr\b[^>]*id="(\d+)"/g)].map(m=>m[1]);assert.equal(ids.length,new Set(ids).size);
 assert.equal(addSpecialStatementButtons(files),0);
});
test('both public actions share the generator and special mode uses actual receipt rows',()=>{
 const files={'xl/vbaProject.bin':new Uint8Array(fs.readFileSync(new URL('./fixtures/statement-vba.bin',import.meta.url)))};
 upgradeStatementMacros(files);const c=readCompound(files['xl/vbaProject.bin']);const source=new TextDecoder().decode(decompressVba(c.entries.find(e=>e.name==='Module1').data));
 assert.match(source,/Public Sub CreateBulkSpecialInvoiceSheets\(\)\r\n    LKCreateInvoiceSheets True/);
 assert.match(source,/Public Sub CreateCurrentVoyageInvoiceSheets\(\)\r\n    LKCreateInvoiceSheets False/);
 assert.match(source,/If n = 0 Then Exit Function/);
 assert.match(source,/special Or n \+ extra \+ 1 >= 11/);
 assert.match(source,/If LKInvoiceIsTax\(s\) Then s.Tab.Color = RGB\(191, 191, 191\)/);
 assert.equal((source.match(/Public Sub CreateBulkSpecialInvoiceSheets\(/g)||[]).length,1);
 assert.equal(upgradeStatementMacros(files).changed,false);
});
