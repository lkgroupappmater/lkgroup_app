// A cell style is not the whole font: Excel stores mixed-language fonts, sizes
// and colours inside individual rich-text runs. Keep those runs when DB values
// or the voyage number are refreshed.
const enc=new TextEncoder(),dec=new TextDecoder();
const decode=s=>s.replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi,e=>{
 const named={'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"};
 return named[e]??String.fromCodePoint(parseInt(e.slice(e[2]?.toLowerCase()==='x'?3:2,-1),e[2]?.toLowerCase()==='x'?16:10));
});
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
export const richTextValue=xml=>[...xml.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m=>decode(m[1])).join('');
export function sharedRichText(files){
 const rich=new Map();let i=0;
 for(const m of dec.decode(files['xl/sharedStrings.xml']||new Uint8Array()).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)){
  if(/<r\b/.test(m[1]))rich.set(i,m[1]);i++;
 }
 return rich;
}
export function richTextBody(cell,shared=new Map()){
 if(/\bt="s"/.test(cell.slice(0,cell.indexOf('>')+1)))return shared.get(Number(cell.match(/<v>(\d+)<\/v>/)?.[1]));
 const body=cell.match(/<is\b[^>]*>([\s\S]*?)<\/is>/)?.[1];
 return body&&/<r\b/.test(body)?body:undefined;
}
export function inlineRichTextStrings(files,paths){
 const rich=sharedRichText(files);if(!rich.size)return;
 for(const path of Object.keys(files)){
  if(!/^xl\/worksheets\/[^/]+\.xml$/.test(path))continue;
  if(paths&&!paths.has(path))continue;
  const xml=dec.decode(files[path]);let changed=false;
  if(!xml.includes('t="s"'))continue;
  const next=xml.replace(/<c\b[^>]*\bt="s"[^>]*>[\s\S]*?<\/c>/g,cell=>{
   const body=richTextBody(cell,rich);if(body===undefined)return cell;
   changed=true;return cell.replace(/\bt="s"/,'t="inlineStr"').replace(/<v>\d+<\/v>/,()=>'<is>'+body+'</is>');
  });
  if(changed)files[path]=enc.encode(next);
 }
}
export function preserveCellText(cell,value){
 if(!cell||!/<is\b/.test(cell)||/<f\b/.test(cell))return null;
 const old=richTextValue(cell),next=String(value??'');
 if(old===next)return cell;
 const body=richTextBody(cell);if(body===undefined||!next)return null;
 const runs=[...body.matchAll(/<r\b[^>]*>([\s\S]*?)<\/r>/g)].map(m=>({text:richTextValue(m[1]),format:m[1].match(/<rPr\b[^>]*?(?:\/>|>[\s\S]*?<\/rPr>)/)?.[0]||''}));
 const a=Array.from(old),b=Array.from(next);let prefix=0,suffix=0;
 while(prefix<Math.min(a.length,b.length)&&a[prefix]===b[prefix])prefix++;
 while(suffix<Math.min(a.length-prefix,b.length-prefix)&&a[a.length-1-suffix]===b[b.length-1-suffix])suffix++;
 const styles=runs.flatMap(r=>Array.from(r.text,()=>r.format));
 const insertedStyle=styles[Math.min(prefix,Math.max(0,styles.length-1))]||'';
 // Preserve unchanged text inside a changed span too (for example a new
 // voyage number AND an edited suffix). Prefix/suffix alone would repaint Lao.
 const matched=new Map();
 for(let i=0;i<prefix;i++)matched.set(i,i);
 for(let i=0;i<suffix;i++)matched.set(b.length-1-i,a.length-1-i);
 const left=a.length-prefix-suffix,right=b.length-prefix-suffix;
 if(left*right<=1000000){
  const width=right+1,table=new Uint32Array((left+1)*width);
  for(let i=left-1;i>=0;i--)for(let j=right-1;j>=0;j--)table[i*width+j]=a[prefix+i]===b[prefix+j]?1+table[(i+1)*width+j+1]:Math.max(table[(i+1)*width+j],table[i*width+j+1]);
  let i=0,j=0;while(i<left&&j<right){if(a[prefix+i]===b[prefix+j]){matched.set(prefix+j,prefix+i);i++;j++;}else if(table[(i+1)*width+j]>=table[i*width+j+1])i++;else j++;}
 }
 const output=[];
 let previous=insertedStyle;
 for(let i=0;i<b.length;i++){
  const format=matched.has(i)?styles[matched.get(i)]:previous;
  previous=format;
  if(output.at(-1)?.format===format)output.at(-1).text+=b[i];else output.push({format,text:b[i]});
 }
 const phonetic=body.match(/<phoneticPr\b[^>]*\/>/)?.[0]||'';
 const replacement='<is>'+output.map(r=>`<r>${r.format}<t xml:space="preserve">${escape(r.text)}</t></r>`).join('')+phonetic+'</is>';
 return cell.replace(/<is\b[^>]*>[\s\S]*?<\/is>/,()=>replacement);
}
