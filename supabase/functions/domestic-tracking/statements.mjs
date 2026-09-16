// Statement identity uses receipt_number, never the inbound invoice_number.
export function receiptKey(value) {
  const v=String(value??'').trim().toUpperCase().replace(/\s/g,'');
  const m=/^([A-Z]*)(\d+)$/.exec(v);
  if(!m)return v;
  return m[1]+m[2].replace(/^0+(?=\d)/,'');
}
export function statementInput(body) {
  body=body??{};
  const route=String(body.route??'').trim(),voyage=String(body.voyage??'').trim();
  const receipt_number=String(body.receipt_number??'').trim(),shipment_year=Number(body.shipment_year);
  if(!route||route.length>160||!voyage||voyage.length>40||!receipt_number||receipt_number.length>80||!/[0-9]/.test(receipt_number)||!Number.isInteger(shipment_year)||shipment_year<1900||shipment_year>2200)throw new Error('INVALID_STATEMENT');
  return {route,shipment_year,voyage,receipt_number};
}
export function carrierRecommendation(value) {
  const n=String(value??'').replace(/\s/g,'').toUpperCase();
  // Hints only. Numeric formats overlap; no carrier is selected automatically.
  if(/^VTE\d{8,16}$/.test(n))return ['HAL'];
  if(/^\d{13}$/.test(n))return ['ANS'];
  return [];
}
export async function mapLimited(rows,fn,limit=4) {
  const out=new Array(rows.length);let next=0;
  await Promise.all(Array.from({length:Math.min(limit,rows.length)},async()=>{while(next<rows.length){const i=next++;out[i]=await fn(rows[i]);}}));
  return out;
}
