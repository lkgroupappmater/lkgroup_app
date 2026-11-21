import {discountWorkbookSource,discountMatchRank,DISCOUNT_MATCH_VERSION} from './discount-matching.mjs';
import {worksheetRowEntries,rewriteWorksheetRows} from './worksheet-rows.mjs';
const enc=new TextEncoder(),dec=new TextDecoder(),text=b=>dec.decode(b),bytes=s=>enc.encode(s);
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const formulaText=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
export const DISCOUNT_FORMULA_STORAGE='independent-array-selectors-v4';
const SHEET='_LK_Discount_Identity';
// These ranges are on the helper itself. Keep their ordinary A1 references
// short, including when each cargo row is written as an independent formula.
const range=col=>`$${col}$3:$${col}$256`;
const sub=(value,from,to)=>`SUBSTITUTE(${value},${typeof from==='object'?from.f:JSON.stringify(from)},${JSON.stringify(to)})`;
function separators(value){
 for(const token of ['\\r\\n','\\r','\\n','／',';',',','|',{f:'CHAR(13)'},{f:'CHAR(10)'}])value=sub(value,token,'/');
 for(const token of [' ',{f:'CHAR(160)'},{f:'CHAR(9)'},'-','.',"'"])value=sub(value,token,'');
 return value;
}
function memberBase(value){
 value=separators(value);
 for(const token of ['대표님','사장님','대표','사장','님'])value=sub(value,token,'');
 value=sub(sub(value,'(','|'),')','');
 // Slash plus a wrapped line break is one separator, not an empty member.
 for(let i=0;i<4;i++)value=sub(value,'//','/');
 return `"|"&LOWER(${value})&"|"`;
}
function phonesBase(value){
 value=separators(value);for(const token of ['+','(',')'])value=sub(value,token,'');
 for(let i=0;i<4;i++)value=sub(value,'//','/');
 value=`"|"&${sub(value,'/','|')}&"|"`;
 for(const [from,to] of [['|00856','|0'],['|856','|0'],['|0082','|0'],['|82','|0']])value=sub(value,from,to);
 return value;
}
const count=(value,delimiter)=>`LEN(${value})-LEN(SUBSTITUTE(${value},"${delimiter}",""))`;
const first=value=>`IFERROR(MID(${value},2,FIND("|",${value},2)-2),"")`;
const last=value=>`IF(LEN(${value})<3,"",TRIM(RIGHT(SUBSTITUTE(LEFT(${value},LEN(${value})-1),"|",REPT(" ",LEN(${value}))),LEN(${value}))))`;
function selector(row,phoneColumn,special){
 const p=`$${phoneColumn}${row}`,phonePosition=`IFERROR(FIND("|"&${p}&"|",${range('D')}),0)`;
 const phoneOrdinal=`(${count(`LEFT(${range('D')},${phonePosition})`,'|')})`;
 const member = name => {
  const pos=`IFERROR(FIND("|"&${name}&"|",${range('B')}),0)`;
  const groupOrdinal=`(${count(`LEFT(${range('A')},${pos})`,'/')}+1)`;
  const flatOrdinal=`(${count(`LEFT(${range('B')},${pos})`,'|')})`;
  const paired=`((${range('E')}=1)+(${range('G')}=1)+((${range('E')}=${range('G')})*(${groupOrdinal}=${phoneOrdinal}))+((${range('E')}<>${range('G')})*(${range('F')}=${range('G')})*(${flatOrdinal}=${phoneOrdinal})))`;
  return `((${name}<>"")*(${pos}>0)*(${paired}>0))`;
 };
 const memberMatch=`((${member(`$K${row}`)}+${member(`$L${row}`)})>0)`;
 const companyMatch=`((($K${row}<>"")*ISNUMBER(FIND("|"&$K${row}&"|",${range('C')}))+($L${row}<>"")*ISNUMBER(FIND("|"&$L${row}&"|",${range('C')})))>0)`;
 const mask=`((${range('H')}=${special?2:1})*(${phonePosition}>0))`;
 // Highest member match wins before a company-only match, then original row order.
 // BASE has many empty cargo rows. Their result is already zero; avoid
 // evaluating the full chart array until a usable phone has been entered.
 // LOOKUP explicitly consumes its array argument in desktop Excel as well as
 // other engines. Keep IF out of range expressions: implicit intersection in
 // older Excel calculation modes must not silently turn every match into 0.
 return `IF(OR(LEN(${p})<8,LEN(${p})>15),0,IFERROR(1000+LOOKUP(2,1/(${mask}*${memberMatch}),ROW(${range('H')})),IFERROR(LOOKUP(2,1/(${mask}*${companyMatch}),ROW(${range('H')})),0)))`;
}
// Explicit single-cell arrays make the nested range calculations unambiguous
// in desktop Excel. Each selector owns exactly its own output cell: no shared
// formula masters, dependent references or multi-cell spill range are written.
const cell=(ref,f,value='',array=false)=>`<c r="${ref}"${typeof value==='number'?'':' t="str"'}><f${array?` t="array" ref="${ref}"`:''}>${formulaText(f)}</f><v>${esc(value)}</v></c>`;
export function validateDiscountWorksheet(data){
 const xml=typeof data==='string'?data:text(data);let formulaCount=0,arrayCount=0;
 if(/<f\b[^>]*\b(?:si=|t="shared")/.test(xml))throw Error('Discount worksheet must contain independent formulas');
 for(const m of xml.matchAll(/<c\b[^>]*>[\s\S]*?<\/c>/g)){
  const header=m[0].slice(0,m[0].indexOf('>')+1),ref=header.match(/\br="([^"]+)"/)?.[1],formula=m[0].match(/<f\b([^>]*)>([^<]+)<\/f>/),f=formula?.[2];
  if(!f||formula[1].trim().endsWith('/')||!/<v>(?:0)?<\/v>/.test(m[0]))throw Error(`Discount worksheet ${ref}: missing formula or cache`);
  const selector=/^[O-R]\d+$/.test(ref||'');
  if(selector){if(formula[1]!==` t="array" ref="${ref}"`)throw Error(`Discount worksheet ${ref}: invalid single-cell array range`);arrayCount++;}
  else if(formula[1])throw Error(`Discount worksheet ${ref}: unexpected formula attributes`);
  const stringCell=/^(?:A|B|C|D|J|K|L|M|N|S)\d+$/.test(ref||'');
  if(stringCell!==/\bt="str"/.test(header))throw Error(`Discount worksheet ${ref}: invalid formula cache type`);
  formulaCount++;
 }
 if(!formulaCount)throw Error('Discount worksheet has no formulas');
 return {formula_storage:DISCOUNT_FORMULA_STORAGE,formula_count:formulaCount,array_formula_count:arrayCount};
}
function putFormula(row,ref,f,value){
 const pattern=new RegExp(`<c\\b[^>]*\\br="${ref}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`),prior=row.match(pattern)?.[0];
 if(!prior)return row;
 const style=prior.match(/\bs="\d+"/)?.[0];
 return row.replace(pattern,`<c r="${ref}"${style?' '+style:''}><f>${esc(f)}</f><v>${value}</v></c>`);
}
function cargoPath(files){
 const wb=text(files['xl/workbook.xml']),rels=text(files['xl/_rels/workbook.xml.rels']);
 const tag=[...wb.matchAll(/<sheet\b[^>]*>/g)].map(m=>m[0]).find(s=>s.includes('name="물품 입고 내역"'));if(!tag)return null;
 const id=tag.match(/\br:id="([^"]+)"/)?.[1],rel=[...rels.matchAll(/<Relationship\b[^>]*>/g)].map(m=>m[0]).find(s=>s.includes(`Id="${id}"`));
 const p=rel?.match(/\bTarget="([^"]+)"/)?.[1]?.replace(/^\//,'');return p?.startsWith('xl/')?p:p?'xl/'+p:null;
}
function installSheet(files,xml){
 let wb=text(files['xl/workbook.xml']),rels=text(files['xl/_rels/workbook.xml.rels']),types=text(files['[Content_Types].xml']);
 const old=[...wb.matchAll(/<sheet\b[^>]*>/g)].map(m=>m[0]).find(t=>t.includes(`name="${SHEET}"`));let path;
 if(old){const id=old.match(/\br:id="([^"]+)"/)[1],rel=[...rels.matchAll(/<Relationship\b[^>]*>/g)].map(m=>m[0]).find(t=>t.includes(`Id="${id}"`));path=rel.match(/\bTarget="([^"]+)"/)[1].replace(/^\//,'');if(!path.startsWith('xl/'))path='xl/'+path;}
 else{
  const id='rIdLKDiscountIdentity',sheetId=1+Math.max(...[...wb.matchAll(/\bsheetId="(\d+)"/g)].map(m=>Number(m[1])));
  path='xl/worksheets/lk-discount-identity.xml';if(files[path])throw Error('Reserved discount worksheet path is already used');
  wb=wb.replace('</sheets>',`<sheet name="${SHEET}" sheetId="${sheetId}" state="veryHidden" r:id="${id}"/></sheets>`);
  rels=rels.replace('</Relationships>',`<Relationship Id="${id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/lk-discount-identity.xml"/></Relationships>`);
  types=types.replace('</Types>',`<Override PartName="/${path}" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`);
  files['xl/workbook.xml']=bytes(wb);files['xl/_rels/workbook.xml.rels']=bytes(rels);files['[Content_Types].xml']=bytes(types);
 }
 files[path]=bytes(xml);return path;
}
export function applyDiscountMatching(files){
 const originalHelper=files['xl/worksheets/lk-discount-identity.xml'];
 const source=discountWorkbookSource(files),cargo=cargoPath(files);
 if(!source||!cargo)return {version:DISCOUNT_MATCH_VERSION,applicable:false};
 const xml=text(files[cargo]);
 if(!/r="AJ6"/.test(xml)||!xml.includes('Row data'))return {version:DISCOUNT_MATCH_VERSION,applicable:false};
 if(source.rules.some(r=>r.refs.name[0]!=='H'||r.refs.phone[0]!=='K'))throw Error('Discount source columns require review');
 const cargoRows=[...xml.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>/g)].map(m=>Number(m[1])).filter(r=>r>=6),cargoLast=Math.max(...cargoRows),end=Math.max(256,cargoLast),helper=[];
 const sourceColumns=['A','B','C','D','E','F','G','H'],cargoColumns=['J','K','L','M','N','O','P','Q','R','S'];
 // Compile the same cell XML once, then substitute only this row sentinel.
 // Rebuilding and XML-escaping four large selectors for every Sea row exceeded
 // the Edge CPU budget. This changes no formula or output byte.
 const rowToken='__LK_DISCOUNT_ROW__',r=rowToken,formulas={};
 {
   formulas.A=memberBase(`'Row data'!H${r}`);formulas.B=`SUBSTITUTE(A${r},"/","|")`;formulas.C=`SUBSTITUTE(${memberBase(`'Row data'!J${r}`)},"/","|")`;formulas.D=phonesBase(`'Row data'!K${r}`);
   formulas.E=`IF(B${r}="||",0,${count(`A${r}`,'/')}+1)`;formulas.F=`MAX(0,${count(`B${r}`,'|')}-1)`;formulas.G=`MAX(0,${count(`D${r}`,'|')}-1)`;
   formulas.H=`IF('Row data'!AK${r}="",0,IF('Row data'!AG${r}="특별할인",2,1))`;
  }
  {
   const full=`IF('물품 입고 내역'!AL${r}=2,MID('물품 입고 내역'!E${r},FIND("/",'물품 입고 내역'!E${r})+1,LEN('물품 입고 내역'!E${r})),'물품 입고 내역'!E${r})`;
   formulas.J=`SUBSTITUTE(${memberBase(full)},"/","|")`;formulas.K=first(`J${r}`);formulas.L=last(`J${r}`);
   formulas.S=phonesBase(`'물품 입고 내역'!F${r}`);formulas.M=first(`S${r}`);formulas.N=last(`S${r}`);
   formulas.O=selector(r,'M',false);formulas.P=selector(r,'N',false);formulas.Q=selector(r,'M',true);formulas.R=selector(r,'N',true);
  }
  for(const f of Object.values(formulas))if(f.length>8192)throw Error('Discount formula exceeds Excel limit');
  const render=columns=>columns.map(c=>cell(`${c}${rowToken}`,formulas[c],['A','B','C','D','J','K','L','M','N','S'].includes(c)?'':0,['O','P','Q','R'].includes(c))).join('');
  const sourceTemplate=render(sourceColumns),cargoTemplate=render(cargoColumns);
 for(let r=1;r<=end;r++){
  // Excel repair reports removed formula/shared-formula records in this part.
  // Do not hand-serialize shared masters and dependent cells here. Every cell
  // carries its complete formula with an explicit, correctly typed cache.
  helper.push(`<row r="${r}">${(r>=3&&r<=256?sourceTemplate:'').replaceAll(rowToken,String(r))}${(r>=6&&r<=cargoLast?cargoTemplate:'').replaceAll(rowToken,String(r))}</row>`);
 }
 const helperXml=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:S${end}"/><sheetData>${helper.join('')}</sheetData></worksheet>`;
 const path=installSheet(files,helperXml);
 // Formula references are relative by cargo row. Existing styles, print areas,
 // delivery matching, customer IDs, notes, discount rates and VBA are untouched.
 let cargoChanged=false;
 files[cargo]=rewriteWorksheetRows(xml,(row,r)=>{
  if(r<6)return row;
  const before=row;
  row=putFormula(row,`AJ${r}`,`IF(OR(Y${r}="",AC${r}=1),0,MOD(MAX('${SHEET}'!O${r}:P${r}),1000))`,0);
  row=putFormula(row,`AO${r}`,`IF(OR(Y${r}="",AC${r}=1),0,MOD(MAX('${SHEET}'!Q${r}:R${r}),1000))`,0);
  cargoChanged ||= row!==before;return row;
 });
 // Raw/original downloads also call this function without the identity stage.
 // Do not retain Excel's old calculation ID with newly written zero caches.
 const beforeWorkbook=text(files['xl/workbook.xml']);
 const calculation='<calcPr calcId="0" calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>';
 let workbook=beforeWorkbook;
 if(/<calcPr\b/.test(workbook))workbook=workbook.replace(/<calcPr\b[^>]*\/?>(?:<\/calcPr>)?/,tag=>{
  for(const [key,value] of [['calcId','0'],['calcMode','auto'],['fullCalcOnLoad','1'],['forceFullCalc','1']]){
   const attr=new RegExp(`\\b${key}="[^"]*"`);tag=attr.test(tag)?tag.replace(attr,`${key}="${value}"`):tag.replace(/\/?>(?:<\/calcPr>)?$/,` ${key}="${value}"/>`);
  }
  return tag;
 });
 else {
  const next=workbook.search(/<(?:oleSize|customWorkbookViews|pivotCaches|smartTagPr|smartTagTypes|webPublishing|fileRecoveryPr|webPublishObjects|extLst)\b/);
  workbook=next<0?workbook.replace('</workbook>',calculation+'</workbook>'):workbook.slice(0,next)+calculation+workbook.slice(next);
 }
 files['xl/workbook.xml']=bytes(workbook);
 const changed=!originalHelper||text(originalHelper)!==helperXml||cargoChanged||workbook!==beforeWorkbook;
 return {version:DISCOUNT_MATCH_VERSION,applicable:true,changed,cargoRows:cargoRows.length,helper:path,...validateDiscountWorksheet(helperXml)};
}
