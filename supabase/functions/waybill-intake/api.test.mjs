import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as validation from './validation.mjs';
import * as registry from './registry.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
const png=new Uint8Array([137,80,78,71,13,10,26,10,0,0,0,0,0]);
function setup({role='admin',active=true,authenticated=true,data:initial={},ocr={waybills:[]},ocrFailure=false}={}){
 const data={profiles:[{id:'owner',role,approval_status:active?'approved':'pending'}],waybill_intake_batches:[],waybill_intake_files:[],unknown_cargo_photos:[],customer_registry:[],customer_registry_sources:[],customer_registry_source_status:[],shipments:[],customer_registry_statement_mapping:[],...structuredClone(initial)};
 let handler,ocrCalls=0,ocrBody=null;const writes=[],rpcCalls=[],signed=[];
 function query(table){let filters=[],write=null,insert=null,count=false,window=null;
  function run(){let rows=data[table].filter(r=>filters.every(f=>f(r)));
   if(insert){rows=(Array.isArray(insert)?insert:[insert]).map(r=>({created_at:new Date().toISOString(),status:'draft',scan_attempts:0,...r}));data[table].push(...rows);writes.push(table);}
   if(write){for(const r of rows)Object.assign(r,write);writes.push(table);}
   const n=rows.length;if(window)rows=rows.slice(window[0],window[1]+1);return {data:structuredClone(rows),...(count?{count:n}: {})};
  }
  return {select(_,opts){count=opts?.count==='exact';return this},eq(k,v){filters.push(r=>r[k]===v);return this},is(k,v){filters.push(r=>(r[k]??null)===v);return this},in(k,v){filters.push(r=>v.includes(r[k]));return this},gte(k,v){filters.push(r=>r[k]>=v);return this},order(){return this},range(a,b){window=[a,b];return this},insert(v){insert=v;return this},update(v){write=v;return this},async single(){const r=run();return {...r,data:r.data[0]??null}},async maybeSingle(){return this.single()},then(resolve,reject){return Promise.resolve(run()).then(resolve,reject)}};
 }
 const db={auth:{getUser:async()=>({data:{user:authenticated?{id:'owner'}:null},error:!authenticated})},from:query,
  storage:{from:()=>({async createSignedUrl(path){signed.push(path);return {data:{signedUrl:'https://private.test/'+path}}},async createSignedUploadUrl(path){return {data:{signedUrl:'https://upload.test/'+path,token:'upload-token'}}},async download(){return {data:new Blob([png])}}})},
  async rpc(name,args){rpcCalls.push({name,args});
   if(name==='search_shipments_for_current_user')return {data:data.shipments.filter(s=>s.visible!==false)};
   if(name==='list_unknown_recipient_cargo')return {data:data.shipments.filter(s=>s.recipient_unknown)};
   if(name==='domestic_find_delivery_cargo')return {data:data.shipments.filter(s=>s.receipt_number===args.p_number)};
   if(name==='commit_waybill_intake'){const b=data.waybill_intake_batches.find(b=>b.id===args.p_batch);b.status='committed';b.result_ids=['saved'];return {data:b.result_ids};}
   if(name==='commit_reference_photos'){const b=data.waybill_intake_batches.find(b=>b.id===args.p_batch);b.status='committed';b.result_ids=['reference'];return {data:b.result_ids};}
   if(name==='commit_unknown_cargo_photos')return {data:true};
   if(name==='waybill_recipient_candidates'){
    const nk=String(args.p_name).replace(/\s/g,'').toLowerCase(),pk=String(args.p_phone).replace(/\D/g,'').replace(/^856/,'0');
    return {data:data.shipments.filter(s=>s.consignee_name.replace(/\s/g,'').toLowerCase()===nk||s.consignee_phone===pk).map(s=>({exact:s.consignee_phone===pk&&s.consignee_name.replace(/\s/g,'').toLowerCase()===nk,statement:{receipt_number:s.receipt_number}})).sort((a,b)=>Number(b.exact)-Number(a.exact))};
   }
   if(name==='customer_registry_change'||name==='customer_registry_merge')return {data:{id:args.p_id??args.p_target}};
   if(name==='customer_registry_member_id')return {data:{customer_code:'023',status:'linked'}};
   if(name==='customer_registry_bulk_apply')return {data:{updated_count:2,merged_count:0,moved_sources:0}};
   if(name==='customer_registry_resolve_source')return {data:true};
   assert.fail(name);
  }};
 vm.runInNewContext(source,{...validation,...registry,createClient:()=>db,Deno:{env:{get:()=> 'configured'},serve:fn=>handler=fn},Request,Response,Date,crypto,Uint8Array,TextDecoder,AbortSignal,console,
  fetch:async(_url,options)=>{ocrCalls++;ocrBody=JSON.parse(options.body);return new Response(JSON.stringify({output:[{content:[{type:'output_text',text:JSON.stringify(ocr)}]}]}),{status:ocrFailure?503:200});}});
 return {data,writes,rpcCalls,signed,get ocrCalls(){return ocrCalls},get ocrBody(){return ocrBody},async call(body,token='valid'){
  const r=await handler(new Request('https://test.invalid',{method:'POST',headers:token?{Authorization:`Bearer ${token}`}:{},body:JSON.stringify(body)}));return {status:r.status,body:await r.json()};
 }};
}
const file={id:'file',batch_id:'batch',path:'intake/owner/batch/test.png',size_bytes:13,verified_at:'2026-09-01T00:00:00Z',scan_attempts:0};
const batch={id:'batch',owner_id:'owner',purpose:'waybill',status:'draft',created_at:new Date().toISOString()};
const entry={carrier:'HAL',tracking_number:'VTE12345678901',receiver_name:'Customer',receiver_phone:'02012345678',link_scope:'standalone',delivery_kind:'province',service_kind:'domestic',file_ids:['file'],confirmed:true};
const ready={waybill_intake_batches:[batch],waybill_intake_files:[file]};
test('authentication, active status and role boundaries precede writes and photo signing',async()=>{
 for(const [api,token,status]of [[setup(),'',401],[setup({authenticated:false}),'valid',401],[setup({active:false}),'valid',403],[setup({role:'member'}),'valid',403]]){
  assert.equal((await api.call({action:'begin',purpose:'waybill',files:[{name:'a.png',size:13}]},token)).status,status);assert.equal(api.writes.length,0);assert.equal(api.signed.length,0);
 }
 assert.equal((await setup().call(null)).status,400);
 assert.equal((await setup({role:'staff'}).call({action:'customers_list'})).status,403);
 assert.equal((await setup({role:'partner'}).call({action:'begin',purpose:'unknown',shipment_id:1})).status,403);
});
test('50 files of 5MB are staged individually, while 51 files and oversize images never begin a batch',async()=>{
 const api=setup(),files=Array.from({length:50},(_,i)=>({name:`${i}.png`,size:5242880}));
 const r=await api.call({action:'begin',purpose:'waybill',files});assert.equal(r.status,200);assert.equal(r.body.files.length,50);assert.equal(new Set(r.body.files.map(f=>f.path)).size,50);assert.equal(api.ocrCalls,0);
 for(const files of [Array(51).fill({name:'a.png',size:13}),[{name:'a.png',size:5242881}],[{name:'a.exe',size:13}]]){const invalid=setup();assert.equal((await invalid.call({action:'begin',purpose:'waybill',files})).status,400);assert.equal(invalid.writes.length,0);}
});
test('OCR drafts preserve uncertainty, cache results, and never register parcels',async()=>{
 const api=setup({data:ready,ocr:{waybills:[{tracking_number:' VTE 12345678901 ',carrier:'HAL',receiver_name:'A',receiver_phone:'02012345678',note:''},{tracking_number:'',carrier:'unknown',receiver_name:'B',receiver_phone:'',note:'unclear'}]}});
 for(let i=0;i<2;i++){const r=await api.call({action:'scan',batch_id:'batch',file_id:'file'});assert.equal(r.status,200);assert.equal(r.body.waybills.length,2);assert.equal(r.body.waybills[1].carrier,'');assert.equal(r.body.waybills[1].tracking_number,'');}
 assert.equal(api.ocrCalls,1);assert.equal(api.rpcCalls.length,0);assert.equal(api.data.waybill_intake_batches[0].status,'draft');
});
test('OCR failure leaves a verified photo for manual review, and clears retry lock',async()=>{
 const api=setup({data:ready,ocrFailure:true}),r=await api.call({action:'scan',batch_id:'batch',file_id:'file'});
 assert.equal(r.status,502);assert.equal(api.data.waybill_intake_files[0].scan_started_at,null);assert.equal(api.data.waybill_intake_files[0].scan_attempts,1);
 assert.equal((await api.call({action:'preview',batch_id:'batch'})).body.photos.length,1);assert.equal(api.rpcCalls.length,0);
});
test('every entry needs review and an owned verified image; duplicates never commit',async()=>{
 for(const entries of [[{...entry,confirmed:false}],[{...entry,file_ids:['other']}],[entry,entry],[{...entry,tracking_number:''}]]){
  const api=setup({data:ready});assert.equal((await api.call({action:'commit',batch_id:'batch',entries})).status,400);assert.equal(api.rpcCalls.length,0);
 }
 const api=setup({data:{...ready,waybill_intake_batches:[{...batch,owner_id:'other'}]}});assert.equal((await api.call({action:'commit',batch_id:'batch',entries:[entry]})).status,403);
});
test('reviewed commit uses one atomic RPC and retry returns the same records',async()=>{
 const api=setup({data:ready}),body={action:'commit',batch_id:'batch',entries:[entry]};
 const a=await api.call(body),b=await api.call(body);assert.equal(a.status,200);assert.deepEqual(a.body,b.body);assert.equal(api.rpcCalls.length,1);assert.equal(api.rpcCalls[0].args.p_values[0].photo_paths[0],file.path);
});
test('customer suggestions use full phone plus name and do not silently merge namesakes',async()=>{
 const api=setup({data:{shipments:[{id:1,consignee_name:'김고객',consignee_phone:'02012345678',receipt_number:'LKS01'},{id:2,consignee_name:'김고객',consignee_phone:'02087654321',receipt_number:'LKS02'}]}});
 const r=await api.call({action:'candidates',receiver_name:'김 고객',receiver_phone:'+8562012345678'});assert.equal(r.body.candidates.length,2);assert.equal(r.body.candidates.filter(c=>c.exact).length,1);assert.equal(r.body.candidates[0].statement.receipt_number,'LKS01');assert.equal(api.writes.length,0);
});
test('unknown cargo signs only currently visible cargo photos and rejects repeated image IDs',async()=>{
 const data={shipments:[{id:1,recipient_unknown:true}],unknown_cargo_photos:[{id:'p1',shipment_id:1,path:'visible',kind:'box'},{id:'p2',shipment_id:2,path:'hidden',kind:'box'}]};
 const api=setup({role:'member',data}),r=await api.call({action:'unknown_list'});assert.equal(r.body.cargo[0].photos.length,1);assert.deepEqual(api.signed,['visible']);
 const operator=setup({role:'staff',data:{...ready,waybill_intake_batches:[{...batch,purpose:'unknown'}],waybill_intake_files:[file,{...file,id:'file2'}]}});
 const bad=await operator.call({action:'unknown_save',batch_id:'batch',confirmed:true,photos:[{file_id:'file',kind:'box'},{file_id:'file',kind:'box'}]});assert.equal(bad.status,400);assert.equal(operator.rpcCalls.length,0);
});
test('fixed statement is resolved once at intake; number-only OCR and commit preserve authoritative recipient',async()=>{
 const cargo={id:5,route:'KR-LA',shipment_year:2026,voyage:'09',receipt_number:'LKS05',consignee_name:'Statement customer',consignee_phone:'02012345678'};
 const link={link_scope:'statement',statement:{route:cargo.route,shipment_year:2026,voyage:'09',receipt_number:'LKS05'},receiver_name:'Client typo',carrier:'BAD'};
 const api=setup({data:{shipments:[cargo]},ocr:{waybills:[{tracking_number:'VTE12345678901',carrier:'HAL',receiver_name:'OCR wrong',receiver_phone:'000',note:''}]}});
 const started=await api.call({action:'begin',purpose:'waybill',fixed_link:link,files:[{name:'a.png',size:13}]});assert.equal(started.status,200);
 assert.equal(started.body.fixed_link.receiver_name,'Statement customer');assert.equal(started.body.fixed_link.carrier,undefined);
 const f=started.body.files[0],b=started.body.batch_id;
 const scanned=await api.call({action:'scan',batch_id:b,file_id:f.id});assert.equal(scanned.status,200);assert.equal(scanned.body.waybills[0].receiver_name,'Statement customer');
 assert.equal(api.ocrBody.text.format.schema.properties.waybills.items.properties.receiver_name,undefined);
 const r=await api.call({action:'commit',batch_id:b,entries:[{...entry,file_ids:[f.id],receiver_name:'Tampered'},{...entry,file_ids:[f.id],tracking_number:'VTE12345678902'}]});assert.equal(r.status,200);
 const commit=api.rpcCalls.find(r=>r.name==='commit_waybill_intake');assert.equal(commit.args.p_values[0].receiver_name,'Statement customer');
 assert.equal(api.rpcCalls.filter(r=>r.name==='domestic_find_delivery_cargo').length,2);
});
test('customer summary identifies spelling candidates and true mismatches separately; admin operations stay protected',async()=>{
 const data={customer_registry:[{id:'a',customer_no:3,name:'Alpha',phone:'02012345678',name_key:'alpha',phone_key:'02012345678'},{id:'b',customer_no:4,name:'Alphb',phone:'02012345679',name_key:'alphb',phone_key:'02012345679'}],customer_registry_source_status:[{source_kind:'shipment',source_id:'7',customer_registry_id:'a',mismatch:true}]};
 const api=setup({data}),r=await api.call({action:'customers_list',mismatches_only:true});assert.equal(r.body.customers.length,1);assert.equal(r.body.summary.mismatch_customers,1);assert.equal(r.body.summary.duplicate_customers,2);
 const detail=await api.call({action:'customers_detail',id:'a'});assert.equal(detail.body.candidates[0].id,'b');assert.equal(detail.body.sources.length,1);
 const edit=await api.call({action:'customers_update',id:'a',customer_no:3,name:'Alpha',phone:'02012345678',updated_at:'stamp'});assert.equal(edit.status,200);assert.equal(api.rpcCalls.at(-1).args.p_reason,'');
 for(const action of ['customers_summary','customers_detail','customers_update','customers_merge','customers_resolve_source'])assert.equal((await setup({role:'staff'}).call({action})).status,403);
 assert.equal((await api.call({action:'customers_merge',source_id:'a',target_id:'b',confirmed:false})).status,400);
 assert.equal((await api.call({action:'customers_merge',source_id:'a',target_id:'b',source_updated_at:'x',target_updated_at:'y',confirmed:true})).status,200);
 assert.equal(api.rpcCalls.at(-1).args.p_source_expected,'x');
});
test('reference photo commit needs no tracking details or OCR and retries without duplicate records',async()=>{
 const fixed={link_scope:'cargo',shipment_id:1,receiver_name:'A',receiver_phone:'02012345678'};
 const api=setup({data:{...ready,waybill_intake_batches:[{...batch,purpose:'photos',fixed_link:fixed}],shipments:[{id:1,consignee_name:'A',consignee_phone:'02012345678'}]}});
 const body={action:'reference_commit',batch_id:'batch',delivery_kind:'province',service_kind:'domestic'};
 const first=await api.call(body),second=await api.call(body);assert.equal(first.status,200);assert.deepEqual(first.body.ids,second.body.ids);
 assert.equal(api.ocrCalls,0);const calls=api.rpcCalls.filter(r=>r.name==='commit_reference_photos');assert.equal(calls.length,1);assert.equal(calls[0].args.p_value.tracking_number,undefined);assert.equal(calls[0].args.p_value.photo_paths.length,1);
 for(const data of [{...ready,waybill_intake_batches:[{...batch,purpose:'photos'}]},{...ready,waybill_intake_batches:[{...batch,purpose:'photos',fixed_link:fixed}],waybill_intake_files:[{...file,verified_at:null}],shipments:[{id:1,consignee_name:'A'}]}])assert.equal((await setup({data}).call(body)).status,400);
});

