import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as carriers from './carriers.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
function setup({role='member',active=true,authenticated=true,rate=true,shipments=[],parcels=[]}={}){
 let handler,mutations=0;
 const profile={id:'user',role,approval_status:active?'approved':'pending',deletion_status:null};
 const db={auth:{getUser:async()=>({data:{user:authenticated?{id:'user'}:null},error:!authenticated})},rpc:async()=>({data:rate}),from(table){
  if(table==='profiles')return {select(){return this},eq(){return this},async maybeSingle(){return {data:profile}}};
  assert.ok(['shipments','domestic_parcels'].includes(table));
  let rows=table==='shipments'?[...shipments]:[...parcels];
  return {select(){return this},order(){return this},
   eq(k,v){rows=rows.filter(r=>r[k]===v);return this},
   is(k,v){rows=rows.filter(r=>(r[k]??null)===v);return this},
   ilike(k,v){const exact=v.replace(/\\_/g,'_').toLowerCase();rows=rows.filter(r=>String(r[k]??'').toLowerCase()===exact);return this},
   in(k,values){rows=rows.filter(r=>values.includes(r[k]));return this},
   limit(n){rows=rows.slice(0,n);return this},range(a,b){rows=rows.slice(a,b+1);return this},
   async maybeSingle(){return {data:rows[0]??null}},then(resolve,reject){return Promise.resolve({data:rows}).then(resolve,reject)}
  };
 }};
 vm.runInNewContext(source,{...carriers,createClient:()=>db,Deno:{env:{get:()=>''},serve:fn=>{handler=fn}},Request,Response,Date,crypto,Uint8Array,atob,console});
 return async(body,token='token',method='POST')=>{
  const response=await handler(new Request('https://local.test',{method,headers:{...(token?{Authorization:`Bearer ${token}`}:{})},...(method==='POST'?{body:JSON.stringify(body)}:{})}));
  return {status:response.status,body:await response.json(),mutations};
 };
}
test('unauthenticated and inactive accounts cannot read waybill data',async()=>{
 assert.equal((await setup()({action:'lookup'},'')).status,401);
 assert.equal((await setup({authenticated:false})({action:'lookup'})).status,401);
 assert.equal((await setup({active:false})({action:'lookup'})).status,403);
});
test('customers and partners cannot register or edit domestic waybills',async()=>{
 for(const role of ['member','partner'])for(const action of ['save','add_event','cargo_search'])assert.equal((await setup({role})({action})).status,403);
 assert.equal((await setup()({action:'list'})).status,403);
});
test('rate limit, malformed bodies and invalid full identifiers stop before database mutation',async()=>{
 assert.equal((await setup({rate:false})({action:'lookup'})).status,429);
 assert.equal((await setup()(null)).status,400);
 assert.equal((await setup()({action:'lookup',tracking_number:'../bad'})).status,400);
 assert.equal((await setup({role:'admin'})({action:'save',carrier:'bad'})).status,400);
});

const shipment=(id,extra={})=>({id,invoice_number:'LKS-TEST-01',box_number:`S-TEST-${id}`,customer_id:'user',route:'sea',shipment_year:2026,voyage:'01',...extra});
const parcel=(id,shipment_id,carrier='ANS')=>({id,shipment_id,carrier,tracking_number:`TEST00000${id}`,checked_at:new Date().toISOString(),events:[],status:'registered'});
test('one statement returns multiple linked waybills without exposing another customer or deleted cargo',async()=>{
 const api=setup({shipments:[shipment(1),shipment(2,{customer_id:'other'}),shipment(3,{deleted_at:'2026-01-01'})],parcels:[parcel(1,1),parcel(2,1,'JT'),parcel(3,2),parcel(4,3)]});
 const r=await api({action:'statement_lookup',statement_number:'lks-test-01'});
 assert.equal(r.status,200);assert.deepEqual(r.body.parcels.map(p=>p.id),[1,2]);
 assert.equal(r.body.cargo_count,1);assert.equal(r.body.parcels[0].cargo.invoice_number,'LKS-TEST-01');
});
test('exact lookup supports route/year/voyage and cargo numbers without substring enumeration',async()=>{
 const api=setup({shipments:[shipment(1),shipment(2,{route:'air'}),shipment(3,{shipment_year:2025}),shipment(4,{voyage:'02'})],parcels:[1,2,3,4].map(n=>parcel(n,n))});
 const r=await api({action:'statement_lookup',statement_number:'LKS-TEST-01',route:'sea',shipment_year:2026,voyage:'1'});
 assert.deepEqual(r.body.parcels.map(p=>p.id),[1]);
 assert.equal((await api({action:'statement_lookup',statement_number:'LKS-TEST'})).body.parcels.length,0);
 assert.equal((await api({action:'statement_lookup',statement_number:'S-TEST-2'})).body.parcels[0].id,2);
 for(const n of ['', '%', 'a,b', 'x(y)'])assert.equal((await api({action:'statement_lookup',statement_number:n})).status,400);
});
test('statement pages retain every linked parcel and distinguish unlinked cargo from absent cargo',async()=>{
 const api=setup({shipments:[shipment(1)],parcels:Array.from({length:23},(_,n)=>parcel(n+1,1))});
 const first=await api({action:'statement_lookup',statement_number:'LKS-TEST-01'});
 const second=await api({action:'statement_lookup',statement_number:'LKS-TEST-01',page:1});
 assert.equal(first.body.parcels.length,20);assert.equal(first.body.has_more,true);
 assert.equal(second.body.parcels.length,3);assert.equal(second.body.has_more,false);
 const unlinked=await setup({shipments:[shipment(1)]})({action:'statement_lookup',statement_number:'LKS-TEST-01'});
 assert.equal(unlinked.body.cargo_count,1);assert.deepEqual(unlinked.body.parcels,[]);
});
