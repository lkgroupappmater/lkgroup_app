import {approvedFontReference as reference} from './approved-font-reference.mjs';
import {deliverySheetIndex,styleMapper} from './shared-delivery-layout.mjs';
import {rewriteWorksheetRows} from './worksheet-rows.mjs';
import {richTextValue} from './cell-text-format.mjs';
const enc=new TextEncoder(),dec=new TextDecoder(),bytes=s=>enc.encode(s),text=b=>dec.decode(b);

export const APPROVED_FONT_VERSION=reference.version;
const attr=(s,n)=>s.match(new RegExp(`(?:^|\\s)${n}="([^"]*)"`))?.[1];
const set=(s,n,v)=>new RegExp(`\\s${n}="[^"]*"`).test(s)?s.replace(new RegExp(`(\\s${n}=")[^"]*(")`),(_,a,b)=>a+v+b):s.replace(/\s*\/?>(?=$)/,end=>` ${n}="${v}"${end}`);
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');

const script=c=>/[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]/u.test(c)?'ko':/[\u0e80-\u0eff]/u.test(c)?'lo':/[a-z0-9]/i.test(c)?'latin':null;
const sourceFonts=[...reference.styles.matchAll(/<font\b[^>]*>[\s\S]*?<\/font>/g)].map(m=>m[0]);
function renderRuns(value,spec,fixColors){
 const chars=Array.from(value),runs=[];
 if(spec.length===chars.length){
  let at=0;for(const [length,format] of spec.runs){runs.push({format:fixColors(format),value:chars.slice(at,at+length).join('')});at+=length;}
 }else{
  const base=fixColors(sourceFonts[spec.font].replace(/^<font\b[^>]*>/,'<rPr>').replace(/<\/font>$/,'</rPr>').replace(/<name\b/g,'<rFont'));
  let previous=base;
  for(const c of chars){const kind=script(c),format=kind?fixColors(spec.fallback?.[kind]||base):previous;previous=format;
   if(runs.at(-1)?.format===format)runs.at(-1).value+=c;else runs.push({format,value:c});
  }
 }
 return '<is>'+runs.map(r=>`<r>${r.format}<t xml:space="preserve">${escape(r.value)}</t></r>`).join('')+'</is>';
}

// Repair the currently identified templates only. Later uploaded BASE/voyage
// files remain authoritative, rather than being reset to an older font default.
export function repairApprovedWorkbookFonts(files,templateDate,{force=false,onlyDelivery=false}={}){
 if(!force&&!(Number.isFinite(Date.parse(templateDate))&&Date.parse(templateDate)<=Date.parse(reference.legacy_before)))return null;
 const source={'xl/styles.xml':bytes(reference.styles),'xl/theme/theme1.xml':bytes(reference.theme)};
 const mapper=styleMapper(files,source),styles=text(files['xl/styles.xml']);
 const section=styles.match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/);
 if(!section)throw Error('Approved font repair requires original cell styles');
 const xfs=[...section[1].matchAll(/<xf\b[^>]*?(?:\/>|>[\s\S]*?<\/xf>)/g)].map(m=>m[0]),clones=new Map();
 const shared=[...text(files['xl/sharedStrings.xml']||new Uint8Array()).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m=>m[1]);
 let changed=0;const sheets=[];
 function styleFor(id,font){
  const k=`${id}:${font}`;if(clones.has(k))return clones.get(k);
  if(!xfs[id])throw Error(`Unknown original style ${id}`);
  const xf=xfs[id].replace(/^<xf\b[^>]*>/,tag=>set(set(tag,'fontId',mapper.map('fonts',font)),'applyFont',1));
  let next=xfs.indexOf(xf);if(next<0){next=xfs.length;xfs.push(xf);}clones.set(k,next);return next;
 }
 for(const sheet of deliverySheetIndex(files)){
  const spec=reference.sheets[sheet.name];if(!spec||!files[sheet.path])continue;
  if(onlyDelivery&&!['지방배송','시내배송'].includes(sheet.name))continue;
  const last=sheet.name==='고객 리스트'?3:sheet.name==='물품 입고 내역'?4:800;let count=0;
  files[sheet.path]=rewriteWorksheetRows(text(files[sheet.path]),(row,n)=>n>last?row:row.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,cell=>{
   const tag=cell.slice(0,cell.indexOf('>')+1),ref=attr(tag,'r'),profile=spec[ref];if(!profile)return cell;
   let next=cell.replace(tag,()=>set(tag,'s',styleFor(Number(attr(tag,'s')||0),profile.font)));
   if(!/<f\b/.test(cell)){
    const body=attr(tag,'t')==='s'?shared[Number(cell.match(/<v>(\d+)<\/v>/)?.[1])]:cell.match(/<is\b[^>]*>([\s\S]*?)<\/is>/)?.[1];
    if(body!==undefined&&(profile.runs||/<r\b/.test(body))){
     const value=richTextValue(body),content=profile.runs?renderRuns(value,profile,mapper.fixColors):`<is><t xml:space="preserve">${escape(value)}</t></is>`;
     next=next.replace(/^<c\b[^>]*>/,t=>set(t,'t','inlineStr')).replace(/<v>[^<]*<\/v>|<is\b[^>]*>[\s\S]*?<\/is>/,()=>content);
    }
   }
   if(next!==cell){count++;changed++;}return next;
  }));
  sheets.push({sheet:sheet.name,changed_cells:count});
 }
 mapper.finish();
 files['xl/styles.xml']=bytes(text(files['xl/styles.xml']).replace(/<cellXfs\b[^>]*>[\s\S]*?<\/cellXfs>/,()=>`<cellXfs count="${xfs.length}">${xfs.join('')}</cellXfs>`));
 return {version:reference.version,changed_cells:changed,sheets};
}