test('bulk customer endpoint requires active admin and review and performs one atomic RPC',async()=>{
 const rows=['a','b'].map((id,i)=>({id,target_id:id,customer_no:i+3,name:'Customer '+id,phone:'02011110000',updated_at:'2026-09-26T00:00:00Z'}));
 for(const api of [setup({role:'staff'}),setup({active:false}),setup({role:'partner'})]){assert.equal((await api.call({action:'customers_bulk',rows,confirmed:true})).status,403);assert.equal(api.rpcCalls.length,0);}
 const api=setup();assert.equal((await api.call({action:'customers_bulk',rows})).status,400);assert.equal(api.rpcCalls.length,0);
 assert.equal((await api.call({action:'customers_bulk',rows:[rows[0],rows[0]],confirmed:true})).status,400);assert.equal(api.rpcCalls.length,0);
 const result=await api.call({action:'customers_bulk',rows,confirmed:true});assert.equal(result.status,200);assert.equal(result.body.updated_count,2);assert.equal(api.rpcCalls.length,1);assert.equal(api.rpcCalls[0].name,'customer_registry_bulk_apply');assert.equal(api.rpcCalls[0].args.p_reason,'');assert.equal(api.rpcCalls[0].args.p_rows.length,2);
});

test('member identity is owner-only; it does not expose registry or operational actions',async()=>{
 const api=setup({role:'member'});const r=await api.call({action:'my_customer_id',owner:'other',p_owner:'other',id:'other'});
 assert.equal(r.status,200);assert.equal(r.body.customer_code,'023');assert.deepEqual(api.rpcCalls.map(x=>x.name),['customer_registry_member_id']);assert.equal(api.rpcCalls[0].args.p_owner,'owner');
 assert.equal((await api.call({action:'customers_list'})).status,403);
 for(const blocked of [setup({authenticated:false}),setup({active:false})]){const r=await blocked.call({action:'my_customer_id'});assert.ok([401,403].includes(r.status));assert.equal(blocked.rpcCalls.length,0);}
});

