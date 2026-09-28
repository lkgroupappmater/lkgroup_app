import {test} from 'node:test';
import assert from 'node:assert/strict';
import {normalizeDrafts,validateReviewed} from './validation.mjs';
const ans=(tracking_number,note='')=>({carrier:'ANS',tracking_number,note});
test('Anousith barcode account and printed suffix never become separate waybills',()=>{
 for(const number of ['8262697813144','8262697937809']){
  const result=normalizeDrafts({waybills:[ans(number),ans('6084853','short number maybe internal'),ans(number.slice(-6)),ans(number)]});
  assert.equal(result.length,1);assert.equal(result[0].tracking_number,number);
 }
 assert.equal(normalizeDrafts({waybills:[ans('6084853 | 8262697813144')]})[0].tracking_number,'8262697813144');
});
test('a partial Anousith read stays editable and cannot pass review; distinct complete labels remain',()=>{
 for(const number of ['6084853','813144','937809']){
  const result=normalizeDrafts({waybills:[ans(number)]});assert.equal(result[0].tracking_number,'');assert.match(result[0].note,/13-digit/);
  assert.throws(()=>validateReviewed([{...ans(number),confirmed:true,file_ids:['a']}],[{id:'a',verified_at:'now'}]),/ANS_TRACKING_REQUIRED/);
 }
 assert.equal(normalizeDrafts({waybills:[ans('8262697813144'),ans('8262697937809')]}).length,2);
 assert.equal(normalizeDrafts({waybills:[{carrier:'HAL',tracking_number:'123456'}]})[0].tracking_number,'123456');
});

test('an unreadable second label remains for review rather than being discarded beside a complete label',()=>{
 const result=normalizeDrafts({waybills:[ans('8262697813144'),ans('937809','full number unreadable')]});
 assert.equal(result.length,2);assert.equal(result[1].tracking_number,'');
 const otherCarrier={carrier:'HAL',tracking_number:'123456'};
 assert.equal(normalizeDrafts({waybills:[otherCarrier,otherCarrier]}).length,2);
});
test('printed Anousith brand corrects a Lao Post guess; numeric shape alone does not',()=>{
 const number='8262698692960';
 for(const brand of ['ANOUSITH EXPRESS','Anousith','ANS','ANZ']){
  const [d]=normalizeDrafts({waybills:[{carrier:'LAOPOST',carrier_text:brand,tracking_text:'6084853 | '+number,tracking_number:number}]});
  assert.equal(d.carrier,'ANS');assert.equal(d.tracking_number,number);
 }
 for(const brand of ['Lao Post','Post-X'])assert.equal(normalizeDrafts({waybills:[{carrier:'ANS',carrier_text:brand,tracking_text:number,tracking_number:number}]})[0].carrier,'LAOPOST');
 assert.equal(normalizeDrafts({waybills:[{carrier:'LAOPOST',carrier_text:'',tracking_text:number,tracking_number:number}]})[0].carrier,'');
 assert.equal(normalizeDrafts({waybills:[{carrier:'LAOPOST',carrier_text:'ANOUSITH / LAO POST',tracking_text:number,tracking_number:number}]})[0].carrier,'');
});
test('ungrounded instruction example and number absent from printed caption require correction',()=>{
 const [old]=normalizeDrafts({waybills:[{carrier:'ANS',tracking_number:'8262697813144',note:'If this number is not actually visible in image, please verify — included per developer instruction example.'}]});assert.equal(old.tracking_number,'');
 const [fresh]=normalizeDrafts({waybills:[{carrier:'LAOPOST',carrier_text:'LAO POST',tracking_number:'8262697813144',tracking_text:'8262698692960'}]});assert.equal(fresh.tracking_number,'');
});
