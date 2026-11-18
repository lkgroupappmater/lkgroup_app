import {headerReference} from './template-header-reference.mjs';
import {deliverySheetIndex,styleMapper} from './shared-delivery-layout.mjs';
const enc=new TextEncoder(),dec=new TextDecoder();
// Repair only the templates that existed when the corrected workbook was given.
// A later BASE/voyage upload is authoritative and must never be overridden.
const legacyPaths=new Set([
 'base/kr_la_air/0f91cf9b-cadc-44f1-a685-75423f3dee98_KR_LA_AIR_2026_V00_SHIPMENTS.xlsm',
 'base/kr_la_sea/e642c9ea-0b7b-4687-b51d-9b2fb66107ef_KR_LA_SEA_2026_V00_SHIPMENTS.xlsm',
 'macro-updates/kr_la_air/264c6416-3261-47ce-b0da-ba526d4bfd46.xlsm',
]);
const set=(tag,name,value)=>new RegExp(`\\s${name}="[^"]*"`).test(tag)?tag.replace(new RegExp(`(\\s${name}=")[^"]*(")`),(_,a,b)=>a+value+b):tag.replace(/\s*\/?>(?=$)/,end=>` ${name}="${value}"${end}`);
const col=ref=>[...ref.replace(/\d/g,'')].reduce((a,c)=>a*26+c.charCodeAt(0)-64,0);
export function repairApprovedTemplateHeaders(files,storagePath,{force=false}={}){
 if(!force&&!legacyPaths.has(storagePath))return null;
 const source={'xl/styles.xml':enc.encode(headerReference.styles),'xl/theme/theme1.xml':enc.encode(headerReference.theme)};
 const mapper=styleMapper(files,source);let sheets=0,cells=0;
 for(const sheet of deliverySheetIndex(files)){
  const kind=sheet.name==='고객 리스트'?'customers':/^(LKA|LKS)\s/.test(sheet.name)||sheet.name==='명세서 빠르게 확인'?'statement':null;
  if(!kind||!files[sheet.path])continue;
  const spec=headerReference.headers[kind];let xml=dec.decode(files[sheet.path]);
  const wanted=new Map(spec.rows.map(r=>[r.n,r]));
  xml=xml.replace(/<row\b[^>]*?(?:\/>|>[\s\S]*?<\/row>)/g,row=>{
   const n=Number(row.match(/^<row\b[^>]*\br="(\d+)"/)?.[1]),spec=wanted.get(n);if(!spec)return row;
   const seen=new Set();row=row.replace(/<c\b[^>]*>/g,tag=>{
    const ref=tag.match(/\br="([A-Z]+\d+)"/)?.[1];if(!(ref in spec.cells))return tag;
    seen.add(ref);cells++;return set(tag,'s',mapper.map('cellXfs',spec.cells[ref]));
   });
   if(row.endsWith('/>'))row=row.slice(0,-2)+'></row>';
   for(const [ref,id] of Object.entries(spec.cells))if(!seen.has(ref)){
    const cell=`<c r="${ref}" s="${mapper.map('cellXfs',id)}"/>`;
    const next=[...row.matchAll(/<c\b[^>]*\br="([A-Z]+\d+)"/g)].find(m=>col(m[1])>col(ref));
    row=next?row.slice(0,next.index)+cell+row.slice(next.index):row.replace('</row>',()=>cell+'</row>');cells++;
   }
   if(spec.ht!==null)row=row.replace(/^<row\b[^>]*>/,tag=>set(set(tag,'ht',spec.ht),'customHeight',1));
   wanted.delete(n);return row;
  });
  if(wanted.size)throw Error(`Missing approved template header rows: ${sheet.name}`);
  files[sheet.path]=enc.encode(xml);sheets++;
 }
 mapper.finish();
 return {source_sha256:headerReference.source_sha256,repaired_sheets:sheets,repaired_cells:cells};
}
