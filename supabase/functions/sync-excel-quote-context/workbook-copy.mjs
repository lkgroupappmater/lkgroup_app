// Deliberately extract only the common footer of a statement form.
// Customer rows, addresses, phone numbers and statement Remarks never leave it.
const decode=b=>new TextDecoder().decode(b||new Uint8Array());
const entities=s=>String(s).replace(/&#(x[0-9a-f]+|\d+);/gi,(_,n)=>String.fromCodePoint(n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n))).replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&amp;/g,'&');
const texts=s=>[...s.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m=>entities(m[1])).join('');
export function workbookIndex(files){
 const rels=new Map([...decode(files['xl/_rels/workbook.xml.rels']).matchAll(/<Relationship\b[^>]*\bId="([^"]+)"[^>]*\bTarget="([^"]+)"[^>]*\/?\s*>/g)].map(m=>[m[1],m[2].startsWith('/')?m[2].slice(1):'xl/'+m[2].replace(/^\.\//,'')]));
 return [...decode(files['xl/workbook.xml']).matchAll(/<sheet\b[^>]*\bname="([^"]+)"[^>]*\br:id="([^"]+)"[^>]*\/?\s*>/g)].map(m=>({name:entities(m[1]),path:rels.get(m[2])}));
}
export function commonFooter(xml,stringsXml=''){
 const strings=[...stringsXml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m=>texts(m[1]));
 const cells=[];
 for(const m of xml.matchAll(/<c\b([^>]*\br="([A-Z]+)(\d+)"[^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)){
  const body=m[4]||'',type=m[1].match(/\bt="([^"]+)"/)?.[1],value=body.match(/<v\b[^>]*>([\s\S]*?)<\/v>/)?.[1]||'';
  const text=type==='s'?(strings[Number(value)]||''):type==='inlineStr'?texts(body):entities(value);
  cells.push({col:m[2],row:Number(m[3]),text:text.trim(),formula:/<f\b/.test(body)});
 }
 const remark=cells.find(c=>c.col==='A'&&/remark|비\s*고/i.test(c.text));
 if(!remark||!cells.some(c=>/합\s*계|총\s*운임|total/i.test(c.text)))return null;
 const lines=cells.filter(c=>c.col==='A'&&c.row>remark.row+1&&!c.formula&&/^[*＊※•]/.test(c.text)).map(c=>c.text);
 // Missing or unfamiliar layout must retain the last verified common copy.
 return lines.length?[...new Set(lines)]:null;
}
export function extractWorkbookCopy(bytes,unzip){
 const meta=unzip(bytes,{filter:e=>['xl/workbook.xml','xl/_rels/workbook.xml.rels','xl/sharedStrings.xml'].includes(e.name)});
 const candidates=workbookIndex(meta).filter(s=>s.path&&/^(LK[A-Z]*\s*(?:XX|\d+)|이름\(|.*명세서|.*가견적)/i.test(s.name));
 // Empty/master forms before issued customer forms.
 candidates.sort((a,b)=>Number(!/XX|이름\(/i.test(a.name))-Number(!/XX|이름\(/i.test(b.name)));
 for(const sheet of candidates){
  const files=unzip(bytes,{filter:e=>e.name===sheet.path});
  const footer=commonFooter(decode(files[sheet.path]),decode(meta['xl/sharedStrings.xml']));
  if(footer)return {footer_lines:footer};
 }
 throw Error('공통 안내 문구를 확인할 수 없습니다. 기존 가견적 문구를 유지합니다.');
}
