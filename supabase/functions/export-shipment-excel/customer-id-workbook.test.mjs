import test from 'node:test';import assert from 'node:assert/strict';
import {phoneKey,phoneTokens,specialName,statementCode,makeIdentityTables,identityCargoFormulas} from './customer-id-workbook.mjs';
import {customerCodeJson,normalizeCustomerCode} from '../waybill-intake/customer-code.mjs';
const customer={id:'a',customer_no:23,name:'이경희',phone:'020 5555 1234',name_key:'이경희',phone_key:'02055551234'};
const profile={id:1,customer_name:'영문 수령인',alternate_name:'English Receiver',company_name:'',phone:'020 5555 1234',phone_display:'',delivery_type:'province',source_row:3,preferred:true};
const context={customers:[customer],aliases:[],deliveries:[profile],reviews:[]};
test('LK presentation preserves numeric identity and every digit',()=>{
 assert.equal(normalizeCustomerCode('LK 0023'),'023');assert.equal(normalizeCustomerCode('900023'),'900023');assert.equal(normalizeCustomerCode('LKS 0023'),null);
 assert.equal(JSON.stringify({customer_code:'023',id:23},customerCodeJson),'{"customer_code":"LK 0023","id":23}');assert.equal(statementCode('LKTL',123456),'LKTL 123456');
});
test('only explicit special phrases receive the 9 statement prefix',()=>{
 for(const name of ['이경희','곽낭아/이경희','이관택/정유은','JJ 2 SDG/이경희'])assert.equal(specialName(name),false);
 for(const name of ['수취인 불명 / 이경희','비엔티엔 픽업 / 이경희','시내 픽업 / 이경희','운임 따로 지불 / 이경희'])assert.equal(specialName(name),true);
 assert.equal(statementCode('LKS',23,true),'LKS 9023');
});
test('complete phone normalization compares individual numbers, not a suffix',()=>{
 assert.equal(phoneKey('+856 20 5555 1234'),'02055551234');assert.deepEqual(phoneTokens('020 5555 1234 / 020 9999 1234'),['02055551234','02099991234']);assert.notEqual(phoneKey('02055551234'),phoneKey('03055551234'));
});
test('phone-only and name-only matches require review',()=>{
 const tables=makeIdentityTables(context,{prefix:'LKS',deliveryRefs:new Map([[1,'L|3']]),cargoLast:12});const row=tables.delivery.find(r=>r[0]==='이경희|p02055551234');assert.equal(row[2],'');assert.equal(row[3].value,'확인 필요');
 const exact=makeIdentityTables({...context,deliveries:[{...profile,customer_name:'이경희'}]},{prefix:'LKS',deliveryRefs:new Map([[1,'L|3']]),cargoLast:12});assert.equal(exact.delivery.find(r=>r[0]==='이경희|p02055551234')[2],'L|3');
});
test('a reviewed delivery confirmation never merges customer IDs',()=>{
 const tables=makeIdentityTables({...context,customers:[customer,{...customer,id:'b',customer_no:509,name:'곽낭아/이경희',name_key:'곽낭아/이경희'}],deliveries:[{...profile,fingerprint:'version1'}],reviews:[{delivery_profile_id:1,name_key:'이경희',phone_key:customer.phone_key,profile_fingerprint:'version1',approved:true}]},{prefix:'LKS',deliveryRefs:new Map([[1,'L|3']])});
 assert.equal(tables.ids.find(r=>r[0]==='곽낭아/이경희|p02055551234')[3],509);assert.equal(tables.delivery.find(r=>r[0]==='이경희|p02055551234')[2],'L|3');assert.equal(tables.delivery.find(r=>r[0]==='곽낭아/이경희|p02055551234')[2],'');
});
test('locked and manual numbers override generated numbers independently',()=>{
 const tables=makeIdentityTables(context,{prefix:'LKS',shipments:[{customer_no:23,consignee_name:'이경희',receipt_number:'LKS 17',receipt_number_locked:true}]});const r=tables.controls.find(r=>r[0]==='ID|23|0');assert.equal(r[3],'LKS 0023');assert.equal(r[5],'잠금');assert.equal(r[6],'LKS 17');assert.equal(r[7].value,'LKS 17');
 const f=identityCargoFormulas(6,1005,800,700,900,'LKS');assert.match(f.N,/명세서 번호 관리/);assert.match(f.AB,/\$BC\$6:\$BC\$1005/);assert.doesNotMatch(f.N,/AB6/);
});

test('historical receipts remain separate even after customer IDs merge',()=>{
 const shipments=[{customer_no:23,consignee_name:'이경희',receipt_number:'LKS 05'},{customer_no:23,consignee_name:'이경희',receipt_number:'LKS 61'},{customer_no:null,consignee_name:'수취인 불명',receipt_number:'LKS XX'}];
 const {controls}=makeIdentityTables({...context,numberingMode:'legacy'},{prefix:'LKS',shipments});
 assert.deepEqual(controls.slice(5).map(r=>r[0]),['LEGACY|LKS 05','LEGACY|LKS 61','LEGACY|LKS XX']);
 assert.deepEqual(controls.slice(5).map(r=>r[7].value),['LKS 05','LKS 61','LKS XX']);
 assert.equal(controls[5][1],'LK 0023');assert.equal(controls[6][1],'LK 0023');
 assert.deepEqual(controls.slice(5).map(r=>r[12]),[1,2,3]);
 assert.equal(statementCode('LKS',68),'LKS 0068');assert.equal(statementCode('LKA',68,true),'LKA 9068');
 assert.equal(statementCode('LKS',1234,true),'LKS 91234');
});

