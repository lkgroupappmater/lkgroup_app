// Formatting is part of the uploaded template, not a recalculated business value.
// This manifest travels only between the existing authenticated export stages.
import {captureStatementNotices} from './statement-notice-format.mjs';
import {deliverySheetIndex} from './shared-delivery-layout.mjs';
import {richTextBody,richTextValue,sharedRichText} from './cell-text-format.mjs';
const dec=new TextDecoder(),enc=new TextEncoder();
const text=b=>dec.decode(b||new Uint8Array());
const attr=(s,n)=>s.match(new RegExp(`(?:^|\\s)${n}="([^"]*)"`))?.[1];
const names={numFmts:'numFmt',fonts:'font',fills:'fill',borders:'border',cellStyleXfs:'xf',cellXfs:'xf',dxfs:'dxf'};
export const TEMPLATE_STYLE_VERSION='2026-11-25.statement-notice-styles-v4';
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
const helpers=new Set(['고객 ID','명세서 번호 관리','배송 매칭 확인','신규 고객 ID','명세서 고객 ID 연결','지방배송','시내배송','_LK_Discount_Identity']);
function captureRichText(files,paths){
 const shared=sharedRichText(files),out=[];
 for(const s of deliverySheetIndex(files)){
  if(paths&&!paths.has(s.path))continue;
  const xml=text(files[s.path]);if(!xml.includes('<r>')&&!xml.includes('<r ')&&(!shared.size||!xml.includes('t="s"')))continue;
  for(const [cell] of xml.matchAll(/<c\b[^>]*\bt="(?:s|inlineStr)"[^>]*>[\s\S]*?<\/c>/g)){
   const body=richTextBody(cell,shared);if(body!==undefined)out.push({path:s.path,sheet:s.name,ref:attr(cell.slice(0,cell.indexOf('>')+1),'r'),body});
  }
 }
 return out;
}
export function captureTemplateStyles(files){
 const sheets=deliverySheetIndex(files).filter(s=>!helpers.has(s.name)&&files[s.path]).map(s=>({name:s.name,path:s.path,...header(text(files[s.path]),s.name)}));
 return {version:TEMPLATE_STYLE_VERSION,tables:styleTables(text(files['xl/styles.xml'])),theme:text(files['xl/theme/theme1.xml']),sheets,statementNotices:captureStatementNotices(files),richText:captureRichText(files),deliveryFonts:captureDeliveryFonts(files)};
}
function captureDeliveryFonts(files){
 const tables=styleTables(text(files['xl/styles.xml'])),fonts={},sheets=[];
 for(const s of deliverySheetIndex(files).filter(s=>['지방배송','시내배송'].includes(s.name))){
  const cells={};
  for(const [cell] of text(files[s.path]).matchAll(/<c\b[^>]*>/g)){
   const ref=attr(cell,'r');if(!/^[B-H]\d+$/.test(ref||'')||Number(ref.slice(1))>800)continue;
   const xf=tables.cellXfs[Number(attr(cell,'s')||0)],id=Number(attr(xf||'','fontId')||0);
   if(!xf||!tables.fonts[id])throw Error(`Unknown delivery font: ${s.name}!${ref}`);
   fonts[id]=tables.fonts[id];cells[ref]=[id,attr(xf,'applyFont')??null];
  }
  sheets.push({name:s.name,path:s.path,cells});
 }
 return {fonts,sheets};
}
export function assertTemplateStyles(files,before){
 if(![TEMPLATE_STYLE_VERSION,'2026-11-22.delivery-font-preservation-v3','2026-11-21.template-rich-text-v2','2026-11-18.template-style-preservation-v1'].includes(before?.version))throw Error('Invalid Excel template style manifest');
 const after=styleTables(text(files['xl/styles.xml']));
 if(before.theme!==text(files['xl/theme/theme1.xml']))throw Error('Excel template theme changed');
 // Every existing index must keep its definition. Additional styles are allowed.
 for(const [name,entries] of Object.entries(before.tables))for(let i=0;i<entries.length;i++)if(entries[i]!==after[name][i])throw Error(`Excel original ${name}[${i}] was changed`);
 let checked=0;
 for(const s of before.sheets){
  // Older exports already contain the generated hidden discount helper. It is
  // intentionally rebuilt, and is not part of the user's visible template.
  if(s.name==='_LK_Discount_Identity')continue;
  if(!files[s.path])throw Error(`Excel template sheet missing: ${s.name}`);
  const current=header(text(files[s.path]),s.name);
  for(const [ref,id] of Object.entries(s.cells)){
   if(current.cells[ref]!==id)throw Error(`Excel template formatting changed: ${s.name}!${ref}`);
   if(!after.cellXfs[id])throw Error(`Unknown Excel cell style: ${s.name}!${ref}`);
   checked++;
  }
  for(const key of ['rows','cols','merges'])if(JSON.stringify(s[key])!==JSON.stringify(current[key]))throw Error(`Excel template ${key} changed: ${s.name}`);
 }
 const noticeFormats={};
 let noticeCount=0;
 if(before.statementNotices){
  const notices=captureStatementNotices(files);
  // Compare after manifest serialization as well as in-process capture.
  if(JSON.stringify(notices)!==JSON.stringify(before.statementNotices))throw Error('Excel statement notice text, font, alignment or row geometry changed');
  for(const {notices:lines} of notices)for(const line of lines){
   noticeCount++;
   if(!/^A\d+:N\d+$/.test(line.range))continue;
   const xf=after.cellXfs[line.style];
   if(!xf)throw Error('Unknown Excel statement notice style');
   const font=after.fonts[Number(attr(xf,'fontId')||0)]||'';
   const key=(attr(font.match(/<sz\b[^>]*>/)?.[0]||'','val')||'inherited')+'pt/'+(attr(xf.match(/<alignment\b[^>]*>/)?.[0]||'','horizontal')||'general');
   noticeFormats[key]=(noticeFormats[key]||0)+1;
  }
 }
 let deliveryChecked=0;
 if(before.deliveryFonts){
  const current=captureDeliveryFonts(files),bySheet=new Map(current.sheets.map(s=>[s.path,s]));
  for(const s of before.deliveryFonts.sheets)for(const [ref,[id,apply]] of Object.entries(s.cells)){
   const next=bySheet.get(s.path)?.cells[ref];
   if(!next||current.fonts[next[0]]!==before.deliveryFonts.fonts[id]||next[1]!==apply)throw Error(`Excel delivery font changed: ${s.name}!${ref}`);
   deliveryChecked++;
  }
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
 return {version:TEMPLATE_STYLE_VERSION,protected_sheets:before.sheets.length,protected_header_cells:checked,protected_statement_notices:noticeCount,full_width_notice_formats:noticeFormats,statement_notice_repairs:before.noticeRepairs??0,protected_rich_text_cells:before.richText?.length??0,protected_delivery_font_cells:deliveryChecked,original_style_definitions_preserved:true,header_formats_preserved:true,rich_text_formats_preserved:!!before.richText,delivery_fonts_preserved:!!before.deliveryFonts,...(before.headerRepair?{approved_header_repair:before.headerRepair}:{}),...(before.approvedFonts?{approved_fonts:before.approvedFonts}:{})};
}
export function refreshDeliveryStyleGuard(files){
 if(!files[STYLE_CONTEXT_ENTRY])return;
 const before=JSON.parse(text(files[STYLE_CONTEXT_ENTRY]));
 const paths=new Set(deliverySheetIndex(files).filter(s=>['지방배송','시내배송'].includes(s.name)).map(s=>s.path));
 before.richText=[...(before.richText??[]).filter(s=>!paths.has(s.path)),...captureRichText(files,paths)];
 before.deliveryFonts=captureDeliveryFonts(files);
 files[STYLE_CONTEXT_ENTRY]=enc.encode(JSON.stringify(before));
}
export function beginTemplateStyleGuard(files,{headerRepair,approvedFonts,noticeRepairs=0}={}){
 if(files[STYLE_CONTEXT_ENTRY])throw Error('Reserved Excel template style manifest already exists');
 files[STYLE_CONTEXT_ENTRY]=enc.encode(JSON.stringify({...captureTemplateStyles(files),noticeRepairs,...(headerRepair?{headerRepair}:{}),...(approvedFonts?{approvedFonts}:{})}));
}
export function finishTemplateStyleGuard(files){
 if(!files[STYLE_CONTEXT_ENTRY])throw Error('Excel template style preservation was not initialized');
 const before=JSON.parse(text(files[STYLE_CONTEXT_ENTRY]));
 const report=assertTemplateStyles(files,before);delete files[STYLE_CONTEXT_ENTRY];return report;
}

