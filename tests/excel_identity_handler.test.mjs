import test from 'node:test';
import assert from 'node:assert/strict';
import {Unzip,Zip,ZipPassThrough,strToU8} from 'fflate';
import {zipWorkbook,unzipWorkbook} from '../supabase/functions/export-shipment-excel/workbook-zip.mjs';
import {createWorkbookIdentityHandler} from '../supabase/functions/export-shipment-excel/workbook-identity-handler.mjs';
import {createWorkbookFinalizer} from '../supabase/functions/export-shipment-excel/workbook-finalizer-handler.mjs';

const context='_lk_internal_identity_context.json';
const input=await zipWorkbook({[context]:strToU8('{}'),'xl/workbook.xml':strToU8('<workbook/>')},{Zip,ZipPassThrough});
function harness({consume=true,childStatus=200,verified=true}={}){
 let prepares=0,requests=0;
 const handler=createWorkbookIdentityHandler({url:'https://db.example',serviceKey:'internal-test-key',Unzip,Zip,ZipPassThrough,prepareIdentityWorkbook(files,route){assert.equal(route,'kr_la_sea');prepares++;if(consume)delete files[context];},async request(target,options){requests++;assert.equal(new URL(target).pathname,'/functions/v1/finalize-shipment-excel');assert.equal(options.headers.Authorization,'Bearer internal-test-key');assert.equal((await unzipWorkbook(options.body,{Unzip}))[context],undefined);return Response.json({ok:childStatus===200,integrity:{stored_download_verified:verified},storage_path:'verified-output.xlsm'},{status:childStatus});},reportError(){}});
 const request=(auth='Bearer internal-test-key')=>new Request('https://db.example/functions/v1/prepare-shipment-identities?route=kr_la_sea&year=2026&voyage=V10&file_name=SEA.xlsm',{method:'POST',headers:{authorization:auth},body:input});
 return {handler,request,get state(){return {prepares,requests};}};
}
test('identity processing rejects unauthenticated users before touching workbook or calling child',async()=>{
 const h=harness();for(const auth of ['','Bearer member','Bearer admin'])assert.equal((await h.handler(h.request(auth))).status,403);
 assert.deepEqual(h.state,{prepares:0,requests:0});
});
test('identity context is removed before passing the workbook to final storage stage',async()=>{
 const h=harness();const response=await h.handler(h.request());assert.equal(response.status,200);assert.equal((await response.json()).integrity.stored_download_verified,true);assert.deepEqual(h.state,{prepares:1,requests:1});
});
test('unconsumed identity context cannot be sent to finalizer or published',async()=>{
 const h=harness({consume:false});assert.equal((await h.handler(h.request())).status,500);assert.equal(h.state.requests,0);
});
test('failed or unverified child output is never returned as a successful export',async()=>{
 for(const options of [{childStatus:500},{verified:false}]){const h=harness(options),r=await h.handler(h.request()),body=await r.json();assert.equal(r.status,500);assert.equal(body.storage_path,undefined);}
});
test('final storage stage independently rejects private identity context',async()=>{
 let touched=false;
 const handler=createWorkbookFinalizer({url:'https://db.example',serviceKey:'internal-test-key',Unzip,Zip,ZipPassThrough,createClient(){return {storage:{from(){return {upload(){touched=true;throw new Error('Storage must not be used');}};}}};},finalizeWorkbook(){touched=true;},reportError(){}});
 const response=await handler(harness().request());assert.equal(response.status,500);assert.equal(touched,false);
});

test('asynchronous layout preparation is awaited and its audit follows verified storage',async()=>{
 const entry='_lk_internal_delivery_layout.xlsm',audit={version:1,sheets:[{sheet:'지방배송',rows:800}]};
 const body=await zipWorkbook({[context]:strToU8('{}'),[entry]:strToU8('private source'),'xl/workbook.xml':strToU8('<workbook/>')},{Zip,ZipPassThrough});
 const handler=createWorkbookIdentityHandler({url:'https://db.example',serviceKey:'internal-test-key',Unzip,Zip,ZipPassThrough,
  async prepareIdentityWorkbook(files){await new Promise(resolve=>setTimeout(resolve,5));delete files[context];delete files[entry];return audit;},
  async request(target,options){const files=await unzipWorkbook(options.body,{Unzip});assert.equal(files[entry],undefined);assert.equal(files[context],undefined);return Response.json({ok:true,integrity:{stored_download_verified:true}});},reportError(){}});
 const response=await handler(new Request(harness().request().url,{method:'POST',headers:{authorization:'Bearer internal-test-key'},body}));
 assert.equal(response.status,200);assert.deepEqual((await response.json()).integrity.shared_delivery_layout,audit);
});
test('both internal stages reject an unconsumed private layout workbook',async()=>{
 const body=await zipWorkbook({'_lk_internal_delivery_layout.xlsm':strToU8('private source'),'xl/workbook.xml':strToU8('<workbook/>')},{Zip,ZipPassThrough});
 let touched=false;
 const common={url:'https://db.example',serviceKey:'internal-test-key',Unzip,Zip,ZipPassThrough,reportError(){}};
 const identity=createWorkbookIdentityHandler({...common,async prepareIdentityWorkbook(){},async request(){touched=true;}});
 const finalizer=createWorkbookFinalizer({...common,createClient(){return {storage:{from(){return {upload(){touched=true;}};}}};},finalizeWorkbook(){touched=true;}});
 for(const handler of [identity,finalizer]){const request=new Request(harness().request().url,{method:'POST',headers:{authorization:'Bearer internal-test-key'},body});assert.equal((await handler(request)).status,500);}
 assert.equal(touched,false);
});
