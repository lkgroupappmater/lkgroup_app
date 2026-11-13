import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
let db;
const rows=async(q,p=[]) => (await db.query(q,p)).rows;
const descriptor=async route=>(await rows("select policy_summary->'common_delivery_layout' as value from shipment_excel_base_templates where route_key=$1",[route]))[0].value;
const upload=async(route,path)=>rows("update shipment_excel_base_templates set storage_path=$2,policy_summary='{}',updated_at=now() where route_key=$1",[route,path]);
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema lk_private;create schema storage;
 create table storage.objects(bucket_id text,name text);
 create sequence excel_base_revision_seq;
 create table excel_base_sync_state(route_key text primary key,revision bigint default nextval('excel_base_revision_seq'),completed_revision bigint default 0,exporter_revision text,status text default 'pending',requested_at timestamptz default now(),completed_at timestamptz,lease_token uuid,lease_until timestamptz,retry_after timestamptz,attempts int default 0,last_error text,integrity jsonb);
 create table shipment_excel_base_templates(route_key text primary key,storage_path text,file_name text,active boolean default true,updated_at timestamptz default now(),updated_by uuid,source_sha256 text,policy_summary jsonb default '{}');
 create function lk_private.lock_common_delivery() returns trigger language plpgsql as $$begin perform pg_advisory_xact_lock(hashtextextended('lk:shared-laos-delivery',0));return null;end$$;
 insert into storage.objects values('shipment-excel-templates','macro-updates/kr_la_sea/uploaded.xlsm');
 insert into shipment_excel_base_templates(route_key,storage_path,policy_summary) values('kr_la_sea','base/kr_la_sea/generated.xlsm','{"validated_source_revision":1,"source_history":["macro-updates/kr_la_sea/uploaded.xlsm"]}'),('kr_la_air','base/kr_la_air/generated.xlsm','{"validated_source_revision":2}'),('th_la_land','base/th_la_land/original.xlsm','{}');
 insert into excel_base_sync_state(route_key) values('kr_la_sea'),('kr_la_air'),('th_la_land');`);
 await db.exec(fs.readFileSync(new URL('../supabase/migrations/20261113042548_preserve_shared_delivery_layout.sql',import.meta.url),'utf8'));
});
after(async()=>db.close());
test('initial common layout uses the preserved SEA upload, not the generated file',async()=>{
 assert.deepEqual(await descriptor('kr_la_sea'),await descriptor('kr_la_air'));
 assert.equal((await descriptor('kr_la_air')).storage_path,'macro-updates/kr_la_sea/uploaded.xlsm');
 assert.equal(await descriptor('th_la_land'),null);
});
test('a new SEA or AIR upload shares its full form and queues the other BASE',async()=>{
 for(const route of ['kr_la_sea','kr_la_air']){
  const target=route==='kr_la_sea'?'kr_la_air':'kr_la_sea';
  const before=(await rows('select revision from excel_base_sync_state where route_key=$1',[target]))[0].revision;
  await upload(route,`base/${route}/new-layout.xlsm`);
  assert.deepEqual(await descriptor(route),await descriptor(target));
  assert.equal((await descriptor(target)).storage_path,`base/${route}/new-layout.xlsm`);
  assert.ok((await rows('select revision from excel_base_sync_state where route_key=$1',[target]))[0].revision>before);
 }
});
test('generated BASEs never replace the uploaded layout source',async()=>{
 const before=await descriptor('kr_la_air');
 await db.exec("update shipment_excel_base_templates set storage_path='base/kr_la_air/regenerated.xlsm',policy_summary=policy_summary||'{\"validated_source_revision\":999}'::jsonb where route_key='kr_la_air'");
 assert.deepEqual(await descriptor('kr_la_air'),before);assert.deepEqual(await descriptor('kr_la_sea'),before);
});
test('unrelated route and inactive upload never change the common layout',async()=>{
 const before=await descriptor('kr_la_air');await upload('th_la_land','base/th_la_land/updated.xlsm');
 await db.exec("update shipment_excel_base_templates set active=false,storage_path='base/kr_la_sea/inactive.xlsm',policy_summary='{}' where route_key='kr_la_sea'");
 assert.deepEqual(await descriptor('kr_la_air'),before);
});
test('the internal trigger grants no new client entry point',async()=>{
 const grants=await rows("select has_function_privilege('anon','lk_private.share_uploaded_delivery_layout()','execute') as anon,has_function_privilege('authenticated','lk_private.share_uploaded_delivery_layout()','execute') as member");
 assert.deepEqual(grants,[{anon:false,member:false}]);
});
