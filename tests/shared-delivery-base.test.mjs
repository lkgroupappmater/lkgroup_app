import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {planDeliveryBlocks} from '../shared-backend/export-shipment-excel/shared-delivery-blocks.mjs';
const sql=fs.readFileSync(new URL('../supabase/migrations/20261111060858_synchronize_shared_local_delivery_base.sql',import.meta.url),'utf8');
let db;
const rows=async(q,params=[]) => (await db.query(q,params)).rows;
const all=()=>rows('select * from local_delivery_profiles order by route_key,source_no');
const admin='00000000-0000-4000-8000-000000000001';
async function call(route,voyage,rules,file='test_BASE.xlsm'){
 return rows('select import_excel_workbook_policy($1,2026,$2,$3,$4) as result',[route,voyage,file,rules]);
}
async function policy(route,voyage='00') { return (await rows('select lk_excel_effective_policy($1,2026,$2) as p',[route,voyage]))[0].p; }
before(async()=>{
 db=new PGlite();
 await db.exec(fs.readFileSync(new URL('./fixtures/shared-delivery-before.sql',import.meta.url),'utf8'));
 // Same number, different people; the latest SEA address wins for the same identity.
 await db.exec(`insert into local_delivery_profiles(route_key,source_no,customer_name,phone,delivery_type,destination_address,active,preferred,updated_at) values
 ('kr_la_sea',1,'Full / Name','0201111','province','New address',true,false,'2026-10-30'),
 ('kr_la_air',1,'Full / Name','0201111','province','Old address',true,false,'2026-10-29'),
 ('th_la_land',1,'Full / Name','0201111','province','Older address',true,false,'2026-09-28'),
 ('kr_la_sea',89,'SEA person','0202222','province','SEA',true,false,'2026-10-30'),
 ('kr_la_air',89,'AIR person','0203333','province','AIR',true,false,'2026-10-29'),
 ('th_la_land',78,'City person','0204444','city','City',true,false,'2026-09-28');
 insert into excel_workbook_policies values
 ('kr_la_sea',0,'00','{"appearance":{"city":"ABCDEF","province":"FFC000"}}','SEA_BASE',null,'2026-10-30'),
 ('kr_la_air',0,'00','{"appearance":{"city":"112233"}}','AIR_BASE',null,'2026-10-29'),
 ('kr_la_air',2026,'21','{"deliveries":{"province|89":{"patch":{"paid_by":"prepaid"},"identity":{"source_no":89,"customer_name":"AIR person","phone":"0203333","delivery_type":"province"}}},"appearance":{"city":"DDDDDD"}}','voyage',null,now()),
 ('kr_la_sea',2026,'10','{"deliveries":{"province|89":{"deleted":true}}}','voyage',null,now());
 insert into excel_delivery_match_reviews values('kr_la_air','AIR person','0203333',5,'fingerprint',true);
 `);
 await db.exec('begin;'+sql+'commit;');
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
});
after(async()=>{await db.close();});
test('initial reconciliation preserves every full identity and existing IDs',async()=>{
 const data=await all(); assert.equal(data.length,8);
 assert.equal(data.find(x=>x.route_key==='th_la_land'&&x.source_no===1).destination_address,'Older address');
 assert.equal(data.find(x=>x.route_key==='th_la_land'&&x.source_no===78).customer_name,'City person');
 for(const route of ['kr_la_air','kr_la_sea'])assert.equal(data.filter(x=>x.route_key===route).length,3);
 assert.equal(data.find(x=>x.id===5).customer_name,'AIR person');
 assert.equal(data.find(x=>x.id===5).source_no,90);
 assert.equal((await rows('select count(*)::int as n from excel_delivery_match_reviews'))[0].n,1);
 assert.ok(data.filter(x=>x.customer_name==='Full / Name'&&x.route_key!=='th_la_land').every(x=>x.destination_address==='New address'));
});
test('existing voyage exception and removal follow the same customer',async()=>{
 const air=await policy('kr_la_air','21');assert.equal(air.deliveries.find(x=>x.customer_name==='AIR person').paid_by,'prepaid');
 assert.equal(air.appearance.city,'DDDDDD');
 assert.ok(!(await policy('kr_la_sea','10')).deliveries.some(x=>x.customer_name==='SEA person'));
});
test('SEA and AIR BASE writes mirror both Korea-to-Laos routes, keep IDs, and retain voyage exceptions',async()=>{
 for(const route of ['kr_la_sea','kr_la_air']){
  const before=await all(),p=await policy(route);p.deliveries.find(x=>x.source_no===1).destination_address=route+' update';
  await call(route,'00',{deliveries:p.deliveries,appearance:{city:'AABBCC'}});
  const after=await all();assert.deepEqual(after.map(x=>x.id),before.map(x=>x.id));
  assert.ok(after.filter(x=>x.source_no===1&&x.route_key!=='th_la_land').every(x=>x.destination_address===route+' update'));
  for(const target of ['kr_la_air','kr_la_sea'])assert.equal((await policy(target)).appearance.city,'AABBCC');
  assert.equal((await policy('kr_la_air','21')).deliveries.find(x=>x.customer_name==='AIR person').paid_by,'prepaid');
 }
});
test('voyage upload stays local; omitted sheets keep shared defaults',async()=>{
 const before=await all(),p=await policy('kr_la_sea');p.deliveries.find(x=>x.source_no===1).destination_address='Voyage only';
 await call('kr_la_sea','12',{deliveries:p.deliveries,appearance:{city:'123456'}},'SEA_V12.xlsm');
 assert.deepEqual(await all(),before);
 assert.equal((await policy('kr_la_sea','12')).deliveries.find(x=>x.source_no===1).destination_address,'Voyage only');
 await call('kr_la_sea','00',{deliveries:null});assert.deepEqual(await all(),before);
});
test('manual admin edits and removals mirror without losing IDs',async()=>{
 await db.exec("update local_delivery_profiles set destination_address='Manual update' where route_key='kr_la_air' and source_no=1");
 assert.ok((await all()).filter(x=>x.source_no===1&&x.route_key!=='th_la_land').every(x=>x.destination_address==='Manual update'));
 await db.exec("insert into local_delivery_profiles(route_key,source_no,customer_name,phone,delivery_type,active) values('kr_la_air',91,'Added','0205555','province',true)");
 assert.equal((await all()).filter(x=>x.source_no===91).length,2);
 await db.exec("delete from local_delivery_profiles where route_key='kr_la_sea' and source_no=91");
 assert.equal((await all()).filter(x=>x.source_no===91).length,0);
});
test('stale conflicting numbers, duplicate numbers and unauthorized users cannot mutate the common set',async()=>{
 let before=await all(),p=await policy('kr_la_air');p.deliveries.find(x=>x.source_no===89).customer_name='AIR person';
 await assert.rejects(call('kr_la_air','00',{deliveries:p.deliveries}),/최신 공통 BASE/);assert.deepEqual(await all(),before);
 p=await policy('kr_la_air');await assert.rejects(call('kr_la_air','00',{deliveries:[...p.deliveries,p.deliveries[0]]}),/중복/);assert.deepEqual(await all(),before);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",['00000000-0000-4000-8000-000000000002']);
 await assert.rejects(call('kr_la_air','00',{deliveries:[]}),/관리자/);
 await assert.rejects(db.exec("update local_delivery_profiles set notes='unauthorized' where route_key='kr_la_air'"),/관리자/);
 assert.deepEqual(await all(),before);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
});
test('explicit BASE deletions mirror, while unrelated routes stay isolated',async()=>{
 const p=await policy('kr_la_air');await call('kr_la_air','00',{deliveries:p.deliveries.filter(x=>x.source_no!==90)});
 assert.equal((await all()).filter(x=>x.source_no===90).length,0);
 await call('la_kr_air','00',{deliveries:[{source_no:1,customer_name:'Unrelated',delivery_type:'province',active:true}]});
 assert.equal((await all()).filter(x=>x.customer_name==='Unrelated').length,1);
});
test('private helpers and backup do not expose access to client roles',async()=>{
 assert.equal((await rows("select has_function_privilege('authenticated','lk_private.mirror_common_delivery()','execute') as access"))[0].access,false);
 assert.equal((await rows("select has_table_privilege('authenticated','lk_private.delivery_base_backups','select') as access"))[0].access,false);
});
test('Excel reserves exact identities before number reuse, including swapped numbers',()=>{
 const a={source_no:89,name:'SEA'},b={source_no:90,name:'AIR'};
 const old={number:89,name:'AIR'};const blocks=[old];
 const plan=planDeliveryBlocks([a,b],blocks,{key:p=>p.name,readKey:b=>b.name,create:number=>({number,name:''})});
 assert.equal(plan.assigned.get(b),old);assert.notEqual(plan.assigned.get(a),old);
 const left={number:1,name:'B'},right={number:2,name:'A'};
 const pa={source_no:1,name:'A'},pb={source_no:2,name:'B'};
 const swap=planDeliveryBlocks([pa,pb],[left,right],{key:p=>p.name,readKey:b=>b.name,create:()=>assert.fail('No new block needed')});
 assert.equal(swap.assigned.get(pa),right);assert.equal(swap.assigned.get(pb),left);
});
