const enc=new TextEncoder();
// Decode and encode bounded chunks. No full UTF-16 worksheet copy is retained.
export function* worksheetTextChunks(source){
 if(typeof source==='string'){for(let i=0;i<source.length;i+=65536)yield source.slice(i,i+65536);return;}
 const dec=new TextDecoder();
 for(let i=0;i<source.length;i+=65536)yield dec.decode(source.subarray(i,i+65536),{stream:i+65536<source.length});
}
export function worksheetMetadata(source){
 let tail='',ab=0,n=0,maxSharedId=-1,hasAK6=false;
 for(const part of worksheetTextChunks(source)){
  const text=tail+part;
  for(const m of text.matchAll(/<c\b[^>]*r="(AB|N)(\d+)"/g)){
   const row=Number(m[2]);if(m[1]==='AB')ab=Math.max(ab,row);else if(row<=1005)n=Math.max(n,row);
  }
  for(const m of text.matchAll(/<f\b[^>]*\bsi="(\d+)"/g))maxSharedId=Math.max(maxSharedId,Number(m[1]));
  hasAK6 ||= /<c\b[^>]*r="AK6"/.test(text);
  tail=text.slice(-256);
 }return {hasRanking:ab>0,last:Math.max(6,ab||n),hasAK6,maxSharedId};
}
export function worksheetIdentityRange(source){const {hasRanking,last}=worksheetMetadata(source);return {hasRanking,last};}
export function* worksheetRowEntries(source){
 let buffer='';
 for(const part of worksheetTextChunks(source)){
  buffer+=part;
  for(;;){
   const start=/<row\b[^>]*\br="(\d+)"[^>]*>/.exec(buffer);if(!start)break;
   const end=buffer.indexOf('</row>',start.index+start[0].length);if(end<0)break;
   yield [buffer.slice(start.index,end+6),start[1]];
   buffer=buffer.slice(end+6);
  }
 }
}
export function rewriteWorksheetRows(source,transform,transformHeader){
 let output=new Uint8Array(Math.max(1024,Math.ceil(source.length*1.2)));
 let total=0,buffer='',first=true;
 const add=s=>{
  let consumed=0;
  while(consumed<s.length){
   const result=enc.encodeInto(s.slice(consumed),output.subarray(total));
   consumed+=result.read;total+=result.written;
   if(consumed<s.length){const next=new Uint8Array(Math.ceil(output.length*1.5));next.set(output.subarray(0,total));output=next;}
  }
 };
 for(const part of worksheetTextChunks(source)){
  buffer+=part;
  for(;;){
   const start=/<row\b[^>]*\br="(\d+)"[^>]*>/.exec(buffer);if(!start)break;
   const end=buffer.indexOf('</row>',start.index+start[0].length);if(end<0)break;
   const prefix=buffer.slice(0,start.index);
   add(first&&transformHeader?transformHeader(prefix):prefix);first=false;
   add(transform(buffer.slice(start.index,end+6),start[1]));buffer=buffer.slice(end+6);
  }
 }
 add(first&&transformHeader?transformHeader(buffer):buffer);
 return output.subarray(0,total);
}
