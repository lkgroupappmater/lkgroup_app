// Keep shared-formula groups valid when an editable cell replaces their master.
// OOXML CellFormula: https://learn.microsoft.com/dotnet/api/documentformat.openxml.spreadsheet.cellformula
const enc=new TextEncoder(),dec=new TextDecoder();
const decode=s=>s.replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&');
const encode=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
const cells=xml=>xml.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g);
const attrPatterns=new Map();
const attr=(s,n)=>{let re=attrPatterns.get(n);if(!re){re=new RegExp(`\\b${n}="([^"]*)"`);attrPatterns.set(n,re);}return s.match(re)?.[1];};
const colNumber=s=>[...s].reduce((n,c)=>n*26+c.charCodeAt(0)-64,0);
const colName=n=>{let s='';for(;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;};
const point=s=>{const m=/^\$?([A-Z]+)\$?(\d+)$/.exec(s||'');return m?{c:colNumber(m[1]),r:Number(m[2])}:null;};
function groupMap(xml){
 const groups=new Map();
 for(const f of xml.matchAll(/<f\b(?=[^>]*\bt="shared")[^>]*?(?:\/>|>([\s\S]*?)<\/f>)/g)){
  const at=xml.lastIndexOf('<c ',f.index),tag=xml.slice(at,xml.indexOf('>',at)+1);
  const si=attr(f[0],'si');if(!groups.has(si))groups.set(si,[]);
  groups.get(si).push({cell:attr(tag,'r'),si,ref:attr(f[0],'ref'),formula:f[1]?decode(f[1]):'',tag:f[0]});
 }return groups;
}
// Tokenize quoted text, sheet names and structured/external references first.
// Copy only actual A1 references; LOG10(), names and quoted "A1" stay unchanged.
export function translateFormula(formula,from,to){
 const a=point(from),b=point(to);if(!a||!b)throw Error('Invalid formula anchor');
 const dc=b.c-a.c,dr=b.r-a.r;
 return formula.replace(/"(?:[^"]|"")*"|'(?:[^']|'')*'|\[[^\]]*\]|(?<![\p{L}\p{N}_.])\$?[A-Z]{1,3}\$?[1-9]\d*(?![\p{L}\p{N}_.]|\s*[(!])/gu,token=>{
  const m=/^(\$?)([A-Z]+)(\$?)(\d+)$/.exec(token);if(!m)return token;
  const c=colNumber(m[2]),r=Number(m[4]);if(c>16384||r>1048576)return token;
  const nc=c+(m[1]?0:dc),nr=r+(m[3]?0:dr);
  if(nc<1||nc>16384||nr<1||nr>1048576)throw Error('Formula copy exceeds worksheet bounds');
  return m[1]+colName(nc)+m[3]+nr;
 });
}
export function captureSharedFormulaMasters(files){
 const result=new Map();for(const [path,data] of Object.entries(files)){
  if(!/^xl\/worksheets\/[^/]+\.xml$/.test(path))continue;
  const xml=dec.decode(data),masters=new Map();
  for(const f of xml.matchAll(/<f\b(?=[^>]*\bt="shared")(?=[^>]*\bref=")[^>]*>([^<]+)<\/f>/g)){
   const at=xml.lastIndexOf('<c ',f.index),tag=xml.slice(at,xml.indexOf('>',at)+1),si=attr(f[0],'si');
   masters.set(si,{cell:attr(tag,'r'),si,ref:attr(f[0],'ref'),formula:decode(f[1])});
  }
  result.set(path,masters);
 }return result;
}
function replaceMasters(xml,replacements){
 return xml.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,cell=>{
  const replacement=replacements.get(attr(cell,'r'));return replacement?cell.replace(/<f\b[^>]*?(?:\/>|>[\s\S]*?<\/f>)/,()=>replacement):cell;
 });
}
function masterTag(items,source){
 const first=items[0],points=items.map(x=>point(x.cell));
 const minC=Math.min(...points.map(x=>x.c)),maxC=Math.max(...points.map(x=>x.c)),minR=Math.min(...points.map(x=>x.r)),maxR=Math.max(...points.map(x=>x.r));
 return `<f t="shared" si="${first.si}" ref="${colName(minC)}${minR}:${colName(maxC)}${maxR}">${encode(translateFormula(source.formula,source.cell,first.cell))}</f>`;
}
export function restoreSharedFormulaMasters(files,snapshot){
 let repaired=0;
 for(const [path,masters] of snapshot){
  if(!files[path])continue;const xml=dec.decode(files[path]),replacements=new Map();
  for(const [si,items] of groupMap(xml))if(!items.some(x=>x.formula)&&masters.has(si)){
   replacements.set(items[0].cell,masterTag(items,masters.get(si)));repaired++;
  }
  if(replacements.size)files[path]=enc.encode(replaceMasters(xml,replacements));
 }return repaired;
}
const selectorFormula=r=>`IF(AND(T${r}<>"",G${r}<>"",COUNTIFS($T$3:$T$800,T${r},$G$3:$G$800,"<>")=1),"사용","")`;
// Recovery for already-saved v3 files. Require the exact original selector
// formula in surviving groups on the same delivery sheet. Never guess a lost
// price, receipt or arbitrary formula and never replace it with a cached value.
export function recoverDeliverySelectorMasters(files,sheetPath){
 let repaired=0;
 for(const name of ['지방배송','시내배송']){
  const path=sheetPath(files,name);if(!path||!files[path])continue;
  const xml=dec.decode(files[path]),groups=groupMap(xml),replacements=new Map();
  const witnesses=[...groups.values()].flat().filter(x=>/^H\d+$/.test(x.cell)&&x.formula);
  if(!witnesses.length||witnesses.some(x=>x.formula!==selectorFormula(point(x.cell).r)))continue;
  for(const items of groups.values()){
   if(items.some(x=>x.formula)||items.some(x=>!/^H\d+$/.test(x.cell)||point(x.cell).r<3||point(x.cell).r>800))continue;
   replacements.set(items[0].cell,masterTag(items,{cell:items[0].cell,formula:selectorFormula(point(items[0].cell).r)}));repaired++;
  }
  if(replacements.size)files[path]=enc.encode(replaceMasters(xml,replacements));
 }return repaired;
}
export function validateWorkbookFormulas(files){
 let sheetCount=0,formulaCount=0,sharedGroupCount=0;
 for(const [path,data] of Object.entries(files)){
  if(!/^xl\/worksheets\/[^/]+\.xml$/.test(path))continue;sheetCount++;
  const xml=dec.decode(data),seen=new Set();
  for(const m of cells(xml)){
   const ref=attr(m[0].slice(0,m[0].indexOf('>')+1),'r');if(seen.has(ref))throw Error(`${path}: duplicate cell ${ref}`);seen.add(ref);
   const fs=m[0].match(/<f\b/g)?.length||0;formulaCount+=fs;
   if(fs>1||(m[0].match(/<v\b/g)?.length||0)>1)throw Error(`${path}!${ref}: duplicate formula/cache`);
  }
  for(const [si,items] of groupMap(xml)){
   sharedGroupCount++;const masters=items.filter(x=>x.formula);
   if(si==null||masters.length!==1)throw Error(`${path}: shared formula ${si} has ${masters.length} masters`);
   const [lo,hi]=String(masters[0].ref||'').split(':').map(point),end=hi||lo;
   if(!lo||!end||items.some(x=>{const p=point(x.cell);return !p||p.c<lo.c||p.c>end.c||p.r<lo.r||p.r>end.r;}))throw Error(`${path}: shared formula ${si} has invalid range`);
  }
 }
 return {sheet_count:sheetCount,formula_count:formulaCount,shared_group_count:sharedGroupCount,shared_formula_errors:0};
}
