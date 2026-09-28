import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import {unzipSync} from 'https://esm.sh/fflate@0.8.2';
import {extractWorkbookCopy} from './workbook-copy.mjs';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Content-Type':'application/json'};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return new Response('Method not allowed',{status:405,headers});
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,auth=req.headers.get('authorization')||'';
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 let source:any;
 try{
  const worker=auth===`Bearer ${key}`;
  if(!worker){
   const identity=await admin.auth.getUser(auth.replace(/^Bearer /i,''));
   if(identity.error||!identity.data.user)return new Response('{"error":"Unauthorized"}',{status:401,headers});
   const profile=await admin.from('profiles').select('role,deleted_at').eq('id',identity.data.user.id).single();
   if(profile.error||profile.data?.role!=='admin'||profile.data.deleted_at)return new Response('{"error":"Forbidden"}',{status:403,headers});
  }
  const body=await req.json();
  let query=admin.from('excel_quote_sources').select('route_key,storage_path,source_at,synced_at').is('synced_at',null);
  if(body.route_key)query=query.eq('route_key',body.route_key);
  else if(!worker)return new Response('{"error":"Route required"}',{status:400,headers});
  else query=query.or(`attempted_at.is.null,attempted_at.lt.${new Date(Date.now()-300000).toISOString()}`);
  const pending=await query.order('source_at').limit(1).maybeSingle();if(pending.error)throw pending.error;
  source=pending.data;if(!source)return new Response('{"ok":true,"pending":false}',{headers});
  const file=await admin.storage.from('shipment-excel-templates').download(source.storage_path);
  if(file.error||!file.data)throw file.error||Error('Excel source missing');
  const copy=extractWorkbookCopy(new Uint8Array(await file.data.arrayBuffer()),unzipSync);
  const saved=await admin.rpc('lk_commit_excel_quote_context',{p_route_key:source.route_key,p_path:source.storage_path,p_source_at:source.source_at,p_footer_lines:copy.footer_lines});
  if(saved.error)throw saved.error;if(!saved.data)throw Error('Excel source changed; retry latest upload');
  return new Response(JSON.stringify({ok:true,route_key:source.route_key,footer_count:copy.footer_lines.length}),{headers});
 }catch(error){
  const message=error instanceof Error?error.message:String(error);
  if(source)await admin.from('excel_quote_sources').update({last_error:message,attempted_at:new Date().toISOString()}).eq('route_key',source.route_key).eq('source_at',source.source_at);
  return new Response(JSON.stringify({error:message}),{status:422,headers});
 }
});
