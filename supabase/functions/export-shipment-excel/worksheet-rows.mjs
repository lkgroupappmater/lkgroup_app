const enc=new TextEncoder(),dec=new TextDecoder();
// Encode each rewritten row immediately. A full-sheet String.replace retains
// all match arguments and large UTF-16 replacements until the last row.
export function rewriteWorksheetRows(source,transform){
 const xml=typeof source==='string'?source:dec.decode(source);
 let output=new Uint8Array(Math.max(1024,typeof source==='string'?Math.ceil(source.length*1.2):source.length));
 let cursor=0,total=0;
 const add=s=>{
  let consumed=0;
  while(consumed<s.length){
   const result=enc.encodeInto(s.slice(consumed),output.subarray(total));
   consumed+=result.read;total+=result.written;
   if(consumed<s.length){const next=new Uint8Array(Math.ceil(output.length*1.5));next.set(output.subarray(0,total));output=next;}
  }
 };
 for(const m of xml.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)){
  add(xml.slice(cursor,m.index));add(transform(m[0],m[1]));cursor=m.index+m[0].length;
 }
 add(xml.slice(cursor));
 return output.subarray(0,total);
}
