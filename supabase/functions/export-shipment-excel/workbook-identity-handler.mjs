import {unzipWorkbook,zipWorkbook} from './workbook-zip.mjs';
import {exportMetadata} from './workbook-finalizer-handler.mjs';
const json=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});

export function createWorkbookIdentityHandler({url,serviceKey,Unzip,Zip,ZipPassThrough,prepareIdentityWorkbook,request=fetch,reportError=console.error}){
 return async req=>{
  if(req.method!=='POST')return json(405,{error:'Method not allowed'});
  if(!url||!serviceKey)return json(500,{error:'Excel identity configuration is missing.'});
  if(req.headers.get('authorization')!==`Bearer ${serviceKey}`)return json(403,{error:'Internal Excel processing only.'});
  const metadata=exportMetadata(req.url);if(!metadata)return json(400,{error:'Invalid Excel output metadata.'});
  try{
   const files=await unzipWorkbook(new Uint8Array(await req.arrayBuffer()),{Unzip});
   const deliveryLayout=await prepareIdentityWorkbook(files,metadata.route);
   if(files['_lk_internal_identity_context.json']||files['_lk_internal_delivery_layout.xlsm'])throw new Error('Internal Excel context was not consumed.');
   const prepared=await zipWorkbook(files,{Zip,ZipPassThrough});
   const target=new URL(url+'/functions/v1/finalize-shipment-excel');target.search=new URL(req.url).search;
   const response=await request(target,{method:'POST',headers:{Authorization:'Bearer '+serviceKey,apikey:serviceKey,'Content-Type':'application/octet-stream'},body:prepared,signal:AbortSignal.timeout(90000)});
   const completed=await response.json().catch(()=>null);
   if(!response.ok||!completed?.ok||!completed?.integrity?.stored_download_verified)throw new Error(completed?.error||'Excel 최종 검증·저장 처리에 실패했습니다.');
   if(deliveryLayout)completed.integrity.shared_delivery_layout=deliveryLayout;
   return json(200,completed);
  }catch(error){reportError('prepare-shipment-identities failed:',error);return json(500,{error:error?.message||'Excel 고객 ID 반영에 실패했습니다.'});}
 };
}

