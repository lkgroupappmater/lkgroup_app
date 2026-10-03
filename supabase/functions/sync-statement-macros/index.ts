import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import {unzipSync,Zip,ZipPassThrough} from 'npm:fflate@0.8.2';
import {upgradeStatementMacros} from '../export-shipment-excel/statement-macros.mjs';
import {zipWorkbook} from '../export-shipment-excel/workbook-zip.mjs';

// Private, one-file worker. Change only the macro and its existing button text.
// Preserve every worksheet, issued number, formula, image and source backup.
Deno.serve(async(req)=>{
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,url=Deno.env.get('SUPABASE_URL')!;
 if(req.method!=='POST'||req.headers.get('Authorization')!=='Bearer '+key)return new Response('Unauthorized',{status:401});
 const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}}),bucket=db.storage.from('shipment-excel-templates');
 const {data:job,error}=await db.rpc('lk_claim_statement_macro_upgrade');if(error)return Response.json({error:error.message},{status:500});if(!job)return Response.json({ok:true,pending:false});
 let target:string|null=null;
 try{
  const {data:blob,error:downloadError}=await bucket.download(job.source_path);if(downloadError||!blob)throw downloadError||Error('Source download failed');
  const original=new Uint8Array(await blob.arrayBuffer()),files=unzipSync(original),before=new Map(Object.entries(files));
  const workbookText=new TextDecoder().decode(files['xl/workbook.xml']||new Uint8Array());
  const worksheetParts=Object.entries(files).filter(([path])=>/^xl\/worksheets\/sheet[^/]*\.xml$/.test(path));
  const audit={sheet_count:worksheetParts.length,vba_present:!!files['xl/vbaProject.bin'],archive_bytes:original.length,external_links:Object.keys(files).filter(p=>/^xl\/externalLinks\/externalLink[^/]*\.xml$/.test(p)).length,calculation_properties:workbookText.match(/<calcPr\b[^>]*\/>/)?.[0]||null,style_count:(new TextDecoder().decode(files['xl/styles.xml']||new Uint8Array()).match(/<xf\b/g)||[]).length};
  const result=upgradeStatementMacros(files),changed=Object.keys(files).filter(path=>files[path]!==before.get(path));
  if(changed.some(path=>path!=='xl/vbaProject.bin'&&!/^(xl\/(drawings|ctrlProps)\/|customUI\/)/.test(path)))throw Error('Unexpected workbook part changed');
  const hash=async(bytes:Uint8Array)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(v=>v.toString(16).padStart(2,'0')).join('');
  const sourceHash=await hash(original);let targetHash=sourceHash;
  if(result.changed){
   const encoded=await zipWorkbook(files,{Zip,ZipPassThrough}),reopened=unzipSync(encoded);
   for(const [path,bytes] of before)if(!changed.includes(path)&&await hash(bytes)!==await hash(reopened[path]))throw Error('Unrelated workbook part changed: '+path);
   if(upgradeStatementMacros(reopened).changed)throw Error('Macro update is not idempotent');
   target=`macro-updates/${job.route_key}/${crypto.randomUUID()}.xlsm`;
   const uploaded=await bucket.upload(target,encoded,{upsert:false,contentType:'application/vnd.ms-excel.sheet.macroEnabled.12'});if(uploaded.error)throw uploaded.error;
   const saved=await bucket.download(target);if(saved.error||!saved.data)throw saved.error||Error('Saved file unavailable');targetHash=await hash(encoded);if(await hash(new Uint8Array(await saved.data.arrayBuffer()))!==targetHash)throw Error('Saved workbook verification failed');
  }
  const details={...result,audit,source_sha256:sourceHash,target_sha256:targetHash,changed_parts:changed,unrelated_parts_unchanged:true,stored_download_verified:true};
  const completed=await db.rpc('lk_finish_statement_macro_upgrade',{p_resource_key:job.resource_key,p_lease_token:job.lease_token,p_target_path:target,p_details:details});
  if(completed.error)throw completed.error;if(completed.data!==true&&target)await bucket.remove([target]);
  return Response.json({ok:true,resource:job.resource_key,...details,committed:completed.data});
 }catch(e){
  if(target)await bucket.remove([target]);
  const message=e instanceof Error?e.message:String(e);await db.rpc('lk_finish_statement_macro_upgrade',{p_resource_key:job.resource_key,p_lease_token:job.lease_token,p_target_path:null,p_details:{},p_error:message});
  return Response.json({error:message,resource:job.resource_key},{status:500});
 }
});
