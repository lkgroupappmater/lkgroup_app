import {test} from 'node:test';
import assert from 'node:assert/strict';
import {autoPair,autoCandidates,previewAutoSelection,unionContact} from './auto-merge.mjs';
const row=(id,name,phone='02012345678')=>({id:String(id),customer_no:id,customer_code:String(id).padStart(3,'0'),name,phone,updated_at:'2026-09-27T00:00:00Z'});
const select=rows=>rows.map(({id,updated_at})=>({id,updated_at}));
test('only exact slash expansion or one phone extension; country prefixes normalize',()=>{
 assert.equal(autoPair(row(3,'A'),row(4,'B / A','+8562012345678')),true);
 assert.equal(autoPair(row(3,'A'),row(4,'A','02012345678 / 02099998888')),true);
 assert.equal(autoPair(row(3,'A'),row(4,'B')),false);
 assert.equal(autoPair(row(3,'A'),row(4,'A / B','02012345678 / 02099998888')),false);
 assert.equal(autoPair(row(3,'Alpha'),row(4,'Alphb')),false);
 assert.equal(autoPair(row(3,'A','5678'),row(4,'A / B','5678')),false);
});
test('unchecked lowest ID changes representative; all unique names and three phones retained',()=>{
 const rows=[row(5,'A','02012345678'),row(8,'A','02012345678 / 02099998888'),row(12,'A','02012345678 / 02099998888 / 02055554444')];
 const groups=autoCandidates(rows),preview=previewAutoSelection(groups,select(rows.slice(1)));
 assert.equal(preview.groups[0].customer_code,'008');assert.equal(preview.groups[0].phone,'02012345678 / 02099998888 / 02055554444');
 assert.equal(unionContact([row(5,'A'),row(6,'a / B')],'name'),'A / B');
});
test('unchecked bridge splits components; no unrelated pair is silently merged',()=>{
 const rows=[row(3,'A / B'),row(4,'A'),row(5,'A / C'),row(6,'A / C / D')];
 const preview=previewAutoSelection(autoCandidates(rows),select([rows[0],rows[2],rows[3]]));
 assert.equal(preview.groups.length,1);assert.deepEqual(preview.groups[0].members.map(c=>c.id),['5','6']);assert.equal(preview.excluded_count,1);
});
test('protected names survive aliases and transitive bridges; shipping groups start unchecked',()=>{
 const rows=[row(3,'First'),row(4,'First / Second'),row(5,'Second')];
 const aliases=[{customer_registry_id:'3',name_key:'protectedone'}],rules=[{name_key:'protectedone',separation_key:'one'},{name_key:'second',separation_key:'two'}];
 const groups=autoCandidates(rows,aliases,rules);
 assert.equal(groups[0].default_selected,false);
 assert.throws(()=>previewAutoSelection(groups,select(rows)),/SEPARATE_CUSTOMER_IDS/);
 const delivery=autoCandidates(rows,[],[],[{customer_name:'First',phone_display:'02012345678',active:true,route_key:'sea',paid_by:'선결제'}]);
 assert.equal(delivery[0].default_selected,false);assert.match(delivery[0].members[0].delivery_contexts[0],/선결제/);
});
test('stale, repeated and forged selection rejected; reserved and unknown IDs excluded',()=>{
 const rows=[row(3,'A'),row(4,'A / B')],groups=autoCandidates(rows);
 assert.throws(()=>previewAutoSelection(groups,[{id:'3',updated_at:'old'},select(rows)[1]]),/RECORD_CHANGED/);
 assert.throws(()=>previewAutoSelection(groups,[select(rows)[0],select(rows)[0]]),/AUTO_SELECTION_INVALID/);
 assert.throws(()=>previewAutoSelection(groups,[{id:'fake'}]),/AUTO_SELECTION_INVALID/);
 assert.equal(autoCandidates([row(1,'A'),row(4,'수취인 불명/A')]).length,0);
});
