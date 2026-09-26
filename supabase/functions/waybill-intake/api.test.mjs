import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as validation from './validation.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
const png=new Uint8Array([137,80,78,71,13,10,26,10,0,0,0,0,0]);
function setup({role='admin',active=true,authenticated=true,data:initial={},ocr={waybills:[]},ocrFailure=false}={}){
 const data={profiles:[{id:'owner',role,approval_status:active?'approved':'pending'}],waybill_intake_batches:[],waybill_intake_files:[],unknown_cargo_photos:[],customer_registry:[],customer_registry_sources:[],shipments:[],...structuredClone(initial)};
 let handler,ocrCalls=0;const writes=[],rpcCalls=[],signed=[];
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
   if(name==='list_unknown_recipient_cargo')return {data:data.shipments.filter(s=>s.recipient_unknown)};
   if(name==='domestic_find_delivery_cargo')return {data:data.shipments.filter(s=>s.receipt_number===args.p_number)};
   if(name==='commit_waybill_intake'){const b=data.waybill_intake_batches.find(b=>b.id===args.p_batch);b.status='committed';b.result_ids=['saved'];return {data:b.result_ids};}
   if(name==='commit_unknown_cargo_photos')return {data:true};
   assert.fail(name);
  }};
 vm.runInNewContext(source,{...validation,createClient:()=>db,Deno:{env:{get:()=> 'configured'},serve:fn=>handler=fn},Request,Response,Date,crypto,Uint8Array,TextDecoder,AbortSignal,console,
  fetch:async()=>{ocrCalls++;return new Response(JSON.stringify({output:[{content:[{type:'output_text',text:JSON.stringify(ocr)}]}]}),{status:ocrFailure?503:200});}});
 return {data,writes,rpcCalls,signed,get ocrCalls(){return ocrCalls},async call(body,token='valid'){
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
