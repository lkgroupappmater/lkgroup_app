const enc=new TextEncoder(),dec=new TextDecoder();
const decode=s=>s.replace(/&quot;/g,'"').replace(/&apos;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const compact=s=>String(s??'').replace(/\s/g,'');
const tax=s=>/세금계산서|영세율/.test(compact(s));
function sheetMap(files){
 const rels=new Map([...dec.decode(files['xl/_rels/workbook.xml.rels']||new Uint8Array()).matchAll(/<Relationship\b[^>]*\bId="([^"]+)"[^>]*\bTarget="([^"]+)"[^>]*\/>/g)].map(m=>[m[1],m[2].startsWith('/')?m[2].slice(1):'xl/'+m[2]]));
 return new Map([...dec.decode(files['xl/workbook.xml']||new Uint8Array()).matchAll(/<sheet\b[^>]*\bname="([^"]+)"[^>]*\br:id="([^"]+)"[^>]*\/?\s*>/g)].map(m=>[decode(m[1]),rels.get(m[2])]));
}
function values(xml,strings){
 const result=new Map();
 for(const m of xml.matchAll(/<c\b([^>]*\br="([^"]+)"[^>]*)>([\s\S]*?)<\/c>/g)){
  let val=m[3].match(/<v>([\s\S]*?)<\/v>/)?.[1]??m[3].match(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/)?.[1]??'';
  val=/\bt="s"/.test(m[1])?strings[+val]??'':decode(val);result.set(m[2],val);
 }return result;
}
export function applyTaxStatementColors(files){
 if(!files['xl/workbook.xml']||!files['xl/styles.xml'])return 0;
 const sheets=sheetMap(files),customer=sheets.get('고객 리스트'),cargo=sheets.get('물품 입고 내역');
 if(!customer||!cargo)return 0;
 let changed=0,xml=dec.decode(files[customer]),styles=dec.decode(files['xl/styles.xml']);
 const originalCustomer=xml,hadRule=xml.includes('LK_TAX_CUSTOMER_GRAY_V1');
 {
  const whole=styles.match(/<dxfs\b[^>]*>([\s\S]*?)<\/dxfs>/),empty=styles.match(/<dxfs\b[^>]*\/>/);
  const dxfs=whole?[...whole[1].matchAll(/<dxf\b[^>]*?\/>|<dxf\b[^>]*>[\s\S]*?<\/dxf>/g)].map(m=>m[0]):[];
  let dxf=dxfs.findIndex(s=>s.includes('<fgColor rgb="FFBFBFBF"/>'));
  if(dxf<0){dxf=dxfs.length;dxfs.push('<dxf><fill><patternFill patternType="solid"><fgColor rgb="FFBFBFBF"/><bgColor rgb="FFBFBFBF"/></patternFill></fill></dxf>');
   const block=`<dxfs count="${dxfs.length}">${dxfs.join('')}</dxfs>`;
   if(whole||empty)styles=styles.replace((whole||empty)[0],block);else styles=styles.replace(/(?=<(?:tableStyles|colors|extLst)\b|<\/styleSheet>)/,block);
   files['xl/styles.xml']=enc.encode(styles);changed++;
  }
  const last=Math.max(6,...[...dec.decode(files[cargo]).matchAll(/<c\b[^>]*\br="N(\d+)"/g)].map(m=>+m[1]));
  const rows=Math.max(4,...[...xml.matchAll(/<c\b[^>]*\br="A(\d+)"/g)].map(m=>+m[1]));
  const remarks=`INDIRECT("'물품 입고 내역'!$P$6:$P$${last}")`,bills=`INDIRECT("'물품 입고 내역'!$N$6:$N$${last}")`;
  const clean=s=>`SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(${s}," ",""),CHAR(9),""),CHAR(10),""),CHAR(13),""),CHAR(160),"")`;
  const existing=`INDIRECT("'"&SUBSTITUTE($A4,"'","''")&"'!A"&(INDIRECT("'"&SUBSTITUTE($A4,"'","''")&"'!R6")+2))`;
  const taxFormula=s=>`(ISNUMBER(SEARCH("세금계산서",${clean(s)}))+ISNUMBER(SEARCH("영세율",${clean(s)}))>0)`;
  const formula=`AND($A4<>"",OR(IFERROR(SUMPRODUCT((${bills}=$A4)*${taxFormula(remarks)})>0,FALSE),IFERROR(${taxFormula(existing)},FALSE)))`;
  xml=xml.replace(/<!--LK_TAX_CUSTOMER_GRAY_V1--><conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,'');
  if(!hadRule)xml=xml.replace(/(<cfRule\b[^>]*\bpriority=")(\d+)(")/g,(_,a,n,b)=>a+(+n+1)+b);
  const block=`<!--LK_TAX_CUSTOMER_GRAY_V1--><conditionalFormatting sqref="A4:E${rows}"><cfRule type="expression" dxfId="${dxf}" priority="1" stopIfTrue="1"><formula>${escape(formula)}</formula></cfRule></conditionalFormatting>`;
  const later=/<(?:dataValidations|hyperlinks|printOptions|pageMargins|pageSetup|headerFooter|rowBreaks|colBreaks|customProperties|cellWatches|ignoredErrors|smartTags|drawing|legacyDrawing|picture|oleObjects|controls|webPublishItems|tableParts|extLst)\b/;
  const at=xml.search(later);xml=at<0?xml.replace('</worksheet>',block+'</worksheet>'):xml.slice(0,at)+block+xml.slice(at);
  if(xml!==originalCustomer){files[customer]=enc.encode(xml);changed++;}
 }
 // Set saved tab colors too; VBA refreshes them from displayed customer fills on generation.
 const strings=[...dec.decode(files['xl/sharedStrings.xml']||new Uint8Array()).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m=>decode([...m[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(t=>t[1]).join('')));
 const cv=values(dec.decode(files[cargo]),strings),taxBills=new Set();
 for(const [ref,value] of cv)if(/^P\d+$/.test(ref)&&tax(value)){const bill=cv.get('N'+ref.slice(1));if(bill)taxBills.add(compact(bill));}
 for(const [name,path] of sheets){
  if(!/^LK[AS]\s*\S/.test(name)||!files[path])continue;
  let sheet=dec.decode(files[path]);const cells=values(sheet,strings),total=Number(cells.get('R6'));
  if(!taxBills.has(compact(name))&&!tax(cells.get('A'+(total+2))))continue;
  const tab='<tabColor rgb="FFBFBFBF"/>';
  let next=sheet.replace(/<tabColor\b[^>]*\/>/,tab);
  if(next===sheet&&!sheet.includes(tab)){
   if(/<sheetPr\b[^>]*\/>/.test(sheet))next=sheet.replace(/<sheetPr\b([^>]*)\/>/,`<sheetPr$1>${tab}</sheetPr>`);
   else if(/<sheetPr\b/.test(sheet))next=sheet.replace(/(<sheetPr\b[^>]*>)/,'$1'+tab);
   else next=sheet.replace(/(<worksheet\b[^>]*>)/,'$1<sheetPr>'+tab+'</sheetPr>');
  }
  if(next!==sheet){files[path]=enc.encode(next);changed++;}
 }
 return changed;
}

// Used by the private worker to prove formatting changes cannot alter cell data.
export function stripStatementPresentation(xml){
 return xml.replace(/<!--LK_TAX_CUSTOMER_GRAY_V1-->/g,'').replace(/<conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,'').replace(/<tabColor\b[^>]*\/>/g,'').replace(/<sheetPr><\/sheetPr>/g,'').replace(/<sheetPr\b([^>]*)><\/sheetPr>/g,'<sheetPr$1/>');
}
