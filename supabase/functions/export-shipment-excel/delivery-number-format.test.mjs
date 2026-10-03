import test from 'node:test';
import assert from 'node:assert/strict';
import {formatDeliveryNumbers} from './delivery-number-format.mjs';
const enc=s=>new TextEncoder().encode(s),dec=s=>new TextDecoder().decode(s);
test('delivery numbers and titles recover without changing values or shared discount styles',()=>{
 const originalStyles='<styleSheet><fonts count="2"><font><sz val="11"/></font><font><b/><sz val="28"/></font></fonts><cellXfs count="2"><xf numFmtId="0" fontId="0"/><xf numFmtId="10" fontId="1" borderId="3"><alignment horizontal="center"/></xf></cellXfs></styleSheet>';
 const sheet='<worksheet><sheetData><row r="1"><c r="A1" s="1" t="inlineStr"><is><t>지방배송 고객 list</t></is></c></row><row r="2"><c r="A2" s="1" t="inlineStr"><is><t>No.</t></is></c></row><row r="3"><c r="A3" s="1"><v>7</v></c><c r="B3" s="1"><f>1/10</f><v>0.1</v></c></row></sheetData></worksheet>';
 const files={'xl/workbook.xml':enc('<workbook><sheets><sheet name="지방배송" r:id="r1"/></sheets></workbook>'),'xl/_rels/workbook.xml.rels':enc('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>'),'xl/styles.xml':enc(originalStyles),'xl/worksheets/sheet1.xml':enc(sheet),'xl/vbaProject.bin':new Uint8Array([1,2,3])};
 formatDeliveryNumbers(files,'kr_la_sea');
 const xml=dec(files['xl/worksheets/sheet1.xml']),styles=dec(files['xl/styles.xml']);
 assert.equal(xml.replace(/ s="\d+"/g,''),sheet.replace(/ s="\d+"/g,''));
 assert.match(xml,/<c r="B3" s="1"><f>1\/10<\/f><v>0.1<\/v><\/c>/);
 assert.ok(styles.includes('<xf numFmtId="10" fontId="1" borderId="3"><alignment horizontal="center"/></xf>'));
 const xfs=[...styles.match(/<cellXfs[^>]*>([\s\S]*?)<\/cellXfs>/)[1].matchAll(/<xf\b[^>]*?(?:\/>|>[\s\S]*?<\/xf>)/g)].map(m=>m[0]);
 const fonts=[...styles.match(/<fonts[^>]*>([\s\S]*?)<\/fonts>/)[1].matchAll(/<font>[\s\S]*?<\/font>/g)].map(m=>m[0]);
 for(const ref of ['A1','A2','A3']){const id=Number(xml.match(new RegExp('<c r="'+ref+'" s="(\\d+)"'))[1]),xf=xfs[id];assert.match(xf,new RegExp('numFmtId="'+(ref==='A3'?1:0)+'"'));assert.match(fonts[Number(xf.match(/fontId="(\d+)"/)[1])],/<sz val="11"/);assert.match(xf,/borderId="3"/);}
 assert.deepEqual(files['xl/vbaProject.bin'],new Uint8Array([1,2,3]));
 const once=Object.fromEntries(Object.entries(files).map(([p,b])=>[p,dec(b)]));formatDeliveryNumbers(files,'kr_la_sea');assert.deepEqual(Object.fromEntries(Object.entries(files).map(([p,b])=>[p,dec(b)])),once);
});
