// Mirrors public.document_vat_context; Excel retains the editable formula.
export function documentVatContext(routeKey, remark) {
  const text=String(remark??'').replace(/[\s\u00a0\u3000]+/g,'');
  const taxInvoice=text.includes('세금계산서');
  const applicable=['kr_la_sea','kr_la_air'].includes(routeKey)&&taxInvoice;
  return {taxInvoice,applicable,zeroRated:taxInvoice&&text.includes('영세율'),
    rate:applicable&&!text.includes('영세율')?.1:0};
}

export function documentVatFormula(remarkRef) {
  if(!/^\$?[A-Z]{1,3}\$?\d+$/.test(remarkRef))throw Error('Invalid Remark reference');
  let text=remarkRef;
  for(const space of ['" "','CHAR(9)','CHAR(10)','CHAR(13)','CHAR(160)','"　"'])
    text=`SUBSTITUTE(${text},${space},"")`;
  return `IF(ISNUMBER(SEARCH("세금계산서",${text})),IF(ISNUMBER(SEARCH("영세율",${text})),0,10%)," ")`;
}
