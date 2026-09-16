import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as carriers from './carriers.mjs';
import * as statements from './statements.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
const statement={route:'한국->라오스 해상',shipment_year:2026,voyage:'09',receipt_number:'LKS 08'};
const id='22222222-2222-4222-8222-222222222222';
function setup({role='member',owned=true,count=7}={}){
 let handler,signed=0,parcelQueries=0,saved;
 const profile={id:'owner',role,name:'Owner',phone:'12345678',approval_status:'approved'};
 const cargo=[1,2].map(id=>({id,box_number:'S'+id,...statement,customer_id:owned?'owner':'other',consignee_name:'Receiver',consignee_phone:'87654321'}));
 const parcel=i=>({id:i===0?id:crypto.randomUUID(),carrier:['HAL','ANS','JT','LAOPOST','MIXAY'][i%5],tracking_number:'826246565762'+i,shipment_id:i%2+1,events:[],photo_path:'photo.jpg',checked_at:new Date(Date.now()+60000).toISOString(),updated_at:'2026-09-16T00:00:00Z',delivery_kind:'province',service_kind:'domestic',receiver_name:'Receiver',receiver_phone:'87654321'});
 const rows=Array.from({length:count},(_,i)=>parcel(i));
 if(rows.length>1)Object.assign(rows[1],{shipment_id:null,statement_route:statement.route,statement_year:2026,statement_voyage:'09',statement_receipt:'LKS 08'});
 rows[0].events=[{key:'old',source:'carrier',status:'delivered'},{key:'staff',source:'staff',status:'accepted'}];
 const db={auth:{getUser:async()=>({data:{user:{id:'owner'}}})},storage:{from(){return {async createSignedUrl(){signed++;return {data:{signedUrl:'https://signed.test/photo'}}}}}},
 rpc(name,args){if(name==='consume_domestic_tracking_limit')return Promise.resolve({data:true});let data=[];
  if(name==='domestic_statement_cargo'||name==='domestic_parcels_for_statement'){
   assert.equal(args.p_route,statement.route);assert.equal(args.p_year,2026);assert.equal(args.p_voyage,'09');
   data=name==='domestic_statement_cargo'?cargo:rows;if(name==='domestic_parcels_for_statement')parcelQueries++;
  } else if(name==='domestic_tracking_batches')data=[statement];else assert.fail(name);
  return {range(start,end){return Promise.resolve({data:data.slice(start,end+1)})}};
 },from(table){let filters={},write=null;const builder={select(){return this},eq(k,v){filters[k]=v;return this},update(v){write=v;return this},insert(v){write=v;return this},
  async maybeSingle(){return this.single()},async single(){
   if(table==='profiles')return {data:profile};if(table==='shipments')return {data:cargo.find(c=>c.id===filters.id)};
   if(table==='domestic_parcels'){const old=rows.find(r=>r.id===filters.id)??rows[0];if(write){saved={...old,...write};return {data:saved}}return {data:old};}assert.fail(table);
  }};return builder;}
 };
 vm.runInNewContext(source,{...carriers,...statements,createClient:()=>db,Deno:{env:{get:()=>''},serve:fn=>{handler=fn}},Request,Response,Date,crypto,Uint8Array,atob,console});
 return {get signed(){return signed},get parcelQueries(){return parcelQueries},get saved(){return saved},rows,async call(body){const r=await handler(new Request('https://local.test',{method:'POST',headers:{Authorization:'Bearer token'},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()}}};
}
test('statement lookup includes every carrier, cargo link and statement link with authorized photos',async()=>{
 const s=setup();const r=await s.call({action:'statement_lookup',...statement});
 assert.equal(r.status,200);assert.equal(r.body.parcels.length,7);assert.equal(s.signed,7);assert.equal(new Set(r.body.parcels.map(p=>p.carrier)).size,5);
 assert.equal(r.body.parcels[1].link_mode,'statement');
});
test('statement lookup pages through more than 500 waybills without dropping records',async()=>{
 const s=setup({role:'admin',count:503});const r=await s.call({action:'statement_lookup',...statement});assert.equal(r.status,200);assert.equal(r.body.parcels.length,503);
});
test('a customer cannot enumerate another recipient statement or sign their photos',async()=>{
 const s=setup({owned:false});const r=await s.call({action:'statement_lookup',...statement});assert.equal(r.status,200);assert.deepEqual(r.body.parcels,[]);assert.equal(s.signed,0);assert.equal(s.parcelQueries,0);
});
test('admin statement save resolves the real receipt and corrects carrier while retaining staff events/photo',async()=>{
 const s=setup({role:'admin'}),old=s.rows[0];const r=await s.call({action:'save',id,updated_at:old.updated_at,carrier:'ANS',tracking_number:old.tracking_number,link_mode:'statement',statement,delivery_kind:'province',service_kind:'domestic'});
 assert.equal(r.status,200);assert.equal(s.saved.statement_receipt,'LKS 08');assert.equal(s.saved.shipment_id,null);assert.equal(s.saved.photo_path,'photo.jpg');assert.deepEqual(s.saved.events.map(e=>e.source),['staff']);assert.equal(s.saved.synced_at,null);assert.equal(s.saved.checked_at,null);
});
test('invalid statement fields are rejected and recommendations remain non-binding',async()=>{
 const s=setup();assert.equal((await s.call({action:'statement_lookup',...statement,shipment_year:''})).status,400);
 assert.equal(statements.receiptKey('lks 0008'),'LKS8');assert.equal(statements.receiptKey('LKA08'),'LKA8');
 assert.deepEqual(statements.carrierRecommendation('VTE87297171657'),['HAL']);assert.deepEqual(statements.carrierRecommendation('8262465657623'),['ANS']);assert.deepEqual(statements.carrierRecommendation('UNKNOWN123456'),[]);
});
