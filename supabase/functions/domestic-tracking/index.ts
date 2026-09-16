import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { CARRIERS, STATUSES, trackingNumber, carrierUrl, fetchTracking, mergeEvents, canSeePhoto, laoTimestamp } from './carriers.mjs';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const json=(status:number,data:unknown)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
class ApiError extends Error{constructor(public status:number,code:string){super(code)}}
const must=(ok:unknown,code:string,status=400)=>{if(!ok)throw new ApiError(status,code)};
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const text=(v:unknown,max:number)=>{const s=String(v??'').trim();must(s.length<=max,'FIELD_TOO_LONG');return s};
const dbResult=(r:any)=>{if(r.error)throw new ApiError(r.error.code==='23505'?409:500,r.error.code==='23505'?'DUPLICATE_TRACKING':'DATABASE_ERROR');return r.data};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json(405,{error:'METHOD_NOT_ALLOWED'});
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');must(token,'LOGIN_REQUIRED',401);
  const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await db.auth.getUser(token);must(!auth.error&&auth.data.user,'LOGIN_REQUIRED',401);
  const user=auth.data.user!;
  const profile=dbResult(await db.from('profiles').select('id,role,name,phone,approval_status,deletion_status,deleted_at').eq('id',user.id).maybeSingle());
  must(profile&&!profile.deleted_at&&!['pending','deleted'].includes(profile.deletion_status)&&!['pending','rejected'].includes(profile.approval_status),'ACCOUNT_NOT_ACTIVE',403);
  const allowed=dbResult(await db.rpc('consume_domestic_tracking_limit',{p_user_id:user.id}));must(allowed,'TOO_MANY_REQUESTS',429);
  must(Number(req.headers.get('Content-Length')??0)<=7500000,'FILE_TOO_LARGE',413);
  const raw=await req.text();must(raw.length<=7500000,'FILE_TOO_LARGE',413);
  let b:any;try{b=JSON.parse(raw)}catch{throw new ApiError(400,'INVALID_REQUEST')}
  must(b&&typeof b==='object'&&!Array.isArray(b),'INVALID_REQUEST');
  const manager=['admin','staff'].includes(profile.role),partner=profile.role==='partner';
  const cargoFields='id,box_number,invoice_number,route,shipment_year,voyage,customer_id,consignee_name,consignee_phone,deleted_at,deletion_requested_at';
  const shipment=async(id:number|null)=>id?dbResult(await db.from('shipments').select(cargoFields).eq('id',id).maybeSingle()):null;
  async function serialize(row:any,full=false){
   const s=await shipment(row.shipment_id);const own=canSeePhoto(profile,row,s),visible=full||own;
   let photo_url=null;if(row.photo_path&&own){const result=await db.storage.from('domestic-waybills').createSignedUrl(row.photo_path,600);if(!result.error)photo_url=result.data.signedUrl;}
   return {id:row.id,carrier:row.carrier,carrier_name:CARRIERS[row.carrier].name,tracking_number:row.tracking_number,
    delivery_kind:row.delivery_kind,service_kind:row.service_kind,origin:row.origin,destination:row.destination,
    status:row.status,events:row.events,sync_state:row.sync_state,sync_error:row.sync_error,checked_at:row.checked_at,synced_at:row.synced_at,
    official_url:carrierUrl(row.carrier,row.tracking_number),integration:CARRIERS[row.carrier].mode,
    has_photo:!!row.photo_path,photo_url,photo_restricted:!!row.photo_path&&!own,
    ...(visible?{shipment_id:row.shipment_id,cargo:s?{id:s.id,box_number:s.box_number,invoice_number:s.invoice_number,route:s.route,shipment_year:s.shipment_year,voyage:s.voyage}:null,receiver_name:row.receiver_name,receiver_phone:row.receiver_phone}:{}),
    created_at:row.created_at,updated_at:row.updated_at,can_manage:manager};
  }
  async function sync(row:any){
   const now=new Date(),cutoff=new Date(now.getTime()-300000).toISOString();
   if(row.checked_at&&row.checked_at>cutoff)return row;
   const claimed=dbResult(await db.from('domestic_parcels').update({checked_at:now.toISOString()}).eq('id',row.id).or(`checked_at.is.null,checked_at.lt.${cutoff}`).select().maybeSingle());
   if(!claimed)return dbResult(await db.from('domestic_parcels').select('*').eq('id',row.id).single());
   let update:any;
   try{
    const result=await fetchTracking(row.carrier,row.tracking_number);
    // Re-read to preserve a staff entry made while the carrier request was in flight.
    const latest=dbResult(await db.from('domestic_parcels').select('events,updated_at').eq('id',row.id).single());
    const events=mergeEvents(latest.events,result.events);
    update={events,status:result.status==='returned'?'returned':events[0]?.status??result.status,updated_at:new Date().toISOString(),origin:result.origin,destination:result.destination,sync_state:'synced',sync_error:null,synced_at:now.toISOString()};
    const saved=dbResult(await db.from('domestic_parcels').update(update).eq('id',row.id).eq('updated_at',latest.updated_at).select().maybeSingle());
    return saved??dbResult(await db.from('domestic_parcels').select('*').eq('id',row.id).single());
   }catch(e){
    const code=String((e as Error).message);const known=['CONNECTION_REQUIRED','PLANNED','VERIFICATION_REQUIRED','AUTH_REQUIRED','NOT_FOUND','NO_EVENTS','ANS_ORIGINAL_NUMBER_REQUIRED','RATE_LIMITED','CARRIER_FORMAT_CHANGED'];
    update={sync_state:code==='PLANNED'?'planned':code==='VERIFICATION_REQUIRED'?'verification_required':'error',sync_error:known.includes(code)?code:'CARRIER_UNAVAILABLE'};
   }
   return dbResult(await db.from('domestic_parcels').update(update).eq('id',row.id).select().single());
  }
  if(b.action==='statement_lookup'){
   const number=text(b.statement_number,80).toUpperCase();
   must(/^[A-Z0-9][A-Z0-9./_-]{0,79}$/.test(number),'INVALID_STATEMENT');
   const route=text(b.route,160),voyage=text(b.voyage,40);
   const year=b.shipment_year==null||b.shipment_year===''?null:Number(b.shipment_year);
   must(year===null||Number.isInteger(year)&&year>=1900&&year<=2200,'INVALID_YEAR');
   const page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   // Query exact identifiers only. Underscores must not become LIKE wildcards.
   const pattern=number.replace(/_/g,'\\_');
   const found=new Map<number,any>();
   for(const field of ['invoice_number','box_number']){
    let q=db.from('shipments').select(cargoFields).is('deleted_at',null).is('deletion_requested_at',null).ilike(field,pattern);
    if(route)q=q.eq('route',route);if(year!==null)q=q.eq('shipment_year',year);
    const rows=dbResult(await q.order('id').limit(101));
    must(rows.length<=100,'NARROW_SEARCH');
    for(const s of rows){
     if(voyage&&String(s.voyage??'').replace(/^0+/,'')!==voyage.replace(/^0+/,''))continue;
     // A statement lookup must not reveal another customer's linked waybills.
     if(canSeePhoto(profile,{},s))found.set(s.id,s);
    }
   }
   if(!found.size)return json(200,{parcels:[],has_more:false,cargo_count:0});
   const rows=dbResult(await db.from('domestic_parcels').select('*').in('shipment_id',[...found.keys()]).order('shipment_id').order('created_at').order('id').range(page*20,page*20+20));
   const parcels=[];
   for(let i=0;i<Math.min(rows.length,20);i+=4){
    parcels.push(...await Promise.all(rows.slice(i,Math.min(i+4,20)).map(async(r:any)=>serialize(await sync(r)))));
   }
   return json(200,{parcels,has_more:rows.length>20,cargo_count:found.size});
  }
  if(b.action==='lookup'){
   const number=trackingNumber(b.tracking_number);must(!b.carrier||CARRIERS[b.carrier],'INVALID_CARRIER');
   let q=db.from('domestic_parcels').select('*').eq('tracking_number',number);if(b.carrier)q=q.eq('carrier',b.carrier);
   const rows=dbResult(await q.limit(5));const parcels=[];
   for(const r of rows)parcels.push(await serialize(await sync(r)));
   return json(200,{parcels});
  }
  if(b.action==='list'){
   must(manager||partner,'FORBIDDEN',403);const page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   let q=db.from('domestic_parcels').select('*').order('created_at',{ascending:false}).order('id').range(page*50,page*50+49);
   if(b.carrier){must(CARRIERS[b.carrier],'INVALID_CARRIER');q=q.eq('carrier',b.carrier)}
   const rows=dbResult(await q);return json(200,{parcels:await Promise.all(rows.map((r:any)=>serialize(r,true))),has_more:rows.length===50});
  }
  if(b.action==='cargo_search'){
   must(manager,'FORBIDDEN',403);const q=text(b.query,50);must(q.length>=2,'SEARCH_TOO_SHORT');
   must(/^[A-Za-z0-9./_-]+$/.test(q),'INVALID_STATEMENT');
   const found=new Map<number,any>();
   for(const field of ['invoice_number','box_number']){
    const rows=dbResult(await db.from('shipments').select('id,box_number,invoice_number,route,shipment_year,voyage,consignee_name,consignee_phone').is('deleted_at',null).is('deletion_requested_at',null).ilike(field,'%'+q.replace(/_/g,'\\_')+'%').order('id',{ascending:false}).limit(30));
    for(const row of rows)found.set(row.id,row);
   }
   return json(200,{cargo:[...found.values()].sort((a,b)=>b.id-a.id).slice(0,30)});
  }
  must(manager,'FORBIDDEN',403);
  if(b.action==='save'){
   const id=b.id||crypto.randomUUID();must(uuid(id),'INVALID_ID');must(CARRIERS[b.carrier],'INVALID_CARRIER');
   const number=trackingNumber(b.tracking_number);const old=b.id?dbResult(await db.from('domestic_parcels').select('*').eq('id',id).maybeSingle()):null;
   if(b.id){must(old,'NOT_FOUND',404);must(b.updated_at===old.updated_at,'RECORD_CHANGED',409);must(old.carrier===b.carrier&&old.tracking_number===number,'TRACKING_IMMUTABLE')}
   must(['city','province'].includes(b.delivery_kind),'INVALID_DELIVERY_KIND');must(['domestic','inbound','outbound','ecommerce','express'].includes(b.service_kind),'INVALID_SERVICE_KIND');
   const shipment_id=b.shipment_id?Number(b.shipment_id):null;must(shipment_id===null||Number.isSafeInteger(shipment_id)&&shipment_id>0,'INVALID_CARGO');
   const cargo=await shipment(shipment_id);if(shipment_id)must(cargo&&!cargo.deleted_at&&!cargo.deletion_requested_at,'INVALID_CARGO');
   const value:any={id,carrier:b.carrier,tracking_number:number,shipment_id,delivery_kind:b.delivery_kind,service_kind:b.service_kind,
    receiver_name:text(cargo?.consignee_name??b.receiver_name,160),receiver_phone:text(cargo?.consignee_phone??b.receiver_phone,40),updated_at:new Date().toISOString(),updated_by:user.id};
   let newPhoto:string|null=null;
   if(b.photo){
    must(typeof b.photo.base64==='string'&&b.photo.base64.length<=6990508,'FILE_TOO_LARGE',413);
    let bytes:Uint8Array;try{bytes=Uint8Array.from(atob(b.photo.base64),c=>c.charCodeAt(0))}catch{throw new ApiError(400,'INVALID_IMAGE')}
    must(bytes.length>12&&bytes.length<=5242880,'FILE_TOO_LARGE',413);
    const png=bytes[0]===137&&bytes[1]===80&&bytes[2]===78&&bytes[3]===71;
    const jpg=bytes[0]===255&&bytes[1]===216&&bytes[2]===255;
    const webp=String.fromCharCode(...bytes.slice(0,4))==='RIFF'&&String.fromCharCode(...bytes.slice(8,12))==='WEBP';
    must(png||jpg||webp,'INVALID_IMAGE');const ext=png?'png':jpg?'jpg':'webp',mime=png?'image/png':jpg?'image/jpeg':'image/webp';
    newPhoto=`${id}/${crypto.randomUUID()}.${ext}`;dbResult(await db.storage.from('domestic-waybills').upload(newPhoto,bytes,{contentType:mime,upsert:false}));value.photo_path=newPhoto;
   }
   const result=old?await db.from('domestic_parcels').update(value).eq('id',id).eq('updated_at',old.updated_at).select().maybeSingle():await db.from('domestic_parcels').insert({...value,created_by:user.id}).select().single();
   if(result.error||!result.data){if(newPhoto)await db.storage.from('domestic-waybills').remove([newPhoto]);if(!result.error)throw new ApiError(409,'RECORD_CHANGED');dbResult(result)}
   // Old images expire naturally from signed links; retain them for recovery.
   return json(200,{parcel:await serialize(result.data,true)});
  }
  if(b.action==='add_event'){
   must(uuid(b.id),'INVALID_ID');must(STATUSES.includes(b.status),'INVALID_STATUS');
   const at=laoTimestamp(b.occurred_at);must(at&&new Date(at).getTime()<=Date.now()+300000,'INVALID_DATE');
   const description=text(b.description,1200),location=text(b.location,240);must(description,'DESCRIPTION_REQUIRED');
   const old=dbResult(await db.from('domestic_parcels').select('*').eq('id',b.id).maybeSingle());must(old,'NOT_FOUND',404);must(old.updated_at===b.updated_at,'RECORD_CHANGED',409);
   const event={key:'manual:'+crypto.randomUUID(),occurred_at:at,location,description,status:b.status,source:'staff'};
   const events=mergeEvents(old.events,[event]);const result=dbResult(await db.from('domestic_parcels').update({events,status:events[0].status,updated_at:new Date().toISOString(),updated_by:user.id}).eq('id',b.id).eq('updated_at',old.updated_at).select().maybeSingle());must(result,'RECORD_CHANGED',409);
   return json(200,{parcel:await serialize(result,true)});
  }
  return json(400,{error:'INVALID_ACTION'});
 }catch(e){const code=(e as Error).message;if(e instanceof ApiError)return json(e.status,{error:code});if(code==='INVALID_TRACKING')return json(400,{error:code});console.error('domestic-tracking request failed:',e instanceof Error?e.name:'error');return json(500,{error:'REQUEST_FAILED'})}
});
