// Internal final stage. Only the server's existing service credential may call
// it; member/admin JWTs cannot upload an arbitrary workbook through this route.
import {unzipWorkbook,zipWorkbook} from './workbook-zip.mjs';

const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const sha256=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(v=>v.toString(16).padStart(2,'0')).join('');
export function exportMetadata(requestUrl){
 const query=new URL(requestUrl).searchParams,route=query.get('route'),year=query.get('year'),voyage=query.get('voyage'),name=query.get('file_name');
 if(!/^[a-z0-9_]+$/.test(route||'')||!/^\d{4}$/.test(year||'')||!/^V[\p{L}\p{N}_-]+$/u.test(voyage||'')||
    !name||/[\/\\\u0000-\u001f]/.test(name)||!/^.+\.xls[mx]$/.test(name))return null;
 return {route,year,voyage,name};
}
export function createWorkbookFinalizer({url,serviceKey,createClient,Unzip,Zip,ZipPassThrough,finalizeWorkbook,reportError=console.error}){
 return async req=>{
  if(req.method!=='POST')return json(405,{error:'Method not allowed'});
  if(!url||!serviceKey)return json(500,{error:'Excel finalizer configuration is missing.'});
  if(req.headers.get('authorization')!==`Bearer ${serviceKey}`)return json(403,{error:'Internal Excel processing only.'});
  const metadata=exportMetadata(req.url);if(!metadata)return json(400,{error:'Invalid Excel output metadata.'});
  const {route,year,voyage,name}=metadata;
  const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}}),bucket=admin.storage.from('shipment-excel-exports');
  let storedPath;
  try{
   const files=await unzipWorkbook(new Uint8Array(await req.arrayBuffer()),{Unzip});
   if(files['_lk_internal_identity_context.json']||files['_lk_internal_delivery_layout.xlsm'])throw new Error('Excel identity preparation was not completed.');
   const integrity=finalizeWorkbook(files);
   const encoded=await zipWorkbook(files,{Zip,ZipPassThrough});
   const stamp=new Date().toISOString().replace(/[:.]/g,'-');
   const path=`${route}/${year}/${voyage}/${stamp}_${name}`;
   const saved=await bucket.upload(path,encoded,{upsert:false,contentType:name.endsWith('.xlsm')?'application/vnd.ms-excel.sheet.macroEnabled.12':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
   if(saved.error)throw saved.error;storedPath=path;
   // A success response means the stored file was downloaded and matched, not
   // merely that workbook generation reached its final console log.
   const downloaded=await bucket.download(path);
   if(downloaded.error||!downloaded.data)throw downloaded.error??new Error('저장된 Excel 파일 확인 실패');
   const restored=new Uint8Array(await downloaded.data.arrayBuffer());
   if(restored.length!==encoded.length||await sha256(restored)!==await sha256(encoded))throw new Error('저장된 Excel 파일의 내용 검증에 실패했습니다. 다시 다운로드해 주세요.');
   return json(200,{ok:true,file_name:name,storage_path:path,integrity:{...integrity,stored_download_verified:true}});
  }catch(error){
   if(storedPath)await bucket.remove([storedPath]).catch(()=>{});
   reportError('finalize-shipment-excel failed:',error);
   return json(500,{error:error?.message||'Excel 최종 검증·저장에 실패했습니다.'});
  }
 };
}

