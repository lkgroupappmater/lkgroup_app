import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';

// The scheduled worker is restricted to BASE exports. It never imports cargo,
// assigns customer IDs or changes issued statement numbers.
Deno.serve(async(req)=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const token=req.headers.get('x-excel-worker-token')||'';
 if(token.length!==64)return new Response('Unauthorized',{status:401});
 const check=await admin.rpc('lk_validate_excel_worker',{p_token:token});
 if(check.error||check.data!==true)return new Response('Unauthorized',{status:401});
 const invoke=async(body:Record<string,unknown>)=>{
  const response=await fetch(url+'/functions/v1/export-shipment-excel',{method:'POST',headers:{Authorization:'Bearer '+key,apikey:key,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(120000)});
  const result=await response.json();if(!response.ok)throw Error(result.error||result.message||`BASE export failed (${response.status})`);return result;
 };
 try{
  // Common quote copy updates independently from BASE regeneration.
  EdgeRuntime.waitUntil(fetch(url+'/functions/v1/sync-excel-quote-context',{
   method:'POST',headers:{Authorization:'Bearer '+key,apikey:key,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(60000),
  }).then(async response=>{if(!response.ok)console.error('Quote workbook sync',response.status,await response.text());}).catch(error=>console.error('Quote workbook sync',String(error))));
  const version=await invoke({action:'automation_version'});
  const claimed=await admin.rpc('lk_claim_excel_base_sync',{p_exporter_revision:version.exporter_revision});
  if(claimed.error)throw claimed.error;
  const job=claimed.data;if(!job)return Response.json({ok:true,pending:false});
  const run=async()=>{
   try{
    const output=await invoke({route_key:job.route_key,shipment_year:new Date().getUTCFullYear(),voyage:'00',refresh_base:true});
    if(!output.integrity||output.integrity.shared_formula_errors!==0)throw Error('Missing workbook validation');
   }catch(error){
    const saved=await admin.rpc('lk_fail_excel_base_sync',{p_route_key:job.route_key,p_lease_token:job.lease_token,p_error:error instanceof Error?error.message:String(error)});
    if(saved.error)console.error('BASE failure state could not be saved',saved.error.message);
   }
  };
  EdgeRuntime.waitUntil(run());
  return Response.json({ok:true,route_key:job.route_key,status:'running'},{status:202});
 }catch(error){return Response.json({error:error instanceof Error?error.message:'BASE queue failed'},{status:500});}
});
