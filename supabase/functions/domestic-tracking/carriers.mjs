// Public tracking contracts verified against the carrier websites, 2026-09-16.
// Do not emulate CAPTCHA, use customer sessions, or infer undocumented private APIs.
export const CARRIERS = {
  HAL: {name:'HAL · Houng Aloun', mode:'automatic', url:'https://halexpress.la/parcel'},
  ANS: {name:'ANS · Anousith', mode:'connection_required', url:'https://app.anousith.express/login'},
  MIXAY: {name:'Mixay', mode:'planned', url:null},
  JT: {name:'J&T Express', mode:'verification_required', url:'https://www.jtexpress.la/'},
  LAOPOST: {name:'Lao Post', mode:'verification_required', url:'https://www.laopost.com.la/online-service/tracking'},
};
export const STATUSES = ['registered','accepted','in_transit','ready_for_pickup','out_for_delivery','delivered','returned','exception','unknown'];
export function trackingNumber(value) {
  const v=String(value??'').trim().toUpperCase().replace(/\s/g,'');
  if(!/^[A-Z0-9][A-Z0-9-]{5,39}$/.test(v)) throw new Error('INVALID_TRACKING');
  return v;
}
export function carrierUrl(code, number) {
  const n=encodeURIComponent(trackingNumber(number));
  if(code==='HAL')return `https://halexpress.la/parcel?search=${n}`;
  if(code==='ANS')return `https://app.anousith.express/landing/search_tracking/search_item?_bill_detail=${n}&n_home=2`;
  return CARRIERS[code]?.url??null;
}
export function laoTimestamp(value) {
  const s=String(value??'').trim(); if(!s)return null;
  const zoned=/Z$|[+-]\d\d:\d\d$/.test(s)?s:s.replace(' ','T')+'+07:00';
  const t=new Date(zoned);return Number.isFinite(t.getTime())?t.toISOString():null;
}
const short=(s,n=1200)=>String(s??'').slice(0,n);
function event(id,at,location,description,status,source='carrier') {
  const occurred_at=laoTimestamp(at); if(!occurred_at)return null;
  return {key:String(id),occurred_at,location:short(location,240),description:short(description),status:STATUSES.includes(status)?status:'unknown',source};
}
export function mergeEvents(oldEvents=[],newEvents=[]) {
  const m=new Map();for(const e of [...oldEvents,...newEvents])if(e&&e.key&&laoTimestamp(e.occurred_at))m.set(e.key,e);
  return [...m.values()].sort((a,b)=>b.occurred_at.localeCompare(a.occurred_at)||a.key.localeCompare(b.key)).slice(0,500);
}
export function normalizeHal(data,number) {
  if(!data?.shipment_info||trackingNumber(data.shipment_info.bill_number)!==number)throw new Error('NOT_FOUND');
  if(!Array.isArray(data.tracking_events))throw new Error('CARRIER_FORMAT_CHANGED');
  const codes={1:'registered',2:'accepted',3:'in_transit',4:'in_transit',5:'ready_for_pickup',6:'delivered'};
  const events=data.tracking_events.map(e=>event(`hal:${e.date}:${e.delivery_state}:${e.place}:${e.message}`,e.date,e.place,e.message,codes[e.delivery_state]??'unknown')).filter(Boolean);
  if(!events.length)throw new Error('NO_EVENTS');
  const sorted=mergeEvents([],events),s=data.shipment_info;
  return {events:sorted,status:s.has_been_returned?'returned':sorted[0].status,origin:short(s.from_branch,240),destination:short(s.destination_branch,240)};
}
async function jsonFetch(fetcher,url,body) {
  const response=await fetcher(url,{method:body?'POST':'GET',headers:{Accept:'application/json',...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(15000),redirect:'error'});
  if(response.status===401||response.status===403)throw new Error('AUTH_REQUIRED');
  if(response.status===404)throw new Error('NOT_FOUND');
  if(response.status===429)throw new Error('RATE_LIMITED');
  if(!response.ok)throw new Error('CARRIER_UNAVAILABLE');
  const text=await response.text();if(text.length>2000000)throw new Error('CARRIER_FORMAT_CHANGED');
  let data;try{data=JSON.parse(text)}catch{throw new Error('CARRIER_FORMAT_CHANGED')}
  if(data.errors?.length)throw new Error('CARRIER_UNAVAILABLE');return data;
}
export async function fetchTracking(code,number,fetcher=fetch) {
  const n=trackingNumber(number);
  if(code==='HAL')return normalizeHal(await jsonFetch(fetcher,`https://hal.hal-logistics.la/api/v1/orders/tracking/${encodeURIComponent(n)}`),n);
  // ANS server requests redirect to an unrelated domain; do not follow them.
  if(code==='ANS')throw new Error('CONNECTION_REQUIRED');
  throw new Error(CARRIERS[code]?.mode==='planned'?'PLANNED':'VERIFICATION_REQUIRED');
}
export function canSeePhoto(profile,parcel,shipment) {
  if(['admin','staff','partner'].includes(profile.role))return true;
  if(shipment?.customer_id===profile.id)return true;
  const name=s=>String(s??'').replace(/\s/g,'').toLowerCase();
  const phone=s=>String(s??'').replace(/\D/g,'').slice(-8);
  const n=name(profile.name),p=phone(profile.phone);
  return !!n&&p.length===8&&n===name(shipment?.consignee_name??parcel.receiver_name)&&p===phone(shipment?.consignee_phone??parcel.receiver_phone);
}
