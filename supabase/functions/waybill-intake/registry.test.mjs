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
