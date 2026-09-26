import {test} from 'node:test';
import assert from 'node:assert/strict';
import {oneEditApart,registrySummary,mapLimit} from './registry.mjs';
test('typo candidates require meaningful strings and tolerate an inserted or changed character',()=>{
 assert.equal(oneEditApart('박성호','박성후'),true);assert.equal(oneEditApart('Anong','Annong'),true);
 assert.equal(oneEditApart('02012345678','02012345679',8),true);assert.equal(oneEditApart('0201','0202',8),false);
 assert.equal(oneEditApart('aa','zz'),false);assert.equal(oneEditApart('','abc'),false);
});
test('merged rows are hidden; accepted alias sources no longer inflate mismatch counts',()=>{
 const rows=[{id:'a',customer_no:101,name_key:'alice',phone_key:'02012345678'},{id:'b',customer_no:102,name_key:'alice',phone_key:'02012345677',merged_into:'a'}];
 const r=registrySummary(rows,[{customer_registry_id:'a',mismatch:false},{customer_registry_id:'a',mismatch:true}]);
 assert.equal(r.summary.customers,1);assert.equal(r.summary.duplicate_customers,0);assert.equal(r.summary.mismatch_customers,1);assert.equal(r.rows[0].source_count,2);
});
test('bounded workers overlap requests, preserve order and process each item once',async()=>{
 let active=0,max=0;const seen=[];const result=await mapLimit([0,1,2,3,4,5,6],3,async n=>{active++;max=Math.max(max,active);seen.push(n);await new Promise(setImmediate);active--;return n*2;});
 assert.equal(max,3);assert.deepEqual(result,[0,2,4,6,8,10,12]);assert.equal(new Set(seen).size,7);
});

test('bulk validation keeps independent groups and strips untrusted fields',async()=>{
 const {validateBulkRows}=await import('./registry.mjs');const rows=['a','b','c','d'].map((id,i)=>({id,target_id:i<2?'b':'d',customer_no:i+3,name:' Name '+id+' ',phone:' 02011110000 ',updated_at:'2026-09-26T00:00:00Z',merged_into:'injected',role:'admin'}));
 const out=validateBulkRows(rows);assert.deepEqual(out.map(r=>r.target_id),['b','b','d','d']);assert.equal(out[0].name,'Name a');assert.equal(out[0].phone,'02011110000');assert.equal(out[0].merged_into,undefined);
 for(const bad of [[],Array(101).fill(rows[0]),[rows[0],rows[0]],[{...rows[0],target_id:'absent'}],[{...rows[0],updated_at:null},rows[1]],[{...rows[0],target_id:'b'},{...rows[1],target_id:'a'}]])assert.throws(()=>validateBulkRows(bad),/BULK_SELECTION_INVALID/);
});

test('legacy unknown-prefixed IDs are preserved in storage but not offered as separate customers',()=>{
 const rows=[{id:'real',name:'Customer',name_key:'customer',customer_no:23,phone_key:'02011110000'},{id:'old',name:'수취인 불명 / Customer',name_key:'수취인불명/customer',customer_no:52,phone_key:'02011110000'},{id:'masked',name:'히 수취인불명 / ???',customer_no:359}];
 const out=registrySummary(rows,[{customer_registry_id:'real',mismatch:false}]);assert.equal(out.rows.length,1);assert.equal(out.rows[0].customer_code,'023');assert.equal(out.summary.customers,1);assert.equal(out.rows[0].source_count,1);
});
