import {test} from 'node:test';
import assert from 'node:assert/strict';
import {documentVatContext,documentVatFormula} from './document-vat.mjs';
test('zero-rated invoice takes precedence over the tax-invoice substring',()=>{
 for(const route of ['kr_la_sea','kr_la_air']){
  for(const note of ['영세율 세금 계산서','영 세 율\n세금\t계산서']){
   const result=documentVatContext(route,note);
   assert.equal(result.rate,0);assert.equal(result.taxInvoice,true);assert.equal(result.zeroRated,true);
  }
  assert.equal(documentVatContext(route,'세금 계산서').rate,.1);
  assert.equal(documentVatContext(route,'').rate,0);
 }
 assert.equal(documentVatContext('th_la_land','세금 계산서').rate,0);
});
test('Excel VAT formula normalizes whitespace and checks zero rating',()=>{
 const formula=documentVatFormula('$A$18');
 assert.match(formula,/SEARCH\("영세율"/);assert.match(formula,/,0,10%\)/);
 assert.throws(()=>documentVatFormula('A18+1'));
});
