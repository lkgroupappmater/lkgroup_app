// Formatting is part of the uploaded template, not a recalculated business value.
// This manifest travels only between the existing authenticated export stages.
import {deliverySheetIndex} from './shared-delivery-layout.mjs';
import {richTextBody,richTextValue,sharedRichText} from './cell-text-format.mjs';
const dec=new TextDecoder(),enc=new TextEncoder();
const text=b=>dec.decode(b||new Uint8Array());
const attr=(s,n)=>s.match(new RegExp(`(?:^|\\s)${n}="([^"]*)"`))?.[1];
const names={numFmts:'numFmt',fonts:'font',fills:'fill',borders:'border',cellStyleXfs:'xf',cellXfs:'xf',dxfs:'dxf'};
export const TEMPLATE_STYLE_VERSION='2026-11-21.template-rich-text-v2';
export const STYLE_CONTEXT_ENTRY='_lk_internal_template_styles.json';
export function styleTables(xml){
 const out={};
 for(const [name,child] of Object.entries(names)){
  const block=xml.match(new RegExp(`<${name}\\b[^>]*?(?:/>|>[\\s\\S]*?</${name}>)`))?.[0];
  const entries=block?[...block.matchAll(new RegExp(`<${child}\\b[^>]*?(?:/>|>[\\s\\S]*?</${child}>)`,'g'))].map(m=>m[0]):[];
  if(block&&attr(block.slice(0,block.indexOf('>')+1),'count')!==undefined&&Number(attr(block,'count'))!==entries.length)throw Error(`Excel ${name} style count mismatch`);
  out[name]=entries;
 }
 if(!out.cellXfs.length)throw Error('Excel cell styles are missing');
 return out;
}
function header(xml,sheetName){
 const cells={},rows=[];
 // Only the first five template rows. Later invoice item/footer rows may move.
 for(const m of xml.matchAll(/<row\b[^>]*?(?:\/>|>[\s\S]*?<\/row>)/g)){
  const row=m[0],n=Number(attr(row.slice(0,row.indexOf('>')+1),'r'));
  if(n>5)break;
  rows.push([n,...['ht','customHeight','s','customFormat','hidden'].map(k=>attr(row.slice(0,row.indexOf('>')+1),k)??null)]);
  for(const c of row.matchAll(/<c\b[^>]*>/g)){const ref=attr(c[0],'r');if(ref)cells[ref]=Number(attr(c[0],'s')||0);}
 }
 let cols=xml.match(/<cols\b[\s\S]*?<\/cols>/)?.[0]||'';
 // BA:BL are the existing hidden identity helper columns, not template input columns.
 if(sheetName==='물품 입고 내역'){
  const visible=Array(52).fill(null);
  for(const [tag] of cols.matchAll(/<col\b[^>]*\/>/g)){
   const lo=Number(attr(tag,'min')),hi=Math.min(52,Number(attr(tag,'max')));
   const value=tag.replace(/\s(?:min|max)="[^"]*"/g,'');
   for(let c=lo;c<=hi;c++)visible[c-1]=value;
  }
  cols=visible;
 }
 return {cells,rows,cols,merges:xml.match(/<mergeCells\b[^>]*?(?:\/>|>[\s\S]*?<\/mergeCells>)/)?.[0]||''};
}
const helpers=new Set(['고객 ID','명세서 번호 관리','배송 매칭 확인','신규 고객 ID','명세서 고객 ID 연결','지방배송','시내배송']);
function captureRichText(files,paths){
 const shared=sharedRichText(files),out=[];
 for(const s of deliverySheetIndex(files)){
  if(paths&&!paths.has(s.path))continue;
  const xml=text(files[s.path]);if(!/<r\b/.test(xml)&&!shared.size)continue;
  for(const [cell] of xml.matchAll(/<c\b[^>]*\bt="(?:s|inlineStr)"[^>]*>[\s\S]*?<\/c>/g)){
   const body=richTextBody(cell,shared);if(body!==undefined)out.push({path:s.path,sheet:s.name,ref:attr(cell.slice(0,cell.indexOf('>')+1),'r'),body});
  }
 }
 return out;
}
export function captureTemplateStyles(files){
 const sheets=deliverySheetIndex(files).filter(s=>!helpers.has(s.name)&&files[s.path]).map(s=>({name:s.name,path:s.path,...header(text(files[s.path]),s.name)}));
 return {version:TEMPLATE_STYLE_VERSION,tables:styleTables(text(files['xl/styles.xml'])),theme:text(files['xl/theme/theme1.xml']),sheets,richText:captureRichText(files)};
}
export function assertTemplateStyles(files,before){
 if(![TEMPLATE_STYLE_VERSION,'2026-11-18.template-style-preservation-v1'].includes(before?.version))throw Error('Invalid Excel template style manifest');
 const after=styleTables(text(files['xl/styles.xml']));
 if(before.theme!==text(files['xl/theme/theme1.xml']))throw Error('Excel template theme changed');
 // Every existing index must keep its definition. Additional styles are allowed.
 for(const [name,entries] of Object.entries(before.tables))for(let i=0;i<entries.length;i++)if(entries[i]!==after[name][i])throw Error(`Excel original ${name}[${i}] was changed`);
 let checked=0;
 for(const s of before.sheets){
  if(!files[s.path])throw Error(`Excel template sheet missing: ${s.name}`);
  const current=header(text(files[s.path]),s.name);
  for(const [ref,id] of Object.entries(s.cells)){
   if(current.cells[ref]!==id)throw Error(`Excel template formatting changed: ${s.name}!${ref}`);
   if(!after.cellXfs[id])throw Error(`Unknown Excel cell style: ${s.name}!${ref}`);
   checked++;
  }
  for(const key of ['rows','cols','merges'])if(JSON.stringify(s[key])!==JSON.stringify(current[key]))throw Error(`Excel template ${key} changed: ${s.name}`);
 }
 const shared=sharedRichText(files),byPath=new Map();
 for(const s of before.richText??[]){
  if(!byPath.has(s.path))byPath.set(s.path,new Map([...text(files[s.path]).matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)].map(([c])=>[attr(c.slice(0,c.indexOf('>')+1),'r'),c])));
  const cell=byPath.get(s.path).get(s.ref)||'',body=richTextBody(cell,shared);
  // Deleted delivery inputs may become empty. Any remaining text must retain
  // rich formatting, including when only a voyage number has changed.
  const value=body===undefined?(richTextValue(cell)||(/<v>[^<]+<\/v>/.test(cell)?'[stored value]':'')):richTextValue(body);
  if(!value&&!/<f\b/.test(cell))continue;
  if(body===undefined)throw Error(`Excel rich text formatting removed: ${s.sheet}!${s.ref}`);
  if(richTextValue(s.body)===value&&s.body!==body)throw Error(`Excel rich text formatting changed: ${s.sheet}!${s.ref}`);
  const formats=new Set([...s.body.matchAll(/<rPr\b[^>]*?(?:\/>|>[\s\S]*?<\/rPr>)/g)].map(m=>m[0]));
  const currentFormats=new Set([...body.matchAll(/<rPr\b[^>]*?(?:\/>|>[\s\S]*?<\/rPr>)/g)].map(m=>m[0]));
  for(const [run] of s.body.matchAll(/<r\b[^>]*>[\s\S]*?<\/r>/g)){
   const runText=richTextValue(run),format=run.match(/<rPr\b[^>]*?(?:\/>|>[\s\S]*?<\/rPr>)/)?.[0];
   if(runText&&format&&value.includes(runText)&&!currentFormats.has(format))throw Error(`Excel rich text font removed: ${s.sheet}!${s.ref}`);
  }
  for(const [format] of body.matchAll(/<rPr\b[^>]*?(?:\/>|>[\s\S]*?<\/rPr>)/g))if(!formats.has(format))throw Error(`Excel rich text font changed: ${s.sheet}!${s.ref}`);
 }
 return {version:TEMPLATE_STYLE_VERSION,protected_sheets:before.sheets.length,protected_header_cells:checked,protected_rich_text_cells:before.richText?.length??0,original_style_definitions_preserved:true,header_formats_preserved:true,rich_text_formats_preserved:!!before.richText,...(before.headerRepair?{approved_header_repair:before.headerRepair}:{})};
}
export function refreshDeliveryStyleGuard(files){
 if(!files[STYLE_CONTEXT_ENTRY])return;
 const before=JSON.parse(text(files[STYLE_CONTEXT_ENTRY]));
 const paths=new Set(deliverySheetIndex(files).filter(s=>['지방배송','시내배송'].includes(s.name)).map(s=>s.path));
 before.richText=[...(before.richText??[]).filter(s=>!paths.has(s.path)),...captureRichText(files,paths)];
 files[STYLE_CONTEXT_ENTRY]=enc.encode(JSON.stringify(before));
}
export function beginTemplateStyleGuard(files,{headerRepair}={}){
 if(files[STYLE_CONTEXT_ENTRY])throw Error('Reserved Excel template style manifest already exists');
 files[STYLE_CONTEXT_ENTRY]=enc.encode(JSON.stringify({...captureTemplateStyles(files),...(headerRepair?{headerRepair}:{})}));
}
export function finishTemplateStyleGuard(files){
 if(!files[STYLE_CONTEXT_ENTRY])throw Error('Excel template style preservation was not initialized');
 const before=JSON.parse(text(files[STYLE_CONTEXT_ENTRY]));
 const report=assertTemplateStyles(files,before);delete files[STYLE_CONTEXT_ENTRY];return report;
}

