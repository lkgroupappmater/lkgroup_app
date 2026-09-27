// Formatting only: registry numbers, aliases and source links remain numeric.
export function normalizeCustomerCode(value) {
 const match=String(value??'').trim().match(/^(?:(?:ID|LK)\s*[:#-]?\s*)?(\d{1,9})$/i);
 return match&&Number(match[1])>0?String(Number(match[1])).padStart(3,'0'):null;
}
export function displayCustomerCode(value) {
 const code=normalizeCustomerCode(value);
 return code?'LK '+code.padStart(4,'0'):value;
}
export function customerCodeJson(key,value) {
 return key==='customer_code'&&value!=null?displayCustomerCode(value):value;
}
