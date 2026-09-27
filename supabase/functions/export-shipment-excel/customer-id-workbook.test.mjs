import test from 'node:test';import assert from 'node:assert/strict';
import {phoneKey,phoneTokens,specialName,statementCode,makeIdentityTables,identityCargoFormulas} from './customer-id-workbook.mjs';
import {customerCodeJson,normalizeCustomerCode} from '../waybill-intake/customer-code.mjs';
const customer={id:'a',customer_no:23,name:'이경희',phone:'020 5555 1234',name_key:'이경희',phone_key:'02055551234'};
const profile={id:1,customer_name:'영문 수령인',alternate_name:'English Receiver',company_name:'',phone:'020 5555 1234',phone_display:'',delivery_type:'province',source_row:3,preferred:true};
const context={customers:[customer],aliases:[],deliveries:[profile],reviews:[]};
test('LK presentation preserves numeric identity and every digit',()=>{
 assert.equal(normalizeCustomerCode('LK 00023'),'023');assert.equal(normalizeCustomerCode('900023'),'900023');assert.equal(normalizeCustomerCode('LKS 00023'),null);
 assert.equal(JSON.stringify({customer_code:'023',id:23},customerCodeJson),'{"customer_code":"LK 00023","id":23}');assert.equal(statementCode('LKTL',123456),'LKTL 123456');
});
test('only explicit special phrases receive the 9 statement prefix',()=>{
 for(const name of ['이경희','곽낭아/이경희','이관택/정유은','JJ 2 SDG/이경희'])assert.equal(specialName(name),false);
 for(const name of ['수취인 불명 / 이경희','비엔티엔 픽업 / 이경희','시내 픽업 / 이경희','운임 따로 지불 / 이경희'])assert.equal(specialName(name),true);
 assert.equal(statementCode('LKS',23,true),'LKS 900023');
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
 const tables=makeIdentityTables(context,{prefix:'LKS',shipments:[{customer_no:23,consignee_name:'이경희',receipt_number:'LKS 17',receipt_number_locked:true}]});const r=tables.controls.find(r=>r[0]==='ID|23|0');assert.equal(r[3],'LKS 00023');assert.equal(r[5],'잠금');assert.equal(r[6],'LKS 17');assert.equal(r[7].value,'LKS 17');
 const f=identityCargoFormulas(6,1005,800,700,900,'LKS');assert.match(f.N,/명세서 번호 관리/);assert.match(f.AB,/\$BC\$6:\$BC\$1005/);assert.doesNotMatch(f.N,/AB6/);
});