test('spot statement ID linkage preserves pricing and survives repeated BASE refresh',async()=>{
 const {applyCustomerIdWorkbook}=await import('./customer-id-workbook.mjs'),e=new TextEncoder(),d=new TextDecoder();
 const c=(ref,v)=>`<c r="${ref}" t="inlineStr"><is><t>${v}</t></is></c>`;
 const pricing='<c r="N6"><f>C6*D6</f><v>4</v></c>';
 const files={
  'xl/workbook.xml':e.encode('<workbook><sheets><sheet name="이름(TLxx-xx)" sheetId="1" r:id="r1"/></sheets></workbook>'),
  'xl/_rels/workbook.xml.rels':e.encode('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/></Relationships>'),
  '[Content_Types].xml':e.encode('<Types></Types>'),
  'xl/worksheets/sheet1.xml':e.encode(`<worksheet><sheetData><row r="1">${c('L1','번호(No.)')}${c('M1','LKTL2026xx-xx')}</row><row r="2">${c('I2','고객명/회사명')}${c('L2','이경희')}</row><row r="4">${c('L4','020 5555 1234')}</row><row r="6">${pricing}</row></sheetData></worksheet>`),
  'xl/vbaProject.bin':new Uint8Array([1,2,3]),
 };
 for(let i=0;i<2;i++){
  const result=applyCustomerIdWorkbook(files,{...context,deliveries:[]},{prefix:'LKTL',base:true});assert.equal(result.spotCount,1);
  const source=d.decode(files['xl/worksheets/sheet1.xml']);assert.ok(source.includes(pricing));assert.match(source,/명세서 고객 ID 연결/);assert.match(source,/LKTL 0023/);
  assert.equal((d.decode(files['xl/workbook.xml']).match(/name="명세서 고객 ID 연결"/g)||[]).length,1);
 }
 assert.deepEqual([...files['xl/vbaProject.bin']],[1,2,3]);
});

test('latest policy inputs refresh without rewriting money or Remark formulas',async()=>{
 const {applyCustomerIdWorkbook}=await import('./customer-id-workbook.mjs');const e=new TextEncoder(),d=new TextDecoder();
 const c=(ref,text)=>`<c r="${ref}" t="inlineStr"><is><t>${text}</t></is></c>`;
 const files={
  'xl/workbook.xml':e.encode('<workbook><sheets><sheet name="Row data" sheetId="1" r:id="r1"/><sheet name="Remark 및 특이사항" sheetId="2" r:id="r2"/></sheets></workbook>'),
  'xl/_rels/workbook.xml.rels':e.encode('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/></Relationships>'),
  '[Content_Types].xml':e.encode('<Types></Types>'),
  'xl/worksheets/sheet1.xml':e.encode(`<worksheet><sheetData><row r="7">${c('H7','기업 할인 고객 리스트')}</row><row r="8">${c('H8','이름')}${c('K8','전화번호')}${c('L8','할인율')}</row><row r="9">${c('H9','테스트 고객')}${c('K9','02055551234')}<c r="L9"><v>0.1</v></c><c r="M9"><f>SUM(A1:A5)</f><v>99</v></c></row><row r="10">${c('H10','')}</row></sheetData></worksheet>`),
  'xl/worksheets/sheet2.xml':e.encode(`<worksheet><sheetData><row r="3">${c('A3','1')}${c('B3','테스트 고객')}${c('C3','02055551234')}${c('D3','기존 메모')}<c r="E3"><f>B3&amp;C3</f><v>unchanged</v></c></row></sheetData></worksheet>`),
  'xl/vbaProject.bin':new Uint8Array([1,2,3]),
 };
 applyCustomerIdWorkbook(files,{...context,deliveries:[],discounts:[{id:1,customer_name:'테스트 고객',phone:'02055551234',discount_percent:.2,special_discount_percent:0,group_name:'기업 할인',active:true}],shares:[{id:2,source_no:1,customer_name:'테스트 고객',phone:'02055551234',content:'최신 메모',active:true}]},{prefix:'LKS',base:true});
 const prices=d.decode(files['xl/worksheets/sheet1.xml']),remarks=d.decode(files['xl/worksheets/sheet2.xml']);
 assert.match(prices,/<c r="L9"><v>0.2<\/v>/);assert.match(prices,/<f>SUM\(A1:A5\)<\/f><v>99<\/v>/);
 assert.match(remarks,/최신 메모/);assert.match(remarks,/<f>B3&amp;C3<\/f><v>unchanged<\/v>/);assert.deepEqual([...files['xl/vbaProject.bin']],[1,2,3]);
});
