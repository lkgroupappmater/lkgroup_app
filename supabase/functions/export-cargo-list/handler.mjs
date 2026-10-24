import {buildCargoWorkbook,cargoFields} from './workbook.mjs';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Content-Type':'application/json'};
const json=(status,body)=>new Response(JSON.stringify(body),{status,headers});
export function createCargoListHandler({createClient,url,anonKey,serviceKey,zip,uuid=()=>crypto.randomUUID()}){
 return async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers});
  if(req.method!=='POST')return json(405,{error:'POST required'});
  const authorization=req.headers.get('Authorization')||'',jwt=authorization.replace(/^Bearer\s+/i,'');
  if(!jwt)return json(401,{error:'로그인이 필요합니다.'});
  try{
   const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
   const {data:auth,error:authError}=await admin.auth.getUser(jwt);
   if(authError||!auth?.user?.id)return json(401,{error:'로그인이 필요합니다.'});
   const {data:profile,error:profileError}=await admin.from('profiles').select('role,approval_status,deletion_status').eq('id',auth.user.id).maybeSingle();
   if(profileError)throw profileError;
   if(!profile||!['admin','staff','partner'].includes(profile.role)||profile.approval_status!=='approved'||profile.deletion_status!=='active')return json(403,{error:'승인된 관리자 권한이 필요합니다.'});
   const body=await req.json(),year=Number(body.shipment_year),voyage=String(body.voyage||'').trim(),routeKey=String(body.route_key||'');
   if(!routeKey||!Number.isInteger(year)||year<1900||year>2199||!voyage||voyage==='00'||voyage==='all'||voyage.length>40)return json(400,{error:'운송 경로와 항차를 선택해 주세요.'});
   // All cargo reads use the caller's JWT and normal RLS, including partner scope.
   const reader=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
   const {data:route,error:routeError}=await reader.from('route_definitions').select('route_key,display_name,file_prefix').eq('route_key',routeKey).is('deleted_at',null).maybeSingle();
   if(routeError)throw routeError;if(!route)return json(404,{error:'운송 경로를 찾을 수 없습니다.'});
   const rows=[];let lastId=null;
   for(;;){
    let query=reader.from('shipments').select(cargoFields.join(',')).eq('route',route.display_name).eq('shipment_year',year).eq('voyage',voyage).is('deleted_at',null).is('deletion_requested_at',null).order('id',{ascending:true}).limit(1000);
    if(lastId!=null)query=query.gt('id',lastId);
    const {data,error}=await query;if(error)throw error;
    rows.push(...(data||[]));if(!data?.length||data.length<1000)break;
    const next=data[data.length-1].id;if(next===lastId)throw Error('Cargo pagination did not advance');lastId=next;
   }
   if(!rows.length)return json(404,{error:'선택 항차에 조회 가능한 화물이 없습니다.'});
   const safe=v=>String(v).replace(/[^A-Za-z0-9_-]/g,'_');
   const fileName=`${safe(route.file_prefix||routeKey)}_${year}_V${safe(voyage)}_CARGO_LIST.xlsx`,path=`${routeKey}/${year}/V${safe(voyage)}/${uuid()}_${fileName}`;
   const bytes=buildCargoWorkbook(rows,{route:route.display_name,year,voyage,language:body.language},zip);
   const {error}=await admin.storage.from('shipment-excel-exports').upload(path,bytes,{contentType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',upsert:false});
   if(error)throw error;
   return json(200,{ok:true,file_name:fileName,storage_path:path,shipment_count:rows.length});
  }catch(error){return json(500,{error:error?.message||'Excel 다운로드 실패'});}
 };
}