test('customer ID search normalizes leading zeros and only filters existing authorized cargo',async()=>{
 const api=setup({role:'member',data:{shipments:[{id:1},{id:2,visible:false},{id:3}],customer_registry_statement_mapping:[{shipment_id:1,customer_code:'023'},{shipment_id:2,customer_code:'023'},{shipment_id:3,customer_code:'123'}]}});
 for(const code of ['23','023','ID 023']){const r=await api.call({action:'customer_id_search',customer_code:code});assert.equal(r.status,200);assert.deepEqual(r.body.shipments,[{id:1,customer_code:'023'}]);}
 assert.equal((await api.call({action:'customer_id_search',customer_code:'9023'})).body.shipments.length,0);
 assert.equal((await api.call({action:'customer_id_search',customer_code:'0'})).status,400);
 assert.equal(api.rpcCalls.some(c=>c.name==='search_shipments_by_invoice_suffix'),false);assert.equal(api.writes.length,0);
});
test('bulk identity lookup is read-only and role-scoped',async()=>{
 const data={shipments:[{id:1}],customer_registry_statement_mapping:[{shipment_id:1,customer_code:'023'},{shipment_id:2,customer_code:'044'}]};
 for(const role of ['member','staff','partner'])assert.equal((await setup({role,data}).call({action:'customer_identity_index',profile_ids:['owner']})).status,403);
 assert.equal((await setup({role:'member',data}).call({action:'customer_identity_index',shipment_ids:[1]})).status,403);
 const api=setup({data});const r=await api.call({action:'customer_identity_index',profile_ids:['owner','missing'],shipment_ids:[1,2]});
 assert.equal(r.status,200);assert.equal(r.body.profiles.length,1);assert.equal(r.body.profiles[0].customer_code,'023');assert.equal(r.body.shipments.length,1);assert.equal(api.writes.length,0);
 assert.equal((await api.call({action:'customer_identity_index',shipment_ids:Array(501).fill(1)})).status,400);
});
