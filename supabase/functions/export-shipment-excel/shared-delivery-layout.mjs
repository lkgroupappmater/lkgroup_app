// Copy the two complete delivery sheets, never cargo, prices, invoices or VBA.
// Shared strings and styles belong to a workbook, so their IDs must be remapped.
const dec=new TextDecoder(),enc=new TextEncoder();
const text=b=>dec.decode(b||new Uint8Array()),bytes=s=>enc.encode(s);
const attr=(s,n)=>s.match(new RegExp(`(?:^|\\s)${n}="([^"]*)"`))?.[1];
const set=(s,n,v)=>new RegExp(`\\s${n}="[^"]*"`).test(s)?s.replace(new RegExp(`(\\s${n}=")[^"]*(")`),(_,a,b)=>a+v+b):s.replace(/\s*\/?>(?=$)/,end=>` ${n}="${v}"${end}`);
const tags=(xml,name)=>[...xml.matchAll(new RegExp(`<${name}\\b[^>]*?(?:/>|>[\\s\\S]*?</${name}>)`,'g'))].map(m=>m[0]);
const entities=s=>s.replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&amp;','&');
function normalize(path){const parts=[];for(const p of path.split('/')){if(!p||p==='.')continue;if(p==='..'){if(!parts.length)throw Error('Invalid workbook path');parts.pop();}else parts.push(p);}return parts.join('/');}
const dir=p=>p.slice(0,p.lastIndexOf('/')+1);
const resolve=(part,target)=>normalize(target.startsWith('/')?target:dir(part)+target);
const relPath=p=>dir(p)+'_rels/'+p.slice(p.lastIndexOf('/')+1)+'.rels';
const relative=(part,destination)=>{const a=dir(part).split('/').filter(Boolean),b=destination.split('/');while(a[0]&&a[0]===b[0]){a.shift();b.shift();}return '../'.repeat(a.length)+b.join('/');};
export function deliverySheetIndex(files){
 const rels=new Map(tags(text(files['xl/_rels/workbook.xml.rels']),'Relationship').map(r=>[attr(r,'Id'),resolve('xl/workbook.xml',attr(r,'Target')||'')]));
 return tags(text(files['xl/workbook.xml']),'sheet').map((s,index)=>({name:entities(attr(s,'name')||''),index,path:rels.get(attr(s,'r:id'))}));
}
function styleMapper(target,source){
 let dst=text(target['xl/styles.xml']);const src=text(source['xl/styles.xml']);
 if(!src||!dst)throw Error('Delivery layout styles are missing');
 const tables={},names={numFmts:'numFmt',fonts:'font',fills:'fill',borders:'border',cellStyleXfs:'xf',cellXfs:'xf',dxfs:'dxf'};
 for(const [name,child] of Object.entries(names)){
  const section=s=>s.match(new RegExp(`<${name}\\b[^>]*(?:/>|>[\\s\\S]*?</${name}>)`))?.[0]||'';
  tables[name]={from:tags(section(src),child),to:tags(section(dst),child),old:section(dst),mapped:new Map()};
 }
 const theme=text(source['xl/theme/theme1.xml']);
 const scheme=theme.match(/<a:clrScheme\b[^>]*>([\s\S]*?)<\/a:clrScheme>/)?.[1]||'';
 const colors=['lt1','dk1','lt2','dk2','accent1','accent2','accent3','accent4','accent5','accent6','hlink','folHlink'].map(n=>{const t=scheme.match(new RegExp(`<a:${n}>([\\s\\S]*?)</a:${n}>`))?.[1]||'';return attr(t,'lastClr')||attr(t,'val');});
 const fixColors=xml=>xml.replace(/<(?:color|fgColor|bgColor)\b[^>]*\/>/g,t=>{const id=attr(t,'theme');if(id===undefined)return t;const color=colors[Number(id)];if(!color)throw Error('Unknown delivery theme color');return set(t.replace(/\s+theme="[^"]*"/,''),'rgb','FF'+color);});
 function map(name,id){
  id=Number(id);const table=tables[name];if(table.mapped.has(id))return table.mapped.get(id);
  if(name==='numFmts'&&id<164)return id;
  let item=name==='numFmts'?table.from.find(t=>Number(attr(t,'numFmtId'))===id):table.from[id];
  if(!item)throw Error(`Unknown delivery ${name} ${id}`);
  if(name==='cellXfs'||name==='cellStyleXfs')item=item.replace(/^<xf\b[^>]*>/,t=>{
   for(const [a,tableName] of [['fontId','fonts'],['fillId','fills'],['borderId','borders'],['numFmtId','numFmts'],['xfId','cellStyleXfs']])if(attr(t,a)!==undefined&&!(name==='cellStyleXfs'&&a==='xfId'))t=set(t,a,map(tableName,attr(t,a)));return t;
  });
  else if(name!=='numFmts')item=fixColors(item);
  let mapped;
  if(name==='numFmts'){
   const found=table.to.find(t=>attr(t,'formatCode')===attr(item,'formatCode'));
   mapped=found?Number(attr(found,'numFmtId')):Math.max(163,...table.to.map(t=>Number(attr(t,'numFmtId'))))+1;
   if(!found)table.to.push(set(item,'numFmtId',mapped));
  }else{mapped=table.to.indexOf(item);if(mapped<0){mapped=table.to.length;table.to.push(item);}}
  table.mapped.set(id,mapped);return mapped;
 }
 function finish(){
  const order=['numFmts','fonts','fills','borders','cellStyleXfs','cellXfs','cellStyles','dxfs','tableStyles','colors','extLst'];
  for(const [name,t] of Object.entries(tables)){
   if(!t.to.length&&!t.old)continue;
   const next=`<${name} count="${t.to.length}">${t.to.join('')}</${name}>`;
   if(t.old)dst=dst.replace(t.old,()=>next);
   else{const after=order.slice(order.indexOf(name)+1).map(n=>dst.indexOf('<'+n)).filter(n=>n>=0);const at=after.length?Math.min(...after):dst.indexOf('</styleSheet>');dst=dst.slice(0,at)+next+dst.slice(at);}
  }
  target['xl/styles.xml']=bytes(dst);
 }
 return {map,finish,fixColors};
}
export function copySharedDeliveryLayout(target,source){
 const dstIndex=deliverySheetIndex(target),srcIndex=deliverySheetIndex(source);
 const shared=tags(text(source['xl/sharedStrings.xml']),'si').map(s=>s.replace(/^<si\b[^>]*>/,'').replace(/<\/si>$/,''));
 const styles=styleMapper(target,source),report=[];
 let contentTypes=text(target['[Content_Types].xml']),workbook=text(target['xl/workbook.xml']);
 const sourceTypes=text(source['[Content_Types].xml']);
 function contentType(from,to){
  const explicit=tags(sourceTypes,'Override').find(t=>attr(t,'PartName')==='/'+from);
  const ext=from.split('.').pop();const fallback=tags(sourceTypes,'Default').find(t=>attr(t,'Extension')===ext);
  const type=attr(explicit||fallback||'','ContentType');if(!type)throw Error('Missing delivery part type: '+from);
  const existing=tags(contentTypes,'Override').find(t=>attr(t,'PartName')==='/'+to);
  const entry=`<Override PartName="/${to}" ContentType="${type}"/>`;
  contentTypes=existing?contentTypes.replace(existing,()=>entry):contentTypes.replace('</Types>',entry+'</Types>');
 }
 function cloneRelations(from,to,prefix,seen=new Map()){
  const path=relPath(from);if(!source[path]){delete target[relPath(to)];return;}
  let xml=text(source[path]);
  xml=xml.replace(/<Relationship\b[^>]*\/>/g,r=>{
   if(attr(r,'TargetMode')==='External')return r;
   const type=(attr(r,'Type')||'').split('/').pop();
   if(!['printerSettings','drawing','image','comments','vmlDrawing','chart','chartStyle','chartColorStyle'].includes(type))throw Error('Unsupported delivery sheet attachment: '+type);
   const src=resolve(from,attr(r,'Target')||''),dst=prefix+src;
   if(!source[src])throw Error('Missing delivery attachment: '+src);
   if(!seen.has(src)){seen.set(src,dst);target[dst]=source[src].slice();contentType(src,dst);cloneRelations(src,dst,prefix,seen);}
   return set(r,'Target',relative(to,dst));
  });
  target[relPath(to)]=bytes(xml);
 }
 for(const name of ['지방배송','시내배송']){
  const src=srcIndex.find(s=>s.name===name),dst=dstIndex.find(s=>s.name===name);
  if(!src)continue; // A BASE with an omitted sheet does not remove the other sheet.
  if(!dst||!source[src.path]||!target[dst.path])throw Error('Missing delivery worksheet: '+name);
  let xml=text(source[src.path]);const old=text(target[dst.path]);
  // Preserve the target VBA sheet identity. Its module and all VBA bytes stay put.
  const oldCode=attr(old.match(/<sheetPr\b[^>]*>/)?.[0]||'','codeName');
  xml=xml.replace(/<sheetPr\b[^>]*>/,t=>oldCode?set(t,'codeName',oldCode):t.replace(/\s+codeName="[^"]*"/,''));
  xml=xml.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,c=>{
   const tag=c.slice(0,c.indexOf('>')+1),style=attr(tag,'s')||'0';c=c.replace(tag,()=>set(tag,'s',styles.map('cellXfs',style)));
   if(attr(tag,'t')==='s'){
    const index=Number(c.match(/<v>(\d+)<\/v>/)?.[1]);if(shared[index]===undefined)throw Error('Missing delivery shared string');
    c=c.replace(/\bt="s"/,'t="inlineStr"').replace(/<v>\d+<\/v>/,()=>'<is>'+styles.fixColors(shared[index])+'</is>');
   }
   return c;
  });
  xml=xml.replace(/<(?:row|col)\b[^>]*>/g,t=>{const key=t.startsWith('<row')?'s':'style';return attr(t,key)!==undefined?set(t,key,styles.map('cellXfs',attr(t,key))):t;});
  xml=xml.replace(/<cfRule\b[^>]*>/g,t=>attr(t,'dxfId')!==undefined?set(t,'dxfId',styles.map('dxfs',attr(t,'dxfId'))):t);
  cloneRelations(src.path,dst.path,'xl/lk_delivery_layout/'+(name==='지방배송'?'province/':'city/'));
  target[dst.path]=bytes(xml);
  // Copy sheet-local print/filter ranges without touching global names.
  const names=tags(text(source['xl/workbook.xml']),'definedName').filter(t=>attr(t,'localSheetId')===String(src.index)).map(t=>t.replace(/^<definedName\b[^>]*>/,x=>set(x,'localSheetId',dst.index)));
  workbook=workbook.replace(/<definedName\b[^>]*>[\s\S]*?<\/definedName>/g,t=>attr(t,'localSheetId')===String(dst.index)?'':t);
  if(names.length)workbook=workbook.includes('</definedNames>')?workbook.replace('</definedNames>',()=>names.join('')+'</definedNames>'):workbook.replace('</sheets>',()=>'</sheets><definedNames>'+names.join('')+'</definedNames>');
  report.push({sheet:name,rows:tags(xml,'row').length,merged_ranges:tags(xml,'mergeCell').length,source_path:src.path,target_path:dst.path});
 }
 styles.finish();target['[Content_Types].xml']=bytes(contentTypes);target['xl/workbook.xml']=bytes(workbook);
 return report;
}
