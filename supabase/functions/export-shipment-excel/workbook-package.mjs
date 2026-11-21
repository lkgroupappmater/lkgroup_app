// Validate the OPC links used by every generated Excel package. This is a
// package integrity check; native Excel/Open XML schema tests remain separate.
const dec=new TextDecoder(),enc=new TextEncoder();
const text=v=>typeof v==='string'?v:dec.decode(v||new Uint8Array());
const unescape=s=>String(s).replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&amp;','&');
const attr=(s,n)=>unescape(s.match(new RegExp(`(?:^|\\s)${n}="([^"]*)"`))?.[1]||'');
const tags=(xml,name)=>[...xml.matchAll(new RegExp(`<(?:[\\w.-]+:)?${name}\\b[^>]*>`,`g`))].map(m=>m[0]);
export const WORKBOOK_PACKAGE_VERSION='2026-11-21.package-links-v1';
function sourcePart(path){
 if(path==='_rels/.rels')return '';
 const m=path.match(/^(.*\/)?_rels\/([^/]+)\.rels$/);
 if(!m)throw Error(`Invalid Excel relationship path: ${path}`);
 return (m[1]||'')+m[2];
}
function resolve(source,target){
 let value=target.split('#')[0];if(!value)return source;
 try{value=decodeURIComponent(value);}catch{throw Error('Invalid Excel relationship target encoding');}
 const parent=source.slice(0,source.lastIndexOf('/')+1),parts=[];
 for(const p of (value.startsWith('/')?value.slice(1):parent+value).split('/')){
  if(p==='..'){if(!parts.length)throw Error('Excel relationship escapes package');parts.pop();}
  else if(p&&p!=='.')parts.push(p);
 }
 return parts.join('/');
}
export function discardCalculationChain(files){
 const paths=new Set(['xl/calcChain.xml']);let relationships=0,contentTypes=0,parts=0;
 const relPath='xl/_rels/workbook.xml.rels';
 if(files[relPath]){
  const before=text(files[relPath]),after=before.replace(/<(?:[\w.-]+:)?Relationship\b[^>]*(?:\/>|>[\s\S]*?<\/(?:[\w.-]+:)?Relationship>)/g,tag=>{
   if(!attr(tag,'Type').endsWith('/calcChain'))return tag;
   paths.add(resolve('xl/workbook.xml',attr(tag,'Target')));relationships++;return '';
  });if(after!==before)files[relPath]=enc.encode(after);
 }
 const types='[Content_Types].xml';
 if(files[types]){
  const before=text(files[types]),after=before.replace(/<(?:[\w.-]+:)?Override\b[^>]*(?:\/>|>[\s\S]*?<\/(?:[\w.-]+:)?Override>)/g,tag=>{
   if(!attr(tag,'ContentType').endsWith('spreadsheetml.calcChain+xml'))return tag;
   paths.add(resolve('',attr(tag,'PartName')));contentTypes++;return '';
  });if(after!==before)files[types]=enc.encode(after);
 }
 for(const path of paths)if(files[path]){delete files[path];parts++;}
 return {parts,relationships,content_types:contentTypes};
}
export function validateWorkbookPackage(files){
 for(const p of ['[Content_Types].xml','_rels/.rels','xl/workbook.xml','xl/_rels/workbook.xml.rels'])if(!files[p])throw Error(`Excel package missing ${p}`);
 let relationshipCount=0;const workbookRelations=new Map();
 for(const path of Object.keys(files).filter(p=>p.endsWith('.rels'))){
  const source=sourcePart(path),seen=new Set();if(source&&!files[source])throw Error(`Excel relationship source missing: ${source}`);
  for(const tag of tags(text(files[path]),'Relationship')){
   const id=attr(tag,'Id'),target=attr(tag,'Target');if(!id||seen.has(id))throw Error(`Excel relationship ID missing or duplicated: ${path}/${id}`);seen.add(id);relationshipCount++;
   if(attr(tag,'TargetMode')==='External')continue;
   if(!target)throw Error(`Excel relationship target missing: ${path}/${id}`);
   const part=resolve(source,target);if(!files[part])throw Error(`Excel relationship target not found: ${path} -> ${part}`);
   if(path==='xl/_rels/workbook.xml.rels')workbookRelations.set(id,part);
  }
 }
 const defaults=new Set(),overrides=new Set();
 for(const tag of tags(text(files['[Content_Types].xml']),'Default')){
  const ext=attr(tag,'Extension').toLowerCase();if(!ext||defaults.has(ext))throw Error('Excel default content type duplicated');defaults.add(ext);
 }
 for(const tag of tags(text(files['[Content_Types].xml']),'Override')){
  const part=resolve('',attr(tag,'PartName'));if(!files[part])throw Error(`Excel content type target not found: ${part}`);
  if(overrides.has(part))throw Error(`Excel content type duplicated: ${part}`);overrides.add(part);
 }
 for(const path of Object.keys(files))if(path!=='[Content_Types].xml'&&!path.endsWith('/')&&!overrides.has(path)&&!defaults.has(path.split('.').pop().toLowerCase()))throw Error(`Excel content type missing: ${path}`);
 const names=new Set(),ids=new Set();let sheetCount=0;
 for(const tag of tags(text(files['xl/workbook.xml']),'sheet')){
  const name=attr(tag,'name').toLowerCase(),id=attr(tag,'sheetId'),rel=attr(tag,'r:id');
  if(!name||names.has(name)||!id||ids.has(id))throw Error('Excel sheet name or ID missing/duplicated');names.add(name);ids.add(id);sheetCount++;
  if(!workbookRelations.has(rel))throw Error(`Excel sheet relationship missing: ${name}`);
 }
 if(!sheetCount)throw Error('Excel workbook contains no sheets');
 return {version:WORKBOOK_PACKAGE_VERSION,part_count:Object.keys(files).length,relationship_count:relationshipCount,sheet_count:sheetCount,package_errors:0};
}
