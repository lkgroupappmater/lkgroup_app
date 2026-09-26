import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { CARRIERS, STATUSES, trackingNumber, carrierUrl, fetchTracking, mergeEvents, canSeePhoto, laoTimestamp } from './carriers.mjs';
import { receiptKey, statementInput, referenceInput, rowStatement, canManageParcel, mapLimited, maskName, maskPhone, photoPaths, deliveryGroup } from './statements.mjs';
import { decodePhotos, readBody, MAX_PHOTOS } from './photos.mjs';
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
  const raw=await readBody(req);
  let b:any;try{b=JSON.parse(raw)}catch{throw new ApiError(400,'INVALID_REQUEST')}
  must(b&&typeof b==='object'&&!Array.isArray(b),'INVALID_REQUEST');
  const manager=['admin','staff'].includes(profile.role),partner=profile.role==='partner',operator=manager||partner;
  const cargoFields='id,box_number,invoice_number,receipt_number,route,shipment_year,voyage,customer_id,consignee_name,consignee_phone,deleted_at,deletion_requested_at';
  const shipment=async(id:number|null)=>id?dbResult(await db.from('shipments').select(cargoFields).eq('id',id).maybeSingle()):null;
  async function allRows(query:any) {
   const rows=[];
   for(let page=0;page<21;page++){
    const batch=dbResult(await query().range(page*500,page*500+499));rows.push(...batch);
    must(rows.length<=10000,'NARROW_SEARCH');if(batch.length<500)return rows;
   }
   throw new ApiError(400,'NARROW_SEARCH');
  }
  async function findCargo(input:any,receiptOnly=false){
   const number=text(input.receipt_number??input.statement_number,80);
   must(/^[A-Za-z0-9][A-Za-z0-9 .\/_-]{0,79}$/.test(number),'INVALID_STATEMENT');
   const route=text(input.route,160),voyage=text(input.voyage,40);
   const year=input.shipment_year==null||input.shipment_year===''?null:Number(input.shipment_year);
   must(year===null||Number.isInteger(year)&&year>=1900&&year<=2200,'INVALID_YEAR');
   const rows=dbResult(await db.rpc('domestic_find_delivery_cargo',{p_number:number,p_route:route||null,p_year:year,p_voyage:voyage||null,p_receipt_only:receiptOnly}));
   must(rows.length<=500,'NARROW_SEARCH');return rows;
  }
  const statementCache=new Map<string,Promise<any>>();
  async function resolveStatement(input:any){
   const value=statementInput(input),key=JSON.stringify(value);
   if(!statementCache.has(key))statementCache.set(key,(async()=>{
    const rows=await findCargo(value,true);
    const identities=new Set(rows.map((r:any)=>JSON.stringify([r.route,r.shipment_year,receiptKey(r.voyage),receiptKey(r.receipt_number)])));
    must(identities.size<=1,'AMBIGUOUS_STATEMENT');
    const first=rows[0];
    return {statement:first?{route:first.route,shipment_year:first.shipment_year,voyage:first.voyage,receipt_number:first.receipt_number}:value,rows};
   })());
   return await statementCache.get(key);
  }
  async function photoAccess(row:any,s:any){
   if(operator)return true;
   const ref=rowStatement(row);
   if(ref){const linked=await resolveStatement(ref);return linked.rows.length>0&&linked.rows.every((r:any)=>canSeePhoto(profile,{},r));}
   return canSeePhoto(profile,row,s);
  }
  const photoCache=new Map<string,Promise<string|null>>();
  async function serialize(row:any,full=false){
   const s=await shipment(row.shipment_id),own=await photoAccess(row,s);
   const statement=rowStatement(row)??(s?.receipt_number?{route:s.route,shipment_year:s.shipment_year,voyage:s.voyage,receipt_number:s.receipt_number}:null);
   const paths=photoPaths(row);let photo_urls:any[]=[];
   if(own)photo_urls=await Promise.all(paths.map((path:string)=>{
    if(!photoCache.has(path))photoCache.set(path,(async()=>{
     if(!operator&&path.startsWith('intake/')){
      const linked=await allRows(()=>db.from('domestic_parcels').select('*').contains('photo_paths',[path]).order('id'));
      for(const other of linked)if(!await photoAccess(other,await shipment(other.shipment_id)))return null;
     }
     const r=await db.storage.from('domestic-waybills').createSignedUrl(path,600);return r.error?null:r.data.signedUrl;
    })());
    return photoCache.get(path);
   }));
   photo_urls=photo_urls.filter(Boolean);
   const events=own?row.events:(row.events??[]).map((e:any,i:number)=>({key:`redacted:${i}`,occurred_at:e.occurred_at,status:e.status,source:e.source,description:'',location:''}));
   return {id:row.id,carrier:row.carrier,carrier_name:CARRIERS[row.carrier].name,tracking_number:row.tracking_number,
    delivery_kind:row.delivery_kind,service_kind:row.service_kind,origin:own?row.origin:'',destination:own?row.destination:'',
    status:row.status,events,sync_state:row.sync_state,sync_error:row.sync_error,checked_at:row.checked_at,synced_at:row.synced_at,
    official_url:own?carrierUrl(row.carrier,row.tracking_number):null,integration:CARRIERS[row.carrier].mode,
    has_photo:paths.length>0,photo_url:photo_urls[0]??null,photo_urls,photo_count:paths.length,photo_restricted:paths.length>0&&(!own||photo_urls.length<paths.length),
    group_key:deliveryGroup(row,s),link_scope:row.link_scope??(s?'cargo':'standalone'),statement,
    reference_type:row.reference_type??null,reference_number:row.reference_number??null,
    shipment_id:own?row.shipment_id:null,
    cargo:own&&s?{id:s.id,box_number:s.box_number,invoice_number:s.invoice_number,receipt_number:s.receipt_number,route:s.route,shipment_year:s.shipment_year,voyage:s.voyage}:null,
    receiver_name:own?row.receiver_name:maskName(row.receiver_name),receiver_phone:own?row.receiver_phone:maskPhone(row.receiver_phone),recipient_masked:!own,
    created_at:row.created_at,updated_at:row.updated_at,can_manage:canManageParcel(profile,row)};
  }
  async function sync(row:any){
   const now=new Date(),cutoff=new Date(now.getTime()-300000).toISOString();
   if(row.checked_at&&row.checked_at>cutoff)return row;
   const claimed=dbResult(await db.from('domestic_parcels').update({checked_at:now.toISOString()}).eq('id',row.id).eq('carrier',row.carrier).eq('tracking_number',row.tracking_number).or(`checked_at.is.null,checked_at.lt.${cutoff}`).select().maybeSingle());
   if(!claimed)return dbResult(await db.from('domestic_parcels').select('*').eq('id',row.id).single());
   let update:any;
   try{
    const result=await fetchTracking(row.carrier,row.tracking_number);
    // Re-read to preserve a staff entry made while the carrier request was in flight.
    const latest=dbResult(await db.from('domestic_parcels').select('events,updated_at').eq('id',row.id).single());
    const events=mergeEvents(latest.events,result.events);
    update={events,status:result.status==='returned'?'returned':events[0]?.status??result.status,updated_at:new Date().toISOString(),origin:result.origin,destination:result.destination,sync_state:'synced',sync_error:null,synced_at:now.toISOString()};
    const saved=dbResult(await db.from('domestic_parcels').update(update).eq('id',row.id).eq('carrier',row.carrier).eq('tracking_number',row.tracking_number).eq('updated_at',latest.updated_at).select().maybeSingle());
    return saved??dbResult(await db.from('domestic_parcels').select('*').eq('id',row.id).single());
   }catch(e){
    const code=String((e as Error).message);const known=['CONNECTION_REQUIRED','PLANNED','VERIFICATION_REQUIRED','AUTH_REQUIRED','NOT_FOUND','NO_EVENTS','ANS_ORIGINAL_NUMBER_REQUIRED','RATE_LIMITED','CARRIER_FORMAT_CHANGED'];
    update={sync_state:code==='PLANNED'?'planned':code==='VERIFICATION_REQUIRED'?'verification_required':'error',sync_error:known.includes(code)?code:'CARRIER_UNAVAILABLE'};
   }
   return dbResult(await db.from('domestic_parcels').update(update).eq('id',row.id).eq('carrier',row.carrier).eq('tracking_number',row.tracking_number).select().maybeSingle())??dbResult(await db.from('domestic_parcels').select('*').eq('id',row.id).single());
  }
  async function refreshRows(rows:any[]){
   const cutoff=new Date(Date.now()-300000).toISOString();
   const pending=rows.filter(r=>!r.checked_at||r.checked_at<cutoff).sort((a,b)=>String(a.checked_at??'').localeCompare(String(b.checked_at??''))).slice(0,20);
   const refreshed=new Map((await mapLimited(pending,async(r:any)=>await sync(r),4)).map((r:any)=>[r.id,r]));
   return rows.map(r=>refreshed.get(r.id)??r);
  }
  async function present(rows:any[]){return await mapLimited(await refreshRows(rows),async(r:any)=>await serialize(r));}
  async function uploadPhotos(body:any,existing:string[]=[],folder=crypto.randomUUID()){
   const decoded=decodePhotos(body);
   let staged:string[]=[];
   if(body.staged_batch_id){
    must(uuid(body.staged_batch_id),'INVALID_ID');
    const batch=dbResult(await db.from('waybill_intake_batches').select('*').eq('id',body.staged_batch_id).eq('owner_id',user.id).maybeSingle());
    must(batch&&batch.purpose==='photos'&&new Date(batch.created_at).getTime()>Date.now()-86400000,'INVALID_IMAGE');
    const files=dbResult(await db.from('waybill_intake_files').select('path,verified_at,size_bytes').eq('batch_id',batch.id));
    must(files.length>0&&files.length<=50&&files.every((f:any)=>f.verified_at&&f.size_bytes<=5242880)&&files.reduce((n:number,f:any)=>n+f.size_bytes,0)<=262144000,'INVALID_IMAGE');
    staged=files.map((f:any)=>f.path);
   }
   must(new Set([...existing,...staged]).size+decoded.length<=MAX_PHOTOS,'TOO_MANY_PHOTOS');
   const created:string[]=[];
   try{
    for(const image of decoded){const path=`${folder}/${crypto.randomUUID()}.${image.ext}`;dbResult(await db.storage.from('domestic-waybills').upload(path,image.bytes,{contentType:image.mime,upsert:false}));created.push(path);}
    return {paths:[...new Set([...existing,...staged,...created])],created};
   }catch(e){if(created.length)await db.storage.from('domestic-waybills').remove(created);throw e;}
  }
  async function linkValues(input:any,old:any=null){
   must(['city','province'].includes(input.delivery_kind),'INVALID_DELIVERY_KIND');must(['domestic','inbound','outbound','ecommerce','express'].includes(input.service_kind),'INVALID_SERVICE_KIND');
   const scope=input.link_scope??input.link_mode??(['statement','reference'].includes(old?.link_scope)?old.link_scope:Object.prototype.hasOwnProperty.call(input,'shipment_id')?(input.shipment_id?'cargo':'standalone'):old?.link_scope??'standalone');
   must(['cargo','statement','reference','standalone'].includes(scope),'INVALID_LINK_SCOPE');
   const resolved=scope==='statement'?await resolveStatement(input.statement??rowStatement(old??{})):null;
   if(resolved)must(resolved.rows.length,'STATEMENT_NOT_FOUND',404);
   const reference=scope==='reference'?referenceInput(input.reference??(input.reference_type?input:old??{})):null;
   const shipment_id=scope==='cargo'?Number(input.shipment_id??old?.shipment_id):null;
   must(shipment_id===null||Number.isSafeInteger(shipment_id)&&shipment_id>0,'INVALID_CARGO');
   const cargo=await shipment(shipment_id);if(shipment_id)must(cargo&&!cargo.deleted_at&&!cargo.deletion_requested_at,'INVALID_CARGO');
   const receiver=cargo??resolved?.rows[0],ref=resolved?.statement;
   return {shipment_id,link_scope:scope,
    link_route:ref?.route??null,link_year:ref?.shipment_year??null,link_voyage:ref?.voyage??null,link_receipt_number:ref?.receipt_number??null,
    statement_route:ref?.route??null,statement_year:ref?.shipment_year??null,statement_voyage:ref?.voyage??null,statement_receipt:ref?.receipt_number??null,
    reference_type:reference?.reference_type??null,reference_number:reference?.reference_number??null,
    delivery_kind:input.delivery_kind,service_kind:reference?.reference_type==='ecommerce'?'ecommerce':input.service_kind,
    receiver_name:text(receiver?.consignee_name??input.receiver_name,160),receiver_phone:text(receiver?.consignee_phone??input.receiver_phone,40),updated_at:new Date().toISOString(),updated_by:user.id};
  }
  if(b.action==='list_groups'){
   must(operator,'FORBIDDEN',403);const page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   const groups=dbResult(await db.rpc('domestic_parcel_group_page',{p_page:page,p_size:10}));
   const rows=groups.slice(0,10).flatMap((g:any)=>g.parcels);must(rows.length<=1000,'NARROW_SEARCH');
   return json(200,{parcels:await present(rows),has_more:groups.length>10,group_count:Math.min(groups.length,10)});
  }
  if(b.action==='statement_resolve'){
   must(operator,'FORBIDDEN',403);
   const result=await resolveStatement(b);
   return json(200,{statement:result.rows.length?result.statement:null,cargo:result.rows,cargo_count:result.rows.length});
  }
  if(b.action==='statement_lookup'){
   const found=(await findCargo(b)).filter((r:any)=>operator||canSeePhoto(profile,{},r));
   if(!found.length)return json(200,{parcels:[],has_more:false,cargo_count:0});
   const refs=new Map<string,any>();
   for(const r of found)if(r.receipt_number){
    const ref={route:r.route,shipment_year:r.shipment_year,voyage:r.voyage,receipt_number:r.receipt_number};
    refs.set(JSON.stringify([r.route,r.shipment_year,receiptKey(r.voyage),receiptKey(r.receipt_number)]),ref);
   }
   must(refs.size<=1,'NARROW_SEARCH');
   const records=new Map<string,any>();
   for(const r of await allRows(()=>db.from('domestic_parcels').select('*').in('shipment_id',found.map((x:any)=>x.id)).order('created_at').order('id')))records.set(r.id,r);
   for(const ref of refs.values()){
    const rows=await allRows(()=>db.rpc('domestic_parcels_for_statement',{p_route:ref.route,p_year:ref.shipment_year,p_voyage:ref.voyage,p_receipt:ref.receipt_number}));
    for(const r of rows)if(operator||await photoAccess(r,await shipment(r.shipment_id)))records.set(r.id,r);
   }
   const rows=[...records.values()].sort((a:any,b:any)=>String(a.created_at??'').localeCompare(String(b.created_at??''))||String(a.id).localeCompare(String(b.id)));
   const page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   must(!b.grouped||rows.length<=1000,'NARROW_SEARCH');
   const parcels=await present(b.grouped?rows:rows.slice(page*20,page*20+20));
   return json(200,{parcels,has_more:!b.grouped&&rows.length>(page+1)*20,cargo_count:found.length,statement:[...refs.values()][0]??null});
  }
  if(b.action==='reference_lookup'){
   const ref=referenceInput(b),page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   const rows=await allRows(()=>db.from('domestic_parcels').select('*').eq('link_scope','reference').eq('reference_type',ref.reference_type).eq('reference_number',ref.reference_number).order('created_at').order('id'));
   const visible=rows.filter((r:any)=>operator||canSeePhoto(profile,r,null));
   must(!b.grouped||visible.length<=1000,'NARROW_SEARCH');
   const parcels=await present(b.grouped?visible:visible.slice(page*20,page*20+20));
   return json(200,{parcels,has_more:!b.grouped&&visible.length>(page+1)*20,cargo_count:0,reference:ref});
  }
  if(b.action==='lookup'){
   const number=trackingNumber(b.tracking_number);must(!b.carrier||CARRIERS[b.carrier],'INVALID_CARRIER');
   let q=db.from('domestic_parcels').select('*').eq('tracking_number',number);if(b.carrier)q=q.eq('carrier',b.carrier);
   const rows=dbResult(await q.limit(5)),found=new Map(rows.map((r:any)=>[r.id,r]));
   if(b.grouped)for(const r of rows){
    const s=await shipment(r.shipment_id);if(!await photoAccess(r,s))continue;
    const ref=rowStatement(r)??(s?.receipt_number?{route:s.route,shipment_year:s.shipment_year,voyage:s.voyage,receipt_number:s.receipt_number}:null);
    let related:any[]=[];
    if(ref)related=await allRows(()=>db.rpc('domestic_parcels_for_statement',{p_route:ref.route,p_year:ref.shipment_year,p_voyage:ref.voyage,p_receipt:ref.receipt_number}));
    else if(r.reference_number)related=await allRows(()=>db.from('domestic_parcels').select('*').eq('reference_type',r.reference_type).eq('reference_number',r.reference_number).order('created_at').order('id'));
    for(const child of related)if(await photoAccess(child,await shipment(child.shipment_id)))found.set(child.id,child);
   }
   must(found.size<=1000,'NARROW_SEARCH');return json(200,{parcels:await present([...found.values()]),has_more:false});
  }
  if(b.action==='list'){
   must(manager||partner,'FORBIDDEN',403);const page=Math.max(0,Math.min(10000,Math.floor(Number(b.page)||0)));
   let q=db.from('domestic_parcels').select('*').order('created_at',{ascending:false}).order('id').range(page*50,page*50+49);
   if(b.carrier){must(CARRIERS[b.carrier],'INVALID_CARRIER');q=q.eq('carrier',b.carrier)}
   const rows=dbResult(await q);return json(200,{parcels:await present(rows),has_more:rows.length===50});
  }
  if(b.action==='cargo_search'){
   must(operator,'FORBIDDEN',403);const q=text(b.query,50);must(q.length>=2,'SEARCH_TOO_SHORT');
   must(/^[A-Za-z0-9./_-]+$/.test(q),'INVALID_STATEMENT');
   const found=new Map<number,any>();
   for(const field of ['invoice_number','box_number']){
    const rows=dbResult(await db.from('shipments').select('id,box_number,invoice_number,receipt_number,route,shipment_year,voyage,consignee_name,consignee_phone').is('deleted_at',null).is('deletion_requested_at',null).ilike(field,'%'+q.replace(/_/g,'\\_')+'%').order('id',{ascending:false}).limit(30));
    for(const row of rows)found.set(row.id,row);
   }
   return json(200,{cargo:[...found.values()].sort((a,b)=>b.id-a.id).slice(0,30)});
  }
  must(operator,'FORBIDDEN',403);
  if(b.action==='save_batch'){
   must(Array.isArray(b.waybills)&&b.waybills.length>=1&&b.waybills.length<=50,'INVALID_BATCH');
   const entries=b.waybills.map((w:any)=>{must(w&&CARRIERS[w.carrier],'INVALID_CARRIER');return {carrier:w.carrier,tracking_number:trackingNumber(w.tracking_number)};});
   must(new Set(entries.map((w:any)=>w.carrier+':'+w.tracking_number)).size===entries.length,'DUPLICATE_TRACKING',409);
   const base=await linkValues(b),photos=await uploadPhotos(b);
   const values=entries.map((w:any)=>({...base,...w,id:crypto.randomUUID(),photo_paths:photos.paths,photo_path:photos.paths[0]??null,created_by:user.id}));
   // One PostgREST array insert is a single database transaction: all rows or none.
   const result=await db.from('domestic_parcels').insert(values).select('*');
   if(result.error){if(photos.created.length)await db.storage.from('domestic-waybills').remove(photos.created);dbResult(result);}
   return json(200,{parcels:await present(result.data),saved_count:result.data.length});
  }
  if(b.action==='save'){
   const id=b.id||crypto.randomUUID();must(uuid(id),'INVALID_ID');must(CARRIERS[b.carrier],'INVALID_CARRIER');
   const number=trackingNumber(b.tracking_number),old=b.id?dbResult(await db.from('domestic_parcels').select('*').eq('id',id).maybeSingle()):null;
   if(b.id){must(old,'NOT_FOUND',404);must(canManageParcel(profile,old),'FORBIDDEN',403);must(b.updated_at===old.updated_at,'RECORD_CHANGED',409);}
   const value:any={...(await linkValues(b,old)),id,carrier:b.carrier,tracking_number:number};
   if(old&&(old.carrier!==b.carrier||old.tracking_number!==number)){
    const events=(old.events??[]).filter((e:any)=>e.source==='staff');
    Object.assign(value,{events,status:events[0]?.status??'registered',origin:'',destination:'',checked_at:null,synced_at:null,sync_state:'never',sync_error:null});
   }
   const photos=await uploadPhotos(b,photoPaths(old??{}),id);
   value.photo_paths=photos.paths;value.photo_path=photos.paths[0]??null;
   const result=old?await db.from('domestic_parcels').update(value).eq('id',id).eq('updated_at',old.updated_at).select().maybeSingle():await db.from('domestic_parcels').insert({...value,created_by:user.id}).select().single();
   if(result.error||!result.data){if(photos.created.length)await db.storage.from('domestic-waybills').remove(photos.created);if(!result.error)throw new ApiError(409,'RECORD_CHANGED');dbResult(result);}
   return json(200,{parcel:(await present([result.data]))[0]});
  }
  if(b.action==='add_event'){
   must(uuid(b.id),'INVALID_ID');must(STATUSES.includes(b.status),'INVALID_STATUS');
   const at=laoTimestamp(b.occurred_at);must(at&&new Date(at).getTime()<=Date.now()+300000,'INVALID_DATE');
   const description=text(b.description,1200),location=text(b.location,240);must(description,'DESCRIPTION_REQUIRED');
   const old=dbResult(await db.from('domestic_parcels').select('*').eq('id',b.id).maybeSingle());must(old,'NOT_FOUND',404);must(canManageParcel(profile,old),'FORBIDDEN',403);must(old.updated_at===b.updated_at,'RECORD_CHANGED',409);
   const event={key:'manual:'+crypto.randomUUID(),occurred_at:at,location,description,status:b.status,source:'staff'};
   const events=mergeEvents(old.events,[event]);const result=dbResult(await db.from('domestic_parcels').update({events,status:events[0].status,updated_at:new Date().toISOString(),updated_by:user.id}).eq('id',b.id).eq('updated_at',old.updated_at).select().maybeSingle());must(result,'RECORD_CHANGED',409);
   return json(200,{parcel:await serialize(result,true)});
  }
  return json(400,{error:'INVALID_ACTION'});
 }catch(e){const code=(e as Error).message;if(e instanceof ApiError)return json(e.status,{error:code});if(code==='FILE_TOO_LARGE')return json(413,{error:code});if(['INVALID_TRACKING','INVALID_STATEMENT','INVALID_REFERENCE','INVALID_IMAGE','TOO_MANY_PHOTOS'].includes(code))return json(400,{error:code});console.error('domestic-tracking request failed:',e instanceof Error?e.name:'error');return json(500,{error:'REQUEST_FAILED'})}
});

