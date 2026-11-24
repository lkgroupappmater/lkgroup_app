import {test} from 'node:test';
import assert from 'node:assert/strict';
import {discountMatchRank,discountPhoneTokens} from './discount-matching.mjs';

const rule={customer_name:'Member A/Member B/Member C(Member D)',company_name:'Example Association',phone_display:'020 1111 0001 / 020 1111 0002 / 020 1111 0003 / 020 1111 0004 / 020 1111 0005 / 020 1111 0006'};
test('every registered member matches every phone in the same discount row',()=>{
 for(const name of ['Member A','Member B','Member C','Member D'])
  for(const phone of discountPhoneTokens(rule.phone_display)){
   assert.equal(discountMatchRank(name,phone,rule),0);
   assert.equal(discountMatchRank('Receiver / '+name,phone,rule),0);
   assert.equal(discountMatchRank(name+' / Receiver',phone,rule),0);
  }
});
test('list permutation and counts do not change discounts',()=>{
 const reversed={...rule,customer_name:'Member D/Member C/Member B/Member A',phone_display:discountPhoneTokens(rule.phone_display).reverse().join(' / ')};
 assert.equal(discountMatchRank('Other / Member B / Receiver','02099990001 / 02011110005 / 02099990002',reversed),0);
 assert.equal(discountMatchRank('Example Association','+856 20 1111 0006',reversed),1);
});
test('an exact registered name and a complete registered phone are both required',()=>{
 for(const [name,phone] of [['Member A','02099990001'],['Unknown','02011110001'],['Member A','11110001'],['Member Ax','02011110001'],['Member A',''],['','02011110001'],['Member A','invalid']])assert.equal(discountMatchRank(name,phone,rule),9999);
 const other={customer_name:'Different Member',phone_display:'020 9999 0001'};
 assert.equal(discountMatchRank('Member A','02099990001',other),9999);
 assert.equal(discountMatchRank('Different Member','02011110001',rule),9999);
});

test('receipt suffix digits do not require separate discount aliases',()=>{
 for(const suffix of ['2','3','25','001','12345678901234567890'])assert.equal(discountMatchRank('Receiver/Member A'+suffix,'02011110006',rule),0);
 const numbered={customer_name:'A1B',phone_display:'02011110001'};
 assert.equal(discountMatchRank('A1B25','02011110001',numbered),0);
 assert.equal(discountMatchRank('AB25','02011110001',numbered),9999);
 assert.equal(discountMatchRank('Member A2','02099990001',rule),9999);
 assert.equal(discountMatchRank('Member A2Extra','02011110001',rule),9999);
});
