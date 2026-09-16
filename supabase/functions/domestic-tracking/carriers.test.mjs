import {test} from 'node:test';
import assert from 'node:assert/strict';
import {trackingNumber, carrierUrl, laoTimestamp, normalizeHal, mergeEvents, fetchTracking, canSeePhoto} from './carriers.mjs';

const number='VTE12345678901';
const fixture={shipment_info:{bill_number:number,from_branch:'Origin',destination_branch:'Destination',sender_phone:'PRIVATE'},tracking_events:[
 {date:'2026-09-05 08:45:16',place:'Destination',message:'Available for collection',delivery_state:5},
 {date:'2026-09-08 11:18:39',place:'Destination',message:'Received by customer',delivery_state:6},
]};
test('full tracking identifiers normalize safely without allowing path or query injection',()=>{
 assert.equal(trackingNumber(' vte 12345678901 '),number);
 for(const value of ['123','../../private','123456?x=1','<script>','A'.repeat(41)])assert.throws(()=>trackingNumber(value));
 assert.equal(new URL(carrierUrl('HAL',number)).searchParams.get('search'),number);
 assert.equal(carrierUrl('MIXAY',number),null);
});
test('HAL distinguishes collection from completion, sorts events, strips contact fields',()=>{
 const r=normalizeHal(fixture,number);assert.equal(r.status,'delivered');
 assert.equal(r.events[1].status,'ready_for_pickup');
 assert.equal(r.events[0].occurred_at,'2026-09-08T04:18:39.000Z');
 assert.ok(!JSON.stringify(r).includes('PRIVATE'));
 assert.throws(()=>normalizeHal(fixture,'OTHER123'),/NOT_FOUND/);
 assert.throws(()=>normalizeHal({...fixture,tracking_events:[]},number),/NO_EVENTS/);
});
test('repeated refreshes deduplicate carrier events and preserve staff records',()=>{
 const r=normalizeHal(fixture,number),manual={key:'manual:1',occurred_at:'2026-09-09T00:00:00.000Z',status:'exception',source:'staff'};
 const events=mergeEvents([...r.events,manual],r.events);
 assert.equal(events.length,3);assert.equal(events[0].key,'manual:1');
 assert.equal(laoTimestamp('2026-09-03 15:49:00'),'2026-09-03T08:49:00.000Z');
 assert.equal(laoTimestamp('bad date'),null);
});
test('photos require operational role, linked customer, or both recipient name and phone',()=>{
 const parcel={receiver_name:'Kim Lee',receiver_phone:'+85620 12345678'};
 const profile={id:'customer',role:'member',name:'Kim Lee',phone:'2012345678'};
 assert.equal(canSeePhoto(profile,parcel,null),true);
 assert.equal(canSeePhoto({...profile,name:'Other'},parcel,null),false);
 assert.equal(canSeePhoto({...profile,phone:'87654321'},parcel,null),false);
 assert.equal(canSeePhoto({...profile,name:'',phone:''},parcel,null),false);
 assert.equal(canSeePhoto({...profile,name:'Other'},parcel,{customer_id:'customer'}),true);
 for(const role of ['admin','staff','partner'])assert.equal(canSeePhoto({...profile,role},parcel,null),true);
});
test('only verified HAL adapter calls network; redirect/error responses never become fake events',async()=>{
 let calls=0;
 const fetcher=async(url,options)=>{calls++;assert.equal(new URL(url).hostname,'hal.hal-logistics.la');assert.equal(options.redirect,'error');return Response.json(fixture)};
 assert.equal((await fetchTracking('HAL',number,fetcher)).status,'delivered');assert.equal(calls,1);
 for(const [code,error] of [['ANS','CONNECTION_REQUIRED'],['JT','VERIFICATION_REQUIRED'],['LAOPOST','VERIFICATION_REQUIRED'],['MIXAY','PLANNED']])await assert.rejects(fetchTracking(code,number,fetcher),new RegExp(error));
 assert.equal(calls,1);
 await assert.rejects(fetchTracking('HAL',number,async()=>new Response('redirect',{status:302})),/CARRIER_UNAVAILABLE/);
 await assert.rejects(fetchTracking('HAL',number,async()=>new Response('captcha',{status:403})),/AUTH_REQUIRED/);
});
