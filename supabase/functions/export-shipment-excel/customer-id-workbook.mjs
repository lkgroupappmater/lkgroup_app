// Targeted OOXML extension. Existing VBA, drawings, pricing and discount formulas
// remain in their original ZIP entries. The three new sheets use one data model
// shared with the authored spreadsheet prototype and the online exporter.
export const ID_WORKBOOK_VERSION='2026-09-27.customer-id-controls-v1';
const enc=new TextEncoder(),dec=new TextDecoder();
const xml=v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
const unxml=v=>String(v??'').replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&');
const txt=bytes=>dec.decode(bytes),bytes=text=>enc.encode(text);
export const nameKey=v=>String(v??'').normalize('NFC').replace(/\s/g,'').toLowerCase();
export function phoneKey(v){const d=String(v??'').replace(/\D/g,'');return /^00856\d{8,10}$/.test(d)?'0'+d.slice(5):/^856\d{8,10}$/.test(d)?'0'+d.slice(3):/^0082\d{8,11}$/.test(d)?'0'+d.slice(4):/^82\d{8,11}$/.test(d)?'0'+d.slice(2):d;}
export const phoneTokens=v=>[...new Set(String(v??'').split(/[/,;|\r\n]+/).map(phoneKey).filter(p=>/^\d{8,15}$/.test(p)))];
export const specialName=v=>/^(수취인\s*불명|비엔티엔\s*픽업|시내\s*픽업|운임\s*따로\s*지불)\s*\//i.test(String(v??'').trim());
export const baseName=v=>specialName(v)?String(v).slice(String(v).indexOf('/')+1).trim():String(v??'').trim();
export const customerCode=n=>'LK '+String(n).padStart(5,'0');
export const statementCode=(prefix,n,special=false)=>`${prefix} ${special?'9':''}${String(n).padStart(5,'0')}`;
export const identityKey=(n,special=false)=>`ID|${n}|${special?1:0}`;
const matchKey=(n,p)=>nameKey(baseName(n))+'|p'+phoneKey(p);
const col=n=>{let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;};
const formula=(f,value='')=>({formula:f,value});
export function sheetPath(files,name){
 const sheet=[...txt(files['xl/workbook.xml']).matchAll(/<sheet\b[^>]*\/>/g)].map(m=>m[0]).find(s=>unxml(s.match(/\bname="([^"]*)"/)?.[1])===name);
 if(!sheet)return null;const id=sheet.match(/r:id="([^"]*)"/)?.[1];
 const rel=[...txt(files['xl/_rels/workbook.xml.rels']).matchAll(/<Relationship\b[^>]*\/>/g)].map(m=>m[0]).find(r=>r.match(/\bId="([^"]*)"/)?.[1]===id);
 const path=rel?.match(/\bTarget="([^"]*)"/)?.[1];return path?(path.startsWith('/')?path.slice(1):'xl/'+path):null;
}
function sharedStrings(files){return files['xl/sharedStrings.xml']?[...txt(files['xl/sharedStrings.xml']).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m=>[...m[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(t=>unxml(t[1])).join('')):[];}
export function cellValue(cell,strings){if(/\bt="inlineStr"/.test(cell))return [...cell.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m=>unxml(m[1])).join('');const v=unxml(cell.match(/<v>([\s\S]*?)<\/v>/)?.[1]??'');return /\bt="s"/.test(cell)?strings[Number(v)]??'':v;}
function cell(ref,value,style=''){
 const s=style?` s="${style}"`:'';
 if(value&&typeof value==='object'&&'formula' in value)return `<c r="${ref}"${s}${typeof value.value==='number'?'':' t="str"'}><f>${xml(value.formula)}</f><v>${xml(value.value)}</v></c>`;
 return typeof value==='number'?`<c r="${ref}"${s}><v>${value}</v></c>`:`<c r="${ref}"${s} t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;
}
function sortCells(row){const cells=[...row.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)].map(m=>m[0]);const idx=c=>[...c.match(/\br="([A-Z]+)/)[1]].reduce((n,x)=>n*26+x.charCodeAt(0)-64,0);cells.sort((a,b)=>idx(a)-idx(b));return row.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,'').replace('</row>',cells.join('')+'</row>');}
function hideColumns(text,start,end){
 const cols=text.match(/<cols>([\s\S]*?)<\/cols>/)?.[1]??'';
 const pieces=[];for(const m of cols.matchAll(/<col\b[^>]*\/>/g)){const lo=Number(m[0].match(/min="(\d+)"/)[1]),hi=Number(m[0].match(/max="(\d+)"/)[1]);
  if(hi<start||lo>end){pieces.push({lo,xml:m[0]});continue;}
  if(lo<start)pieces.push({lo,xml:m[0].replace(/max="\d+"/,`max="${start-1}"`)});
  if(hi>end)pieces.push({lo:end+1,xml:m[0].replace(/min="\d+"/,`min="${end+1}"`)});
 }pieces.push({lo:start,xml:`<col min="${start}" max="${end}" width="14" hidden="1" customWidth="1"/>`});
 const replacement='<cols>'+pieces.sort((a,b)=>a.lo-b.lo).map(x=>x.xml).join('')+'</cols>';return cols?text.replace(/<cols>[\s\S]*?<\/cols>/,replacement):text.replace('<sheetData>',replacement+'<sheetData>');
}
function put(row,ref,value){const re=new RegExp(`<c\\b[^>]*\\br="${ref}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`);const found=row.match(re);const replacement=cell(ref,value,found?.[0].match(/\bs="(\d+)"/)?.[1]??'');return found?row.replace(re,()=>replacement):row.replace('</row>',replacement+'</row>');}
function newSheet(files,name,rows,{widths=[],inputColumns=[],hiddenColumns=[]}={}){
 let path=sheetPath(files,name),wb=txt(files['xl/workbook.xml']),rels=txt(files['xl/_rels/workbook.xml.rels']),types=txt(files['[Content_Types].xml']);
 if(!path){let id=1;while(files[`xl/worksheets/sheet${id}.xml`])id++;path=`xl/worksheets/sheet${id}.xml`;const relId=`rIdCustomer${id}`;
  const sheetId=1+Math.max(0,...[...wb.matchAll(/\bsheetId="(\d+)"/g)].map(m=>Number(m[1])));
  wb=wb.replace('</sheets>',`<sheet name="${xml(name)}" sheetId="${sheetId}" r:id="${relId}"/></sheets>`);
  rels=rels.replace('</Relationships>',`<Relationship Id="${relId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${id}.xml"/></Relationships>`);
  types=types.replace('</Types>',`<Override PartName="/${path}" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`);
  files['xl/workbook.xml']=bytes(wb);files['xl/_rels/workbook.xml.rels']=bytes(rels);files['[Content_Types].xml']=bytes(types);
 }
 const last=Math.max(6,rows.length),columns=Math.max(...rows.map(r=>r.length));
 const firstVisible=Array.from({length:columns},(_,i)=>i).find(i=>!hiddenColumns.includes(i+1))??0;
 const lastVisible=Array.from({length:columns},(_,i)=>i).filter(i=>!hiddenColumns.includes(i+1)).at(-1)??columns-1;
 const source=sheetPath(files,'고객 리스트');const original=source?txt(files[source]):'';
 const headerStyle=original.match(/<c\b[^>]*r="A3"[^>]*\bs="(\d+)"/)?.[1]??'0';
 const bodyStyle=original.match(/<c\b[^>]*r="B4"[^>]*\bs="(\d+)"/)?.[1]??'0';
 const validations=inputColumns.map(({column,values})=>`<dataValidation type="list" allowBlank="1" showErrorMessage="1" errorTitle="선택 확인" error="목록에서 선택하세요." sqref="${column}6:${column}${last}"><formula1>${xml('"'+values.join(',')+'"')}</formula1></dataValidation>`).join('');
 files[path]=bytes(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:${col(columns-1)}${last}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="5" topLeftCell="A6" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="22"/><cols>${Array.from({length:columns},(_,i)=>`<col min="${i+1}" max="${i+1}" width="${widths[i]??24}" customWidth="1"${hiddenColumns.includes(i+1)?' hidden="1"':''}/>`).join('')}</cols><sheetData>${rows.map((r,i)=>`<row r="${i+1}"${i<4?' ht="30" customHeight="1"':''}>${r.map((v,j)=>cell(col(j+(i<4?firstVisible:0))+(i+1),v,i<5?headerStyle:bodyStyle)).join('')}</row>`).join('')}</sheetData><autoFilter ref="A5:${col(columns-1)}${last}"/><mergeCells count="4">${[1,2,3,4].map(r=>`<mergeCell ref="${col(firstVisible)}${r}:${col(lastVisible)}${r}"/>`).join('')}</mergeCells>${validations?`<dataValidations count="${inputColumns.length}">${validations}</dataValidations>`:''}</worksheet>`);
 return path;
}
export function makeIdentityTables(context,{prefix,shipments=[],deliveryRefs=new Map(),deliveryRefFormulas=new Map(),cargoLast=1005,cargo=true}={}){
 const customers=context.customers.filter(c=>!specialName(c.name)&&!/수취인\s*불명/.test(c.name)),byId=new Map(customers.map(c=>[c.id,c]));
 const keys=new Map();const add=(key,name,phone,c)=>{if(c&&!keys.has(key))keys.set(key,[key,name,phone,c.customer_no,customerCode(c.customer_no)]);else if(c&&keys.get(key)?.[3]!==c.customer_no)keys.set(key,[key,name,phone,0,'연결 확인 필요']);};
 for(const c of customers)add(c.name_key+'|p'+c.phone_key,c.name,c.phone,c);
 for(const a of context.aliases??[])add(a.name_key+'|p'+a.phone_key,a.name_key,a.phone_key,byId.get(a.customer_registry_id));
 for(const s of context.sources??shipments)if(s.customer_no){const c=customers.find(c=>c.customer_no===s.customer_no);add(matchKey(s.source_name??s.consignee_name,s.source_phone??s.consignee_phone),s.source_name??s.consignee_name,s.source_phone??s.consignee_phone,c);}
 const ids=[['고객 ID 자동 매칭'],['기존 숫자 ID는 유지하며 LK 형식으로 표시합니다.'],['새 고객은 앱·웹 업로드 후 ID 발급 → 최신 자료 Excel 다운로드로 반영합니다.'],['연락처만 같은 고객과 보호된 복수 이름은 자동 통합하지 않습니다.'],['매칭 Key','등록 이름 / 별칭','등록 연락처','고객 번호','고객 고유 ID'],...[...keys.values()].sort((a,b)=>a[3]-b[3]||a[0].localeCompare(b[0]))];
 const controls=[['명세서 번호 관리'],['E열: 수동 번호 / F열: 잠금 선택 / G열: 고정할 번호'],['인쇄 전 G열 번호를 확인하고 F열을 잠금으로 선택하세요. 각 행에서 해제할 수 있습니다.'],['새로 입력한 화물은 앱·웹에 업로드하여 고객 ID를 받은 뒤 최신 자료를 내려받으세요.'],['매칭 Key','고객 고유 ID','고객명 / 구분','자동 번호','수동 지정 번호','번호 상태','고정 번호','적용 번호','화물 행 수','확인 사항','저장 당시 상태','승인 대기 번호 유지']];
 for(const c of customers){for(const special of [false,true]){
  const row=controls.length+1,key=identityKey(c.customer_no,special),group=shipments.filter(s=>s.customer_no===c.customer_no&&specialName(s.consignee_name)===special),numbers=[...new Set(group.map(s=>s.receipt_number).filter(Boolean))];
  if(numbers.length>1)throw new Error('같은 고객 ID에 서로 다른 명세서 번호가 있습니다. 번호 변경 승인을 완료하거나 고객 ID 구분을 확인하세요.');
  const current=numbers.length===1?numbers[0]:'',manual=group.find(s=>s.receipt_number_override)?.receipt_number_override??'',locked=group.some(s=>s.receipt_number_locked||s.data_locked),auto=statementCode(prefix,c.customer_no,special);
  const count=cargo?formula(`COUNTIF('물품 입고 내역'!$BE$6:$BE$${cargoLast},A${row})`,group.length):group.length;
  controls.push([key,customerCode(c.customer_no),c.name+(special?' / 별도 명세서':''),auto,manual,locked?'잠금':'자동',current||auto,formula(`IF(F${row}="잠금",IF(G${row}="","고정번호 입력",G${row}),IF(E${row}<>"",E${row},IF(L${row}=1,G${row},D${row})))`,locked?current||auto:manual||(context.preserveNumbers&&current)||auto),count,formula(`IF(I${row}=0,"",IF(COUNTIFS($H$6:$H$${6+customers.length*2},H${row},$I$6:$I$${6+customers.length*2},">0")>1,"번호 중복 확인",""))`),JSON.stringify({receipt_number:current||auto,manual,locked,fixed:current||auto}),context.preserveNumbers&&current?1:0]);
 }}
 const unknownGroup=shipments.filter(s=>!s.customer_no&&(s.recipient_unknown||/수취인\s*불명|unknown|미확인/i.test(s.consignee_name||'')));
 const ur=controls.length+1,unknownNumbers=[...new Set(unknownGroup.map(s=>s.receipt_number).filter(Boolean))];
 const un=unknownNumbers[0]||`${prefix} XX`,um=unknownGroup.find(s=>s.receipt_number_override)?.receipt_number_override||'',ul=unknownGroup.some(s=>s.receipt_number_locked||s.data_locked);
 controls.push(['UNKNOWN','고객 ID 미확정','수취인 불명 / 미확인',`${prefix} XX`,um,ul?'잠금':'자동',un,formula(`IF(F${ur}="잠금",G${ur},IF(E${ur}<>"",E${ur},D${ur}))`,ul?un:um||`${prefix} XX`),cargo?formula(`COUNTIF('물품 입고 내역'!$BE$6:$BE$${cargoLast},A${ur})`,unknownGroup.length):unknownGroup.length,'',JSON.stringify({receipt_number:un,manual:um,locked:ul,fixed:un}),0]);
 const pairs=new Map([...keys.values()].map(r=>[r[0],{name:r[1],phone:r[2]}]));
 for(const s of shipments)pairs.set(matchKey(s.consignee_name,s.consignee_phone),{name:s.consignee_name,phone:s.consignee_phone});
 const delivery=[['배송 매칭 확인'],['같은 연락처·한글/영문 이름 차이는 확인 후보입니다. F열에서 배송 프로필 번호를 선택해 확정합니다.'],['후보에 없는 배송지는 앱·웹 배송 목록에서 먼저 수정하세요. 고객 ID는 통합하지 않습니다.'],['확인 결과는 Excel 업로드 후 앱·웹 DB와 함께 반영됩니다.'],['매칭 Key','확정 배송 참조','자동 확인 참조','매칭 상태','확인 후보 (프로필 번호 / 고객명)','확인할 프로필 번호','입고 고객명','입고 연락처','후보 번호 목록','프로필 번호','참조','고객명','수령인','연락처','Type','업체','주소','자료 지문','전체 연락처 비교']];
 const profiles=context.deliveries??[];
 const reference=id=>deliveryRefFormulas.has(id)?formula(deliveryRefFormulas.get(id),deliveryRefs.get(id)||''):deliveryRefs.get(id)||'';
 for(const [key,pair] of pairs){
  const n=nameKey(baseName(pair.name)),phones=phoneTokens(pair.phone),matches=profiles.map(d=>{
   const names=[d.customer_name,d.alternate_name,d.company_name].map(nameKey).filter(Boolean),exact=names.includes(n),phone=phoneTokens(d.phone_display||d.phone).some(p=>phones.includes(p)),partial=n.length>=2&&names.some(x=>x.length>=2&&(x.includes(n)||n.includes(x)));
   const review=(context.reviews??[]).find(r=>r.delivery_profile_id===d.id&&r.name_key===nameKey(pair.name)&&r.phone_key===phoneKey(pair.phone)&&r.profile_fingerprint===d.fingerprint);
   return {d,exact,phone,partial,review};
  }).filter(m=>m.review?.approved!==false&&(m.exact||m.phone||m.partial||m.review?.approved));
  const confirmed=matches.filter(m=>m.review?.approved===true||m.exact&&m.phone).sort((a,b)=>Number(b.review?.approved===true)-Number(a.review?.approved===true)||Number(b.d.delivery_type==='province')-Number(a.d.delivery_type==='province')||Number(b.d.preferred)-Number(a.d.preferred)||Number(b.d.source_row||b.d.source_no||0)-Number(a.d.source_row||a.d.source_no||0)||b.d.id-a.d.id)[0];
  const row=delivery.length+1,ref=confirmed?deliveryRefs.get(confirmed.d.id)||'':'',candidates=matches.map(m=>m.d);
  const fp=profiles[row-6],profile=fp?[fp.id,reference(fp.id),fp.customer_name,fp.alternate_name,fp.phone_display||fp.phone,fp.delivery_type,fp.local_company,fp.destination_address,fp.fingerprint||'',phoneTokens(fp.phone_display||fp.phone).map(p=>'|p'+p+'|').join('')]:[];
  delivery.push([key,formula(`IF(F${row}="",C${row},IF(ISNUMBER(SEARCH("|"&F${row}&"|",I${row})),IFERROR(INDEX($K$6:$K$${5+profiles.length},MATCH(F${row},$J$6:$J$${5+profiles.length},0)),""),""))`,ref),confirmed?reference(confirmed.d.id):'',formula(`IF(B${row}<>"","확정",IF(E${row}<>"","확인 필요","일반"))`,ref?'확정':candidates.length?'확인 필요':'일반'),candidates.map(d=>`${d.id} / ${d.customer_name} / ${d.alternate_name} / ${d.local_company}`).join('\n'),'',pair.name,pair.phone,candidates.map(d=>'|'+d.id+'|').join(''),...profile]);
 }
 for(let i=delivery.length-5;i<profiles.length;i++){const d=profiles[i];delivery.push(['','','','','','','','','',d.id,reference(d.id),d.customer_name,d.alternate_name,d.phone_display||d.phone,d.delivery_type,d.local_company,d.destination_address,d.fingerprint||'',phoneTokens(d.phone_display||d.phone).map(p=>'|p'+p+'|').join('')]);}
 return {ids,controls,delivery};
}
const strip=(expr,tokens)=>tokens.reduce((out,t)=>`SUBSTITUTE(${out}&"",${typeof t==='string'?JSON.stringify(t):t.f},"")`,expr);
export function identityCargoFormulas(r,last,idLast,controlLast,deliveryLast,prefix){
 const head=`SUBSTITUTE(TRIM(LEFT(E${r},FIND("/",E${r}&"/")-1))," ","")`;
 const special=`AND(ISNUMBER(FIND("/",E${r})),OR(${['수취인불명','비엔티엔픽업','시내픽업','운임따로지불'].map(v=>head+'="'+v+'"').join(',')}))`;
 const rawPhone=strip(`"p"&F${r}&""`,[' ','-','(',')','+','/','.',',',';',"'",{f:'CHAR(160)'},{f:'CHAR(9)'},{f:'CHAR(10)'},{f:'CHAR(13)'}]);
 const rawPhoneRef=`BI${r}`;
 const phone=`IF(AND(LEFT(${rawPhoneRef},6)="p00856",LEN(${rawPhoneRef})>=14,LEN(${rawPhoneRef})<=16),"p0"&MID(${rawPhoneRef},7,99),IF(AND(LEFT(${rawPhoneRef},4)="p856",LEN(${rawPhoneRef})>=12,LEN(${rawPhoneRef})<=14),"p0"&MID(${rawPhoneRef},5,99),IF(AND(LEFT(${rawPhoneRef},5)="p0082",LEN(${rawPhoneRef})>=13,LEN(${rawPhoneRef})<=16),"p0"&MID(${rawPhoneRef},6,99),IF(AND(LEFT(${rawPhoneRef},3)="p82",LEN(${rawPhoneRef})>=11,LEN(${rawPhoneRef})<=14),"p0"&MID(${rawPhoneRef},4,99),${rawPhoneRef}))))`;

 const fullName=`IF(BD${r}=1,TRIM(MID(E${r},FIND("/",E${r})+1,LEN(E${r}))),E${r})`;
 return {
 BI:rawPhone,BA:`LOWER(${strip(fullName,[' ',{f:'CHAR(160)'},{f:'CHAR(9)'},{f:'CHAR(10)'},{f:'CHAR(13)'}])})`,BB:phone,BD:`IF(${special},1,0)`,
 BC:`IFERROR(IF(COUNTIF('고객 ID'!$A$6:$A$${idLast},BA${r}&"|"&BB${r})=1,VLOOKUP(BA${r}&"|"&BB${r},'고객 ID'!$A$6:$E$${idLast},4,FALSE),0),0)`,
 BE:`IF(AND(E${r}="",F${r}=""),"",IF(BC${r}>0,"ID|"&BC${r}&"|"&BD${r},IF(AC${r}=1,"UNKNOWN","SRC|"&BA${r}&"|"&BB${r})))`,
 R:`IF(AH${r}="",IF(ISNUMBER(SEARCH("확인 필요",BF${r})),BF${r},""),IF(LEFT(AH${r},1)="L",INDEX(지방배송!$Y:$Y,VALUE(MID(AH${r},3,10))),INDEX(시내배송!$Y:$Y,VALUE(MID(AH${r},3,10)))))`,
 Y:`BE${r}`,N:`IF(BE${r}="","",IF(OR(BC${r}>0,AC${r}=1),IFERROR(VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$H$${controlLast},8,FALSE),"ID 확인 필요"),IF(AND(BH${r}=BA${r}&"|"&BB${r},BG${r}<>""),BG${r},"ID 확인 필요")))`,
 Z:`IF(Y${r}="","",IF(BD${r}=1,6,IF(AC${r}=1,5,IF(ISNUMBER(SEARCH("지방배송",R${r}&"")),1,IF(ISNUMBER(SEARCH("시내배송",R${r}&"")),2,IF(OR(SUBSTITUTE(E${r}," ","")="박성호대표",SUBSTITUTE(E${r}," ","")="박성호대표님"),4,3))))))`,
 AB:`IF(AA${r}<>1,"",COUNTIFS($AA$6:$AA$${last},1,$Z$6:$Z$${last},"<"&Z${r})+COUNTIFS($AA$6:$AA$${last},1,$Z$6:$Z$${last},Z${r},$BC$6:$BC$${last},"<"&BC${r})+COUNTIFS($AA$6:AA${r},1,$Z$6:Z${r},Z${r},$BC$6:BC${r},BC${r}))`,
 AH:`IF(BE${r}="","",IFERROR(VLOOKUP(BA${r}&"|"&BB${r},'배송 매칭 확인'!$A$6:$D$${deliveryLast},2,FALSE),""))`,
 BF:`IF(BE${r}="","",IF(AND(BC${r}=0,AC${r}=0),IF(COUNTIF('배송 매칭 확인'!$S$6:$S$${deliveryLast},"*|"&BB${r}&"|*")>0,"고객 ID · 배송 매칭 확인 필요","고객 ID 확인 필요"),IFERROR(IF(VLOOKUP(BA${r}&"|"&BB${r},'배송 매칭 확인'!$A$6:$D$${deliveryLast},4,FALSE)="확인 필요","배송 매칭 확인 필요",""),"")))`,
 };
}

export function applyCustomerIdWorkbook(files,context,{prefix='LKS',shipments=[],base=false}={}){
 const strings=sharedStrings(files),cargoPath=sheetPath(files,'물품 입고 내역'),deliveryRefs=new Map(),deliveryRefFormulas=new Map();
 // Refresh only editable delivery input columns, keeping existing calculation,
 // address-selection, validation and print sections intact.
 for(const [name,type,tag] of [['지방배송','province','L'],['시내배송','city','C']]){
  const path=sheetPath(files,name);if(!path)continue;
  const profiles=(context.deliveries??[]).filter(d=>d.delivery_type===type);
  let text=txt(files[path]);const physical=[...text.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)].map(m=>({n:Number(m[1]),xml:m[0]}));
  const read=(row,c)=>cellValue(row.xml.match(new RegExp(`<c\\b[^>]*\\br="${c}${row.n}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`))?.[0]??'',strings);
  const blocks=[];let current=null,lastInput=2;
  for(const row of physical){if(row.n<3||row.n>800)continue;const number=Number(read(row,'A'));
   if(number>0){current={number,first:row,rows:[]};blocks.push(current);}
   if(current)current.rows.push(row);
   if(['A','B','D','E','F','G'].some(c=>read(row,c)))lastInput=row.n;
  }
  const updates=new Map(),set=(n,c,v)=>{if(!updates.has(n))updates.set(n,{});updates.get(n)[c]=v;};
  for(const d of profiles){
   const number=d.original_source_no||((Number(d.source_no)>=10000&&Number(d.source_no)<20000)?Number(d.source_no)-10000:Number(d.source_no));
   const numbered=blocks.filter(b=>b.number===number);
   let block=blocks.find(b=>matchKey(read(b.first,'B'),read(b.first,'E'))===matchKey(d.customer_name,d.phone_display||d.phone))||(numbered.length===1?numbered[0]:null);
   if(!block){const row=physical.find(r=>r.n>lastInput&&r.n<=800);if(!row)throw new Error(`${name}: 배송 입력 공간이 부족합니다.`);lastInput=row.n;block={number:number||lastInput,first:row,rows:[row]};blocks.push(block);}
   // Preserve every other carrier/address alternative already in the BASE.
   const choices=block.rows.filter(r=>read(r,'F')||read(r,'G')||r.n===block.first.n);
   const chosen=choices.find(r=>nameKey(read(r,'F'))===nameKey(d.local_company)&&read(r,'G')===String(d.destination_address??''))||choices.find(r=>d.local_company&&nameKey(read(r,'F'))===nameKey(d.local_company))||block.rows.find(r=>read(r,'H')==='사용')||block.first;
   for(const [c,v] of Object.entries({A:block.number,B:d.customer_name,C:d.paid_by,D:d.alternate_name,E:d.phone_display||d.phone}))set(block.first.n,c,v);
   set(chosen.n,'F',d.local_company);set(chosen.n,'G',d.destination_address);
   // H remains the workbook's existing address selector, with one active row.
   for(const row of block.rows)if(read(row,'F')||read(row,'G')||row.n===chosen.n)set(row.n,'H',row.n===chosen.n?'사용':'');
   deliveryRefs.set(d.id,`${tag}|${chosen.n}`);
   const first=block.first.n,end=Math.max(...choices.map(r=>r.n));
   deliveryRefFormulas.set(d.id,`IFERROR("${tag}|"&LOOKUP(2,1/('${name}'!$AD${first}:$AD${end}=1),ROW('${name}'!$AD${first}:$AD${end})),"")`);
  }
  text=text.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>{for(const [c,v] of Object.entries(updates.get(Number(n))??{}))row=put(row,c+n,v);return sortCells(row);});
  files[path]=bytes(text);
 }
 let cargoXml=cargoPath?txt(files[cargoPath]):'',last=Math.max(6,...[...cargoXml.matchAll(/<c\b[^>]*r="AB(\d+)"/g)].map(m=>Number(m[1])));
 const tables=makeIdentityTables(context,{prefix,shipments,deliveryRefs,deliveryRefFormulas,cargoLast:last,cargo:!!cargoPath});
 newSheet(files,'고객 ID',tables.ids,{widths:[48,32,28,15,18],hiddenColumns:[1]});
 newSheet(files,'명세서 번호 관리',tables.controls,{widths:[22,18,34,20,20,14,20,20,14,22],hiddenColumns:[1,11,12],inputColumns:[{column:'F',values:['자동','잠금']}]});
 newSheet(files,'배송 매칭 확인',tables.delivery,{widths:[45,18,18,18,70,20,30,26,20,16,14,28,28,24,16,18,50,35],hiddenColumns:[1,2,3,9,10,11,12,13,14,15,16,17,18,19]});
 if(!cargoPath||last<=6)return {tables,applied:false,version:ID_WORKBOOK_VERSION};
 const idByKey=new Map(tables.ids.slice(5).map(r=>[r[0],r[3]]));
 const controlByKey=new Map(tables.controls.slice(5).map(r=>[r[0],r[7].value]));
 const deliveryByKey=new Map(tables.delivery.slice(5).map(r=>[r[0],r]));
 const summaries=new Map();
 cargoXml=cargoXml.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>{
  const r=Number(n);if(r<6||r>last)return row;
  const get=c=>cellValue(row.match(new RegExp(`<c\\b[^>]*\\br="${c}${r}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`))?.[0]??'',strings);
  const name=get('E'),phone=get('F'),key=matchKey(name,phone),id=idByKey.get(key)||0,special=specialName(name),control=id?identityKey(id,special):get('AC')==='1'?'UNKNOWN':'',receipt=control?controlByKey.get(control):name||phone?get('N')||'ID 확인 필요':'',delivery=deliveryByKey.get(key);
  const priorY=get('Y'),cache={R:get('R'),BG:get('BG')||get('N'),BH:get('BH')||key,BI:'p'+String(phone??'').replace(/\D/g,''),BA:nameKey(baseName(name)),BB:'p'+phoneKey(phone),BC:id,BD:special?1:0,BE:control||(!name&&!phone?'':get('AC')==='1'?'UNKNOWN':'SRC|'+key),Y:control||priorY,N:receipt,AH:delivery?.[1]?.value??'',BF:id?(delivery?.[3]?.value==='확인 필요'?'배송 매칭 확인 필요':''):name&&get('AC')!=='1'?'고객 ID 확인 필요':''};
  row=put(row,'BG'+r,cache.BG);row=put(row,'BH'+r,cache.BH);
  if(!cache.AH)cache.R=cache.BF;
  const formulas=identityCargoFormulas(r,last,tables.ids.length,tables.controls.length,tables.delivery.length,prefix);
  for(const [column,f] of Object.entries(formulas))row=put(row,column+r,formula(f,cache[column]??''));
  if(receipt&&!summaries.has(receipt))summaries.set(receipt,{id,receipt,priority:special?6:receipt.endsWith(' XX')?5:delivery?.[1]?.value?.startsWith('L|')?1:delivery?.[1]?.value?.startsWith('C|')?2:/^박성호\s*대표님?$/.test(name)?4:3});
  return sortCells(row);
 });
 // Keep appended helper cells within the explicit worksheet dimension.
 cargoXml=cargoXml.replace(/<dimension\b[^>]*\/>/,`<dimension ref="A1:BI${Math.max(last,1010)}"/>`);
 cargoXml=hideColumns(cargoXml,53,61);
 files[cargoPath]=bytes(cargoXml);
 const customerPath=sheetPath(files,'고객 리스트');
 if(customerPath){let i=0;const ordered=[...summaries.values()].sort((a,b)=>a.priority-b.priority||a.id-b.id);let text=txt(files[customerPath]);
  text=text.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>{
   const r=Number(n),a=row.match(new RegExp(`<c\\b[^>]*r="A${r}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`))?.[0]??'';
   // A formula identifies a previously upgraded slot; preserve the original
   // fixed-zone reference table below the existing customer list.
   if(!/^LK[A-Z]*\s+(\d+|XX)$/i.test(cellValue(a,strings))&&!a.includes("MATCH("))return row;
   i++;return put(row,`A${r}`,formula(`IFERROR(INDEX('물품 입고 내역'!$N$6:$N$${last},MATCH(${i},'물품 입고 내역'!$AB$6:$AB$${last},0)),"")`,ordered[i-1]?.receipt??''));
  });
  if(ordered.length>i)throw new Error(`고객 리스트의 기존 ${i}개 명세서 공간을 초과했습니다. 표 공간을 확인하세요.`);
  files[customerPath]=bytes(text);
 }
 return {tables,applied:true,version:ID_WORKBOOK_VERSION};
}
