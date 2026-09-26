import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as carriers from './carriers.mjs';
import * as links from './statements.mjs';
import * as photos from './photos.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const ref={route:'한국->라오스 해상',shipment_year:2026,voyage:'08',receipt_number:'LKS 03'};
const cargo=(n,extra={})=>({id:n,...ref,invoice_number:'SUPPLIER-1',box_number:`S-TEST-${n}`,customer_id:'user',consignee_name:'Customer',consignee_phone:'2012345678',...extra});
const parcel=(n,extra={})=>({id:id(n),carrier:'ANS',tracking_number:`TEST0000${n}`,link_scope:'cargo',shipment_id:1,delivery_kind:'province',service_kind:'domestic',events:[],photo_path:'photo.jpg',status:'registered',created_by:'user',updated_at:'2026-09-17T00:00:00Z',created_at:`2026-09-17T00:00:${String(n%60).padStart(2,'0')}Z`,checked_at:new Date(Date.now()+600000).toISOString(),...extra});
const direct=(n,extra={})=>parcel(n,{shipment_id:null,link_scope:'statement',link_route:ref.route,link_year:2026,link_voyage:'08',link_receipt_number:'LKS 03',...extra});
function setup({role='member',active=true,authenticated=true,rate=true,shipments=[],parcels=[],uploadFailure=0,fetchTracking=async()=>({events:[],status:'accepted',origin:'',destination:''})}={}){
 let handler,mutations=0,signed=0;const uploaded=[],removed=[];const data={shipments:structuredClone(shipments),domestic_parcels:structuredClone(parcels)};
 const profile={id:'user',role,approval_status:active?'approved':'pending',deletion_status:null,name:'User',phone:'2099999999'};
 const activeCargo=r=>!r.deleted_at&&!r.deletion_requested_at;
 const same=(a,b)=>links.receiptKey(a)===links.receiptKey(b);
 function query(table,initial){let predicates=[],range=null,limit=null,write=null,insert=null,orders=[];
  function result(){
   let rows=(initial??data[table]).filter(r=>predicates.every(p=>p(r)));
   if(insert){const values=Array.isArray(insert)?insert:[insert];if(values.some(v=>data[table].some(r=>r.carrier===v.carrier&&r.tracking_number===v.tracking_number)))return {data:null,error:{code:'23505'}};rows=values.map(v=>({events:[],status:'registered',sync_state:'never',checked_at:null,created_at:new Date().toISOString(),...v}));data[table].push(...rows);mutations+=rows.length;}
   if(write){for(const r of rows)Object.assign(r,write);mutations+=rows.length;}
   for(const [key,asc]of orders.reverse())rows.sort((a,b)=>(String(a[key]??'').localeCompare(String(b[key]??'')))*(asc?1:-1));
   if(limit!==null)rows=rows.slice(0,limit);if(range)rows=rows.slice(range[0],range[1]+1);
   return {data:structuredClone(rows)};
  }
  return {select(){return this},eq(k,v){predicates.push(r=>r[k]===v);return this},is(k,v){predicates.push(r=>(r[k]??null)===v);return this},in(k,v){predicates.push(r=>v.includes(r[k]));return this},
   contains(k,v){predicates.push(r=>v.every(x=>(r[k]??[]).includes(x)));return this},
   ilike(k,v){const term=v.replace(/\\_/g,'_').replace(/%/g,'').toLowerCase();predicates.push(r=>String(r[k]??'').toLowerCase().includes(term));return this},
   or(){return this},order(k,options={}){orders.push([k,options.ascending!==false]);return this},limit(n){limit=n;return this},range(a,b){range=[a,b];return this},update(v){write=structuredClone(v);return this},insert(v){insert=structuredClone(v);return this},
   async maybeSingle(){const r=result();return {...r,data:r.data?.[0]??null}},async single(){return this.maybeSingle()},then(resolve,reject){return Promise.resolve(result()).then(resolve,reject)}};
 }
 const db={auth:{getUser:async()=>({data:{user:authenticated?{id:'user'}:null},error:!authenticated})},
  storage:{from:()=>({async createSignedUrl(path){signed++;return {data:{signedUrl:'https://signed.test/'+path}}},async upload(path){if(uploadFailure===uploaded.length+1)return {error:{code:'upload'}};uploaded.push(path);return {data:{}}},async remove(paths){removed.push(...paths);return {data:{}}}})},
  from(table){return table==='profiles'?query(table,[profile]):query(table)},
  rpc(name,args){
   if(name==='consume_domestic_tracking_limit')return Promise.resolve({data:rate});
   if(name==='domestic_parcel_group_page'){
    const groups=new Map();for(const r of data.domestic_parcels){const key=links.deliveryGroup(r,data.shipments.find(s=>s.id===r.shipment_id));if(!groups.has(key))groups.set(key,[]);groups.get(key).push(r);}
    return Promise.resolve({data:[...groups].sort(([a],[b])=>a.localeCompare(b)).slice(args.p_page*args.p_size,args.p_page*args.p_size+args.p_size+1).map(([group_key,parcels])=>({group_key,parcels:structuredClone(parcels)}))});
   }
   if(name==='domestic_find_delivery_cargo'){
    const rows=data.shipments.filter(r=>activeCargo(r)&&(!args.p_route||r.route===args.p_route)&&(!args.p_year||r.shipment_year===args.p_year)&&(!args.p_voyage||same(r.voyage,args.p_voyage))&&
     (same(r.receipt_number,args.p_number)||(args.p_receipt_only&&/^\d+$/.test(links.receiptKey(args.p_number))&&links.receiptKey(r.receipt_number).replace(/^[A-Z]+/,'')===links.receiptKey(args.p_number))||(!args.p_receipt_only&&[r.box_number,r.invoice_number].some(v=>String(v??'').toUpperCase()===args.p_number.toUpperCase()))));
    return Promise.resolve({data:structuredClone(rows.slice(0,501))});
   }
   if(name==='domestic_parcels_for_statement'){
    const matches=r=>r.route===args.p_route&&r.shipment_year===args.p_year&&same(r.voyage,args.p_voyage)&&same(r.receipt_number,args.p_receipt);
    return query('domestic_parcels',data.domestic_parcels.filter(r=>{const ref=links.rowStatement(r);return ref&&matches(ref)||data.shipments.some(s=>s.id===r.shipment_id&&activeCargo(s)&&matches(s));}));
   }
   assert.fail(name);
  }};
 vm.runInNewContext(source,{...carriers,...links,...photos,fetchTracking,createClient:()=>db,Deno:{env:{get:()=>''},serve:fn=>{handler=fn}},Request,Response,Date,crypto,Uint8Array,atob,console});
 return {data,uploaded,removed,get mutations(){return mutations},get signed(){return signed},async call(body,token='token'){
  const response=await handler(new Request('https://local.test',{method:'POST',headers:token?{Authorization:`Bearer ${token}`}:{},body:JSON.stringify(body)}));
  return {status:response.status,body:await response.json()};
 }};
}
const saveBody={action:'save',link_scope:'statement',statement:ref,carrier:'ANS',tracking_number:'1234567890123',delivery_kind:'province',service_kind:'domestic'};
test('anonymous, inactive, customer writes and malformed requests stop before mutation',async()=>{
 assert.equal((await setup().call({action:'lookup'},'')).status,401);
 assert.equal((await setup({authenticated:false}).call({action:'lookup'})).status,401);
 assert.equal((await setup({active:false}).call({action:'list'})).status,403);
 for(const action of ['save','add_event','cargo_search','statement_resolve','list'])assert.equal((await setup().call({action})).status,403);
 assert.equal((await setup({rate:false}).call({action:'lookup'})).status,429);
 assert.equal((await setup().call(null)).status,400);
 for(const number of ['','%','a,b','x(y)'])assert.equal((await setup().call({action:'statement_lookup',statement_number:number})).status,400);
});
test('LK receipt identity is distinct from supplier invoice and ignores spaces/leading zeros within exact voyage',async()=>{
 const api=setup({role:'admin',shipments:[cargo(1),cargo(2),cargo(3,{voyage:'09'}),cargo(4,{shipment_year:2025})]});
 const result=await api.call({action:'statement_resolve',...ref,voyage:'8',receipt_number:'lks03'});
 assert.equal(result.status,200);assert.equal(result.body.cargo_count,2);assert.deepEqual(result.body.statement,ref);
 assert.equal((await api.call({action:'statement_resolve',...ref,receipt_number:'SUPPLIER-1'})).body.statement,null);
 assert.equal((await api.call({action:'statement_resolve',...ref,receipt_number:'3'})).body.statement.receipt_number,'LKS 03');
 assert.equal((await api.call({action:'statement_lookup',statement_number:'LKS 03'})).body.error,'NARROW_SEARCH');
});
test('one statement includes all direct and legacy cargo waybills, pages without duplicate rows, and excludes other voyages',async()=>{
 const records=[parcel(1),direct(2),direct(3,{link_voyage:'09'}),...Array.from({length:21},(_,n)=>parcel(n+4))];
 const api=setup({shipments:[cargo(1),cargo(2,{voyage:'09'})],parcels:records});
 const first=await api.call({action:'statement_lookup',statement_number:'LKS 03',route:ref.route,shipment_year:2026,voyage:'8'});
 const second=await api.call({action:'statement_lookup',statement_number:'LKS03',...ref,page:1});
 assert.equal(first.status,200);assert.equal(first.body.parcels.length,20);assert.equal(first.body.has_more,true);
 assert.equal(second.body.parcels.length,3);assert.equal(second.body.has_more,false);
 const ids=[...first.body.parcels,...second.body.parcels].map(r=>r.id);assert.equal(new Set(ids).size,23);assert.equal(ids.includes(id(3)),false);
 assert.ok(first.body.parcels.every(r=>r.photo_url));
});
test('customers cannot expose another recipient photo or mixed-owner statement link',async()=>{
 const api=setup({shipments:[cargo(1),cargo(2,{customer_id:'other'})],parcels:[parcel(1),direct(2),parcel(3,{shipment_id:2})]});
 const r=await api.call({action:'statement_lookup',...ref,statement_number:'LKS 03'});
 assert.deepEqual(r.body.parcels.map(r=>r.id),[id(1)]);assert.equal(api.signed,1);
 const hidden=await setup({shipments:[cargo(1,{customer_id:'other'})],parcels:[direct(1)]}).call({action:'statement_lookup',statement_number:'LKS03'});
 assert.deepEqual(hidden.body.parcels,[]);
});
test('one uploaded image containing different recipients is restricted even for one linked customer',async()=>{
 const path='intake/owner/batch/multiple-labels.png';
 const api=setup({shipments:[cargo(1),cargo(2,{customer_id:'other',consignee_name:'Other',consignee_phone:'2098765432'})],parcels:[parcel(1,{photo_path:path,photo_paths:[path]}),parcel(2,{shipment_id:2,photo_path:path,photo_paths:[path]})]});
 const r=await api.call({action:'lookup',carrier:'ANS',tracking_number:'TEST00001'});
 assert.equal(r.status,200);assert.deepEqual(r.body.parcels[0].photo_urls,[]);assert.equal(r.body.parcels[0].photo_restricted,true);assert.equal(api.signed,0);
});
test('statement save writes both compatible representations and partner ownership is enforced',async()=>{
 for(const role of ['admin','staff','partner']){
  const api=setup({role,shipments:[cargo(1),cargo(2)]});const r=await api.call(saveBody);
  assert.equal(r.status,200);const saved=api.data.domestic_parcels[0];
  assert.equal(saved.link_scope,'statement');assert.equal(saved.shipment_id,null);assert.equal(saved.link_receipt_number,'LKS 03');assert.equal(saved.statement_receipt,'LKS 03');assert.equal(saved.created_by,'user');assert.equal(saved.receiver_name,'Customer');
 }
 const row=parcel(1,{created_by:'someone-else'}),api=setup({role:'partner',shipments:[cargo(1)],parcels:[row]});
 assert.equal((await api.call({...saveBody,id:row.id,updated_at:row.updated_at})).status,403);
 assert.equal((await api.call({action:'add_event',id:row.id,updated_at:row.updated_at,status:'accepted',occurred_at:'2026-01-01T00:00:00+07:00',description:'Accepted'})).status,403);
 assert.equal(api.mutations,0);assert.equal((await api.call({action:'list'})).body.parcels[0].can_manage,false);
});
test('separate reference maps multiple waybills by namespace and cannot reveal another customer',async()=>{
 const api=setup({role:'partner'});
 for(const [number,type]of [['REF00001','ecommerce'],['REF00002','ecommerce'],['REF00003','local']]){
  const r=await api.call({...saveBody,link_scope:'reference',statement:null,reference:{reference_type:type,reference_number:'ec-001'},tracking_number:number,receiver_name:'Recipient',receiver_phone:'2012345678'});assert.equal(r.status,200);
 }
 const result=await api.call({action:'reference_lookup',reference_type:'ecommerce',reference_number:'EC-001'});assert.equal(result.body.parcels.length,2);assert.ok(result.body.parcels.every(r=>r.service_kind==='ecommerce'));
 const customer=setup({parcels:api.data.domestic_parcels});assert.deepEqual((await customer.call({action:'reference_lookup',reference_type:'ecommerce',reference_number:'EC-001'})).body.parcels,[]);assert.equal(customer.signed,0);
});
test('old installed clients preserve a reference link and CAS rejects conflicting edits',async()=>{
 const row=direct(1),api=setup({role:'admin',shipments:[cargo(1)],parcels:[row]});
 const b={action:'save',id:row.id,updated_at:row.updated_at,carrier:row.carrier,tracking_number:row.tracking_number,shipment_id:null,delivery_kind:'city',service_kind:'domestic'};
 assert.equal((await api.call(b)).status,200);assert.equal(api.data.domestic_parcels[0].link_scope,'statement');
 assert.equal((await api.call(b)).status,409);
});
test('carrier corrections retain manual history/photo and discard obsolete carrier events',async()=>{
 const row=parcel(1,{events:[{key:'carrier',source:'carrier',status:'delivered'},{key:'staff',source:'staff',status:'accepted',occurred_at:'2026-01-01T00:00:00Z'}]});
 const api=setup({role:'partner',shipments:[cargo(1)],parcels:[row]});
 const r=await api.call({...saveBody,link_scope:'cargo',shipment_id:1,id:row.id,updated_at:row.updated_at,carrier:'JT',tracking_number:'JTLA123456789012'});
 assert.equal(r.status,200);const saved=api.data.domestic_parcels[0];assert.equal(saved.photo_path,'photo.jpg');assert.deepEqual(saved.events.map(r=>r.key),['staff']);assert.ok(saved.checked_at);assert.equal(saved.status,'accepted');
});
test('missing and ambiguous statements never create a mapping',async()=>{
 const api=setup({role:'admin',shipments:[cargo(1),cargo(2,{receipt_number:'OTHER 03'})]});
 assert.equal((await api.call({...saveBody,statement:{...ref,receipt_number:'3'}})).body.error,'AMBIGUOUS_STATEMENT');
 assert.equal((await api.call({...saveBody,statement:{...ref,receipt_number:'LKS 99'}})).status,404);
 assert.equal((await api.call({...saveBody,link_scope:'reference',reference:{reference_type:'ecommerce',reference_number:'%'}})).status,400);assert.equal(api.mutations,0);
 assert.equal((await api.call({...saveBody,statement:null})).status,400);
});
test('in-flight carrier success and failure cannot overwrite a corrected carrier',async()=>{
 for(const fail of [false,true]){
  let release;
  const row=parcel(1,{checked_at:null}),api=setup({role:'admin',shipments:[cargo(1)],parcels:[row],fetchTracking:()=>new Promise((resolve,reject)=>{release=()=>fail?reject(Error('AUTH_REQUIRED')):resolve({events:[],status:'delivered',origin:'OLD',destination:'OLD'});})});
  const request=api.call({action:'lookup',carrier:'ANS',tracking_number:row.tracking_number});
  while(!release)await new Promise(setImmediate);
  Object.assign(api.data.domestic_parcels[0],{carrier:'JT',tracking_number:'JTLA123456789012',status:'registered',sync_state:'never'});release();await request;
  assert.equal(api.data.domestic_parcels[0].carrier,'JT');assert.equal(api.data.domestic_parcels[0].status,'registered');assert.equal(api.data.domestic_parcels[0].sync_state,'never');
 }
});
const png={base64:Buffer.from([137,80,78,71,13,10,26,10,...Array(20).fill(0)]).toString('base64')};
const batchBody={...saveBody,action:'save_batch',waybills:[{carrier:'HAL',tracking_number:'VTE71626785947'},{carrier:'ANS',tracking_number:'1234567890123'}]};
test('batch saves two numbers and two shared private photos atomically; initial history fetch is automatic',async()=>{
 let calls=0;const api=setup({role:'admin',shipments:[cargo(1)],fetchTracking:async()=>{calls++;return {status:'delivered',events:[],origin:'',destination:''}}});
 const r=await api.call({...batchBody,photos:[png,png]});
 assert.equal(r.status,200);assert.equal(r.body.saved_count,2);assert.equal(calls,2);assert.equal(api.uploaded.length,2);assert.equal(api.signed,2);
 assert.ok(r.body.parcels.every(p=>p.photo_urls.length===2&&p.status==='delivered'&&p.checked_at));
 assert.equal(new Set(r.body.parcels.map(p=>p.group_key)).size,1);
 const listed=await api.call({action:'list_groups'});assert.equal(listed.body.parcels.length,2);assert.equal(calls,2,'fresh history is cached');
});
test('invalid batches and photo limits have no partial registration; failed writes clean new images only',async()=>{
 const api=setup({role:'admin',shipments:[cargo(1)],parcels:[parcel(1,{carrier:'ANS',tracking_number:'1234567890123'})]});
 assert.equal((await api.call({...batchBody,waybills:Array(51).fill(batchBody.waybills[0])})).status,400);
 assert.equal((await api.call({...batchBody,waybills:[batchBody.waybills[0],batchBody.waybills[0]]})).status,409);
 assert.equal((await api.call({...batchBody,photos:Array(51).fill(png)})).body.error,'TOO_MANY_PHOTOS');
 assert.equal(api.mutations,0);
 const duplicate=await api.call({...batchBody,photos:[png,png]});assert.equal(duplicate.status,409);assert.equal(api.data.domestic_parcels.length,1);assert.deepEqual(api.removed,api.uploaded);
 const failed=setup({role:'admin',shipments:[cargo(1)],uploadFailure:2});
 assert.equal((await failed.call({...batchBody,photos:[png,png]})).status,500);assert.deepEqual(failed.removed,failed.uploaded);assert.equal(failed.data.domestic_parcels.length,0);
});
test('editing appends multiple photos and keeps legacy image, conflicts leave existing images intact',async()=>{
 const row=direct(1),api=setup({role:'admin',shipments:[cargo(1)],parcels:[row]});
 const r=await api.call({...saveBody,id:row.id,updated_at:row.updated_at,photos:[png,png]});
 assert.equal(r.status,200);assert.equal(r.body.parcel.photo_count,3);assert.equal(api.data.domestic_parcels[0].photo_path,'photo.jpg');
 assert.equal((await api.call({...saveBody,id:row.id,updated_at:row.updated_at,photos:[png]})).status,409);assert.equal(api.uploaded.length,2);assert.equal(api.removed.length,0);
});
test('group pages never split a statement and grouping distinguishes route/year/voyage',async()=>{
 const rows=Array.from({length:11},(_,n)=>direct(n+1,{link_receipt_number:`LKS ${n}`}));rows.push(direct(50,{link_receipt_number:'LKS 00'}));
 const api=setup({role:'admin',parcels:rows}),a=await api.call({action:'list_groups'}),b=await api.call({action:'list_groups',page:1});
 assert.equal(a.status,200);assert.equal(a.body.has_more,true);assert.equal(b.body.has_more,false);
 assert.equal(new Set(a.body.parcels.map(p=>p.group_key)).size,10);assert.equal(b.body.parcels.length,1);assert.equal(a.body.parcels.length,11);
 assert.notEqual(links.deliveryGroup(direct(1)),links.deliveryGroup(direct(1,{link_voyage:'09'})));
});
test('nonowner tracking search includes LK statement with masked recipient and no photos, free text or sibling numbers',async()=>{
 const rows=[direct(1,{receiver_name:'원순연',receiver_phone:'020 5555 5555',events:[{key:'raw-02055555555',occurred_at:'2026-01-01T00:00:00Z',status:'delivered',source:'staff',location:'private address',description:'private name'}]}),direct(2)];
 const hidden=setup({shipments:[cargo(1,{customer_id:'other'})],parcels:rows});
 const r=await hidden.call({action:'lookup',tracking_number:rows[0].tracking_number,grouped:true});assert.equal(r.status,200);assert.equal(r.body.parcels.length,1);
 const p=r.body.parcels[0];assert.equal(p.statement.receipt_number,'LKS 03');assert.equal(p.receiver_name,'원*연');assert.equal(p.receiver_phone,'020 5555 ****');assert.equal(p.recipient_masked,true);assert.deepEqual(p.photo_urls,[]);assert.equal(p.official_url,null);assert.equal(hidden.signed,0);
 assert.ok(!JSON.stringify(p).includes('private'));assert.ok(!JSON.stringify(p).includes('02055555555'));
 const owner=setup({shipments:[cargo(1)],parcels:rows});const own=await owner.call({action:'lookup',tracking_number:rows[0].tracking_number,grouped:true});assert.equal(own.body.parcels.length,2);assert.equal(own.body.parcels[0].receiver_name,'원순연');
});
test('photo decoding rejects bad formats, enforces per-image and total bytes, accepts legacy upload',()=>{
 assert.equal(photos.decodePhotos({photo:png}).length,1);
 assert.throws(()=>photos.decodePhotos({photos:[{base64:'bad!'}]}),/INVALID_IMAGE/);
 const large=Buffer.alloc(5*1024*1024);large.set([137,80,78,71]);const max={base64:large.toString('base64')};
 assert.throws(()=>photos.decodePhotos({photos:[max,max,max,png]}),/FILE_TOO_LARGE/);
 assert.throws(()=>photos.decodePhotos({photos:[{base64:max.base64+'AAAA'}]}),/FILE_TOO_LARGE/);
});
