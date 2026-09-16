import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import * as carriers from './carriers.mjs';
import * as statements from './statements.mjs';
const source=stripTypeScriptTypes(fs.readFileSync(new URL('./index.ts',import.meta.url),'utf8').replace(/^import .+;\n/gm,''),{mode:'transform'});
function setup({role='member',active=true,authenticated=true,rate=true}={}){
 let handler,mutations=0;
 const profile={id:'user',role,approval_status:active?'approved':'pending',deletion_status:null};
 const db={auth:{getUser:async()=>({data:{user:authenticated?{id:'user'}:null},error:!authenticated})},rpc:async()=>({data:rate}),from(table){
  assert.equal(table,'profiles');return {select(){return this},eq(){return this},async maybeSingle(){return {data:profile}}};
 }};
 vm.runInNewContext(source,{...carriers,...statements,createClient:()=>db,Deno:{env:{get:()=>''},serve:fn=>{handler=fn}},Request,Response,Date,crypto,Uint8Array,atob,console});
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
 for(const role of ['member','partner'])for(const action of ['save','add_event','cargo_search','statement_resolve','recommend_carrier'])assert.equal((await setup({role})({action})).status,403);
 assert.equal((await setup()({action:'list'})).status,403);
});
test('rate limit, malformed bodies and invalid full identifiers stop before database mutation',async()=>{
 assert.equal((await setup({rate:false})({action:'lookup'})).status,429);
 assert.equal((await setup()(null)).status,400);
 assert.equal((await setup()({action:'lookup',tracking_number:'../bad'})).status,400);
 assert.equal((await setup({role:'admin'})({action:'save',carrier:'bad'})).status,400);
});
