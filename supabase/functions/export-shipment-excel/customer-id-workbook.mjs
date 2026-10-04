// Targeted OOXML extension. Existing VBA, drawings, pricing and discount formulas
// remain in their original ZIP entries. The three new sheets use one data model
// shared with the authored spreadsheet prototype and the online exporter.
import {unknownPrefixZone,unknownZoneCondition} from './unknown-zone.mjs';
import {rewriteWorksheetRows,worksheetIdentityRange} from './worksheet-rows.mjs';
import {captureSharedFormulaMasters,restoreSharedFormulaMasters,recoverDeliverySelectorMasters} from './workbook-integrity.mjs';
export const ID_WORKBOOK_VERSION='2026-09-28.merged-delivery-id-v8';
const enc=new TextEncoder(),dec=new TextDecoder();
const xml=v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
const unxml=v=>String(v??'').replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&');
const txt=bytes=>dec.decode(bytes),bytes=text=>enc.encode(text);
export const nameKey=v=>String(v??'').normalize('NFC').replace(/\s/g,'').toLowerCase();
export function phoneKey(v){const d=String(v??'').replace(/\D/g,'');return /^00856\d{8,10}$/.test(d)?'0'+d.slice(5):/^856\d{8,10}$/.test(d)?'0'+d.slice(3):/^0082\d{8,11}$/.test(d)?'0'+d.slice(4):/^82\d{8,11}$/.test(d)?'0'+d.slice(2):d;}
export const phoneTokens=v=>[...new Set(String(v??'').split(/[/,;|\r\n]+/).map(phoneKey).filter(p=>/^\d{8,15}$/.test(p)))];
export const specialName=v=>/^(수취인\s*불명|비엔티엔\s*픽업|시내\s*픽업|운임\s*따로\s*지불)\s*\//i.test(String(v??'').trim());
export const baseName=v=>specialName(v)?String(v).slice(String(v).indexOf('/')+1).trim():String(v??'').trim();
export const customerCode=n=>'LK '+String(n).padStart(4,'0');
export const statementCode=(prefix,n,special=false)=>`${prefix} ${special?'9':''}${String(n).padStart(special?3:4,'0')}`;
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
const columnIndexes=new Map();
const columnIndex=ref=>{if(columnIndexes.has(ref))return columnIndexes.get(ref);let n=0;for(const c of ref)n=n*26+c.charCodeAt(0)-64;columnIndexes.set(ref,n);return n;};
function parsedCells(row){return new Map([...row.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)].map(m=>[m[0].match(/\br="([A-Z]+)\d+"/)[1],m[0]]));}
function patchRow(row,n,values,existingCells){
 if(!values||!Object.keys(values).length)return row;
 const cells=existingCells??parsedCells(row);
 for(const [c,v] of Object.entries(values))cells.set(c,cell(c+n,v,cells.get(c)?.match(/\bs="(\d+)"/)?.[1]??''));
 const ordered=[...cells].sort((a,b)=>columnIndex(a[0])-columnIndex(b[0])).map(x=>x[1]).join('');
 return row.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,'').replace('</row>',ordered+'</row>');
}
function readRow(row,c,strings){
 row.values??=new Map();if(row.values.has(c))return row.values.get(c);
 row.cells??=parsedCells(row.xml);const value=cellValue(row.cells.get(c)??'',strings);row.values.set(c,value);return value;
}
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
const recoveredOrder=rows=>Math.min(...rows.filter(r=>unknownPrefixZone(r.consignee_name)&&Number(r.recipient_recovered_order)>0).map(r=>Number(r.recipient_recovered_order)),Infinity);
export function makeIdentityTables(context,{prefix,shipments=[],deliveryRefs=new Map(),deliveryRefFormulas=new Map(),cargoLast=1005,cargo=true}={}){
 const customers=context.customers.filter(c=>!specialName(c.name)&&!/수취인\s*불명/.test(c.name)),byId=new Map(customers.map(c=>[c.id,c])),byNumber=new Map(customers.map(c=>[c.customer_no,c]));
 const keys=new Map();const add=(key,name,phone,c)=>{if(c&&!keys.has(key))keys.set(key,[key,name,phone,c.customer_no,customerCode(c.customer_no)]);else if(c&&keys.get(key)?.[3]!==c.customer_no)keys.set(key,[key,name,phone,0,'연결 확인 필요']);};
 for(const c of customers)add(c.name_key+'|p'+c.phone_key,c.name,c.phone,c);
 for(const a of context.aliases??[])add(a.name_key+'|p'+a.phone_key,a.name_key,a.phone_key,byId.get(a.customer_registry_id));
 for(const s of context.sources??shipments)if(s.customer_no){const c=byNumber.get(s.customer_no);add(matchKey(s.source_name??s.consignee_name,s.source_phone??s.consignee_phone),s.source_name??s.consignee_name,s.source_phone??s.consignee_phone,c);}
 const ids=[['고객 ID 자동 매칭'],['기존 숫자 ID는 유지하며 LK 형식으로 표시합니다.'],['신규 고객 ID 시트에서 빈 번호를 임시 배정합니다. 업로드 후 DB 확정 ID로 최신 자료를 받으세요.'],['연락처만 같은 고객과 보호된 복수 이름은 자동 통합하지 않습니다.'],['매칭 Key','등록 이름 / 별칭','등록 연락처','고객 번호','고객 고유 ID'],...[...keys.values()].sort((a,b)=>a[3]-b[3]||a[0].localeCompare(b[0]))];
 const legacy=context.numberingMode==='legacy';
 const controls=[['명세서 번호 관리'],['E열: 수동 번호 / F열: 잠금 선택 / G열: 고정할 번호'],['인쇄 전 G열 번호를 확인하고 F열을 잠금으로 선택하세요. 각 행에서 해제할 수 있습니다.'],['신규 고객의 임시 번호는 업로드 후 DB가 확정합니다. 임시 명세서는 확정·인쇄 전에 최신 자료로 교체하세요.'],['매칭 Key','고객 고유 ID','고객명 / 구분','자동 번호','수동 지정 번호','번호 상태','고정 번호','적용 번호','화물 행 수','확인 사항','저장 당시 상태','승인 대기 번호 유지']];
 if(!legacy){for(const c of customers){for(const special of [false,true]){
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
 }else{
  controls[2]=['기존 발행 항차: 명세서 번호는 유지하고 현재 고객 ID는 별도로 연결합니다.'];
  controls[3]=['과거 명세서는 고객 ID가 같아도 합치지 않습니다. 번호 변경은 수동 지정과 기존 승인 절차를 따릅니다.'];
  controls[4][3]='기존 발행 번호';controls[4].push('기존 번호 순서');
  const groups=new Map();for(const row of shipments){const number=String(row.receipt_number??'').trim();if(!number)continue;if(!groups.has(number))groups.set(number,[]);groups.get(number).push(row);}
  const ordered=[...groups].sort((a,b)=>{const ar=recoveredOrder(a[1]),br=recoveredOrder(b[1]);if(Number.isFinite(ar)!==Number.isFinite(br))return Number.isFinite(ar)?1:-1;return Number.isFinite(ar)?ar-br:a[0].localeCompare(b[0],'en',{numeric:true});});
  for(const [number,group] of ordered){
   const r=controls.length+1,locked=group.some(s=>s.receipt_number_locked||s.data_locked),manual=group.find(s=>s.receipt_number_override)?.receipt_number_override||'';
   const codes=[...new Set(group.filter(s=>s.customer_no).map(s=>customerCode(s.customer_no)))].join(', '),names=[...new Set(group.map(s=>s.consignee_name||''))].join(' / ');
   controls.push(['LEGACY|'+number,codes||'고객 ID 미확정',names,number,manual,locked?'잠금':'자동',number,formula(`IF(F${r}="잠금",IF(G${r}="","고정번호 입력",G${r}),IF(E${r}<>"",E${r},D${r}))`,number),cargo?formula(`COUNTIF('물품 입고 내역'!$BE$6:$BE$${cargoLast},A${r})`,group.length):group.length,formula(`IF(I${r}=0,"",IF(COUNTIFS($H$6:$H$${5+ordered.length},H${r},$I$6:$I$${5+ordered.length},">0")>1,"번호 중복 확인",""))`),JSON.stringify({receipt_number:number,manual,locked,fixed:number}),1,r-5]);
  }
 }
 controls[4][13]='확인 순서';
 controls[3]=[String(controls[3]?.[0]||'')+' / 오프라인에서 새로 확인한 건은 N열에 기존 최댓값 다음 순서를 입력하세요.'];
 for(const row of controls.slice(5)){
  const group=shipments.filter(x=>legacy?String(x.receipt_number||'')===row[3]:identityKey(x.customer_no,specialName(x.consignee_name))===row[0]);
  const order=recoveredOrder(group);row[13]=Number.isFinite(order)?order:'';
  row[10]=JSON.stringify({...JSON.parse(row[10]),recovered_order:row[13]||null});
 }
 if(legacy){
  controls[4][14]='확인 정렬 Key';
  for(let i=5;i<controls.length;i++){
   const r=i+1,row=controls[i],rank=row[12];
   row[14]=formula(`IF(N${r}>0,1000000000000+N${r},${rank})`,row[13]?1e12+row[13]:rank);
   row[12]=formula(`COUNTIF($O$6:$O$${controls.length},"<"&O${r})+COUNTIF($O$6:O${r},O${r})`,rank);
  }
 }
 const pairs=new Map([...keys.values()].map(r=>[r[0],{name:r[1],phone:r[2]}]));
 for(const s of shipments)pairs.set(matchKey(s.consignee_name,s.consignee_phone),{name:s.consignee_name,phone:s.consignee_phone});
 const delivery=[['배송 매칭 확인'],['같은 연락처·한글/영문 이름 차이는 확인 후보입니다. F열에서 배송 프로필 번호를 선택해 확정합니다.'],['후보에 없는 배송지는 앱·웹 배송 목록에서 먼저 수정하세요. 고객 ID는 통합하지 않습니다.'],['확인 결과는 Excel 업로드 후 앱·웹 DB와 함께 반영됩니다.'],['매칭 Key','확정 배송 참조','자동 확인 참조','매칭 상태','확인 후보 (프로필 번호 / 고객명)','확인할 프로필 번호','입고 고객명','입고 연락처','후보 번호 목록','프로필 번호','참조','고객명','수령인','연락처','Type','업체','주소','자료 지문','전체 연락처 비교']];
 const profiles=context.deliveries??[];
 // Normalize each profile once, retaining the same matching and review rules.
 // Only complete registry/alias pairs establish identity. Do not infer it from
 // a shared phone, a recipient token, or an unreviewed source association.
 const deliveryIdentityKeys=new Map();
 const addDeliveryIdentity=(key,id)=>{if(!deliveryIdentityKeys.has(key))deliveryIdentityKeys.set(key,id);else if(deliveryIdentityKeys.get(key)!==id)deliveryIdentityKeys.set(key,null);};
 for(const c of customers)if(c.name_key&&c.phone_key)addDeliveryIdentity(c.name_key+'|p'+c.phone_key,c.id);
 for(const a of context.aliases??[])if(a.name_key&&a.phone_key&&byId.has(a.customer_registry_id))addDeliveryIdentity(a.name_key+'|p'+a.phone_key,a.customer_registry_id);
 const deliveryIdentity=(name,phone)=>deliveryIdentityKeys.get(matchKey(name,phone));
 const normalizedProfiles=profiles.map(d=>({d,names:[d.customer_name,d.alternate_name,d.company_name].map(nameKey).filter(Boolean),phones:phoneTokens(d.phone_display||d.phone),customerId:deliveryIdentity(d.customer_name,d.phone_display||d.phone)}));
 const profileCounts=new Map();
 for(const p of normalizedProfiles)if(p.customerId)profileCounts.set(p.customerId,(profileCounts.get(p.customerId)||0)+1);
 const reviewsByPair=new Map();
 for(const review of context.reviews??[]){const key=JSON.stringify([review.name_key,review.phone_key]);if(!reviewsByPair.has(key))reviewsByPair.set(key,[]);reviewsByPair.get(key).push(review);}
 const reference=id=>deliveryRefFormulas.has(id)?formula(deliveryRefFormulas.get(id),deliveryRefs.get(id)||''):deliveryRefs.get(id)||'';
 for(const [key,pair] of pairs){
  const n=nameKey(baseName(pair.name)),phones=phoneTokens(pair.phone),customerId=deliveryIdentity(pair.name,pair.phone),reviews=reviewsByPair.get(JSON.stringify([nameKey(pair.name),phoneKey(pair.phone)]))??[],matches=normalizedProfiles.map(({d,names,phones:profilePhones,customerId:profileCustomerId})=>{
   const exact=names.includes(n),phone=profilePhones.some(p=>phones.includes(p)),partial=n.length>=2&&names.some(x=>x.length>=2&&(x.includes(n)||n.includes(x)));
   const review=reviews.find(r=>r.delivery_profile_id===d.id&&r.profile_fingerprint===d.fingerprint);
   const sameCustomer=!!customerId&&customerId===profileCustomerId;
   return {d,exact,phone,partial,review,sameCustomer,uniqueCustomer:sameCustomer&&profileCounts.get(customerId)===1};
  }).filter(m=>m.review?.approved!==false&&(m.exact||m.phone||m.partial||m.sameCustomer||m.review?.approved));
  const confirmed=matches.filter(m=>m.review?.approved===true||m.exact&&m.phone||m.uniqueCustomer).sort((a,b)=>Number(b.review?.approved===true)-Number(a.review?.approved===true)||Number(b.review?.approved===true||b.exact&&b.phone)-Number(a.review?.approved===true||a.exact&&a.phone)||Number(b.d.delivery_type==='province')-Number(a.d.delivery_type==='province')||Number(b.d.preferred)-Number(a.d.preferred)||Number(b.d.source_row||b.d.source_no||0)-Number(a.d.source_row||a.d.source_no||0)||b.d.id-a.d.id)[0];
  const row=delivery.length+1,ref=confirmed?deliveryRefs.get(confirmed.d.id)||'':'',candidates=matches.map(m=>m.d);
  const fp=profiles[row-6],profile=fp?[fp.id,reference(fp.id),fp.customer_name,fp.alternate_name,fp.phone_display||fp.phone,fp.delivery_type,fp.local_company,fp.destination_address,fp.fingerprint||'',phoneTokens(fp.phone_display||fp.phone).map(p=>'|p'+p+'|').join('')]:[];
  delivery.push([key,formula(`IF(F${row}="",C${row},IF(ISNUMBER(SEARCH("|"&F${row}&"|",I${row})),IFERROR(INDEX($K$6:$K$${5+profiles.length},MATCH(F${row},$J$6:$J$${5+profiles.length},0)),""),""))`,ref),confirmed?reference(confirmed.d.id):'',formula(`IF(B${row}<>"","확정",IF(E${row}<>"","확인 필요","일반"))`,ref?'확정':candidates.length?'확인 필요':'일반'),candidates.map(d=>`${d.id} / ${d.customer_name} / ${d.alternate_name} / ${d.local_company}`).join('\n'),'',pair.name,pair.phone,candidates.map(d=>'|'+d.id+'|').join(''),...profile]);
 }
 for(let i=delivery.length-5;i<profiles.length;i++){const d=profiles[i];delivery.push(['','','','','','','','','',d.id,reference(d.id),d.customer_name,d.alternate_name,d.phone_display||d.phone,d.delivery_type,d.local_company,d.destination_address,d.fingerprint||'',phoneTokens(d.phone_display||d.phone).map(p=>'|p'+p+'|').join('')]);}
 return {ids,controls,delivery,unusedNumbers:context.unused_customer_numbers??[]};
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
 BK:provisionalNumber(r),
 BL:`IF(BC${r}>0,"LK "&TEXT(BC${r},"0000"),IF(BK${r}>0,"LK "&TEXT(BK${r},"0000")&" (임시)",""))`,
 BJ:`IF(AND(BD${r}=1,${unknownZoneCondition(`E${r}`)}),IFERROR(IF(VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$N$${controlLast},14,FALSE)>0,VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$N$${controlLast},14,FALSE),1000000000000+ROW()),1000000000000+ROW()),IF(BC${r}>0,BC${r},BK${r}))`,
 BI:rawPhone,BA:`LOWER(${strip(fullName,[' ',{f:'CHAR(160)'},{f:'CHAR(9)'},{f:'CHAR(10)'},{f:'CHAR(13)'}])})`,BB:phone,BD:`IF(${special},1,0)`,
 BC:`IFERROR(IF(COUNTIF('고객 ID'!$A$6:$A$${idLast},BA${r}&"|"&BB${r})=1,VLOOKUP(BA${r}&"|"&BB${r},'고객 ID'!$A$6:$E$${idLast},4,FALSE),0),0)`,
 BE:`IF(AND(E${r}="",F${r}=""),"",IF(BC${r}>0,"ID|"&BC${r}&"|"&BD${r},IF(AC${r}=1,"UNKNOWN","SRC|"&BA${r}&"|"&BB${r}&"|"&BD${r})))`,
 R:`IF(AH${r}="",IF(ISNUMBER(SEARCH("확인 필요",BF${r})),BF${r},""),IF(LEFT(AH${r},1)="L",INDEX(지방배송!$Y:$Y,VALUE(MID(AH${r},3,10))),INDEX(시내배송!$Y:$Y,VALUE(MID(AH${r},3,10)))))`,
 Y:`BE${r}`,N:`IF(BE${r}="","",IF(OR(BC${r}>0,AC${r}=1),IFERROR(VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$H$${controlLast},8,FALSE),"ID 확인 필요"),IF(AND(BH${r}=BA${r}&"|"&BB${r},BG${r}<>""),BG${r},IF(BK${r}>0,${provisionalStatement(r,prefix)},"ID 확인 필요"))))`,
 Z:`IF(Y${r}="","",IF(BD${r}=1,IF(${unknownZoneCondition(`E${r}`)},7,6),IF(AC${r}=1,5,IF(ISNUMBER(SEARCH("지방배송",R${r}&"")),1,IF(ISNUMBER(SEARCH("시내배송",R${r}&"")),2,IF(OR(SUBSTITUTE(E${r}," ","")="박성호대표",SUBSTITUTE(E${r}," ","")="박성호대표님"),4,3))))))`,
 AB:`IF(AA${r}<>1,"",COUNTIFS($AA$6:$AA$${last},1,$Z$6:$Z$${last},"<"&Z${r})+COUNTIFS($AA$6:$AA$${last},1,$Z$6:$Z$${last},Z${r},$BJ$6:$BJ$${last},"<"&BJ${r})+COUNTIFS($AA$6:AA${r},1,$Z$6:Z${r},Z${r},$BJ$6:BJ${r},BJ${r}))`,
 AH:`IF(BE${r}="","",IFERROR(VLOOKUP(BA${r}&"|"&BB${r},'배송 매칭 확인'!$A$6:$D$${deliveryLast},2,FALSE),""))`,
 BF:`IF(BE${r}="","",IF(AND(BC${r}=0,AC${r}=0),IF(COUNTIF('배송 매칭 확인'!$S$6:$S$${deliveryLast},"*|"&BB${r}&"|*")>0,"고객 ID · 배송 매칭 확인 필요",IF(BK${r}>0,"임시 ID · 업로드 후 확정","고객 ID 확인 필요")),IFERROR(IF(VLOOKUP(BA${r}&"|"&BB${r},'배송 매칭 확인'!$A$6:$D$${deliveryLast},4,FALSE)="확인 필요","배송 매칭 확인 필요",""),"")))`,
 };
}

// These numbers are a download-time availability snapshot, never DB identities.
// Per-row references keep duplicates together without accepting a provisional
// number as an alias or an ID| control during import.
export function provisionalCustomerRows(source,last,idLast,numbers,{spot=false}={}){
 const q="'"+source.replaceAll("'","''")+"'",available=[...new Set(numbers)].filter(n=>Number.isInteger(n)&&n>=3&&n<=9999).slice(0,Math.max(0,last-5));
 const rows=[['신규 고객 임시 ID'],['이름·전체 연락처가 같은 신규 고객은 같은 임시 ID를 사용합니다. 기존·통합된 번호는 재사용하지 않습니다.'],['임시 ID는 이 파일에서만 유효합니다. 업로드 시 DB에서 정식 고객 ID를 확정하고 최신 Excel에 반영합니다.'],['(임시) 명세서는 확정 번호가 아닙니다. 발급·인쇄 전 업로드하고 최신 자료를 다시 다운로드하세요.'],['매칭 Key','고객명','연락처','배정 순서','임시 번호','고객 ID','상태','다운로드 당시 빈 번호']];
 for(let r=6;r<=last;r++){
  const n=`${q}!BA${r}`,p=`${q}!BB${r}`,id=`${q}!BC${r}`,known=`COUNTIF('고객 ID'!$A$6:$A$${idLast},${n}&"|"&${p})`,uncertain=spot?`OR(${n}="고객이름",ISNUMBER(SEARCH("미확인",${n})),ISNUMBER(SEARCH("~?",${n})))`:`${q}!AC${r}=1`;
  rows.push([formula(`IF(AND(${id}=0,${n}<>"",${known}=0,NOT(${uncertain})),${n}&"|"&${p},"")`),formula(`IF(A${r}="","",${q}!E${r})`),formula(`IF(A${r}="","",${q}!F${r}&"")`),formula(`IF(A${r}="",0,IF(COUNTIF($A$6:A${r},A${r})=1,MAX($D$5:D${r-1})+1,0))`,0),formula(`IF(A${r}="","",IFERROR(IF(INDEX($H$6:$H$${last},INDEX($D$6:$D$${last},MATCH(A${r},$A$6:$A$${last},0)))>0,INDEX($H$6:$H$${last},INDEX($D$6:$D$${last},MATCH(A${r},$A$6:$A$${last},0))),"번호 확인 필요"),"번호 확인 필요"))`),formula(`IF(ISNUMBER(E${r}),"LK "&TEXT(E${r},"0000")&" (임시)","")`),formula(`IF(A${r}="","",IF(ISNUMBER(E${r}),"업로드 후 DB 확정","빈 번호 확인 필요"))`),available[r-6]??'']);
 }return rows;
}
function addProvisionalSheet(files,tables,source,last,spot=false){
 newSheet(files,'신규 고객 ID',provisionalCustomerRows(source,last,tables.ids.length,tables.unusedNumbers,{spot}),{widths:[40,32,28,14,14,24,28,18],hiddenColumns:[1,4,5,8]});
}
const provisionalNumber=r=>`IFERROR(IF(ISNUMBER('신규 고객 ID'!E${r}),'신규 고객 ID'!E${r},0),0)`;
const provisionalStatement=(r,prefix)=>`"${prefix} "&IF(BD${r}=1,"9"&TEXT(BK${r},"000"),TEXT(BK${r},"0000"))&" (임시)"`;

// Spot templates keep their original price/weight calculations and print area.
// Only the existing statement-number cell links to the shared ID controls.
function connectSpotStatements(files,tables,strings,prefix,legacy=false){
 const names=[...txt(files['xl/workbook.xml']).matchAll(/<sheet\b[^>]*\bname="([^"]*)"/g)].map(m=>unxml(m[1]));
 const rows=[['명세서 고객 ID 연결'],['각 원본 명세서의 고객명(L2)과 연락처(L4)를 입력하면 고객 ID와 번호가 계산됩니다.'],['수동 번호·잠금은 명세서 번호 관리 시트에서 설정하세요. 신규 고객은 임시 ID를 쓰고 업로드 후 정식 ID로 확정됩니다.'],['오프라인은 다운로드 당시 고객 정보를 사용합니다. 최신 DB 반영은 업로드·승인 후 다시 다운로드하세요.'],['명세서 시트','고객 고유 ID','자동 번호','적용 번호','고객명','연락처','확인 사항']];
 const ids=new Map(tables.ids.slice(5).map(r=>[r[0],r[3]])),controls=new Map(tables.controls.slice(5).map(r=>[r[0],r[7].value]));
 for(const name of names){
  const path=sheetPath(files,name);if(!path)continue;let source=txt(files[path]);
  const values=new Map([...source.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)].map(m=>[m[0].match(/\br="([A-Z]+\d+)"/)?.[1],cellValue(m[0],strings)]));
  if(!/번호/.test(values.get('L1')||'')||!values.has('M1')||!values.has('L2')||!values.has('L4')||!/고객/.test(values.get('I2')||''))continue;
  const r=rows.length+1,quoted="'"+name.replaceAll("'","''")+"'",n=values.get('L2')||'',p=values.get('L4')||'',id=ids.get(matchKey(n,p))||0,special=specialName(n),current=values.get('M1')||'',applied=id?controls.get(identityKey(id,special))||current:current;
  const f=identityCargoFormulas(r,r,tables.ids.length,tables.controls.length,tables.delivery.length,prefix),row=Array(61).fill('');
  const data={BK:formula(provisionalNumber(r),0),A:name,B:formula(`IF(BC${r}>0,"LK "&TEXT(BC${r},"0000"),IF(BK${r}>0,"LK "&TEXT(BK${r},"0000")&" (임시)",""))`,id?customerCode(id):''),C:formula(`IF(BC${r}>0,IFERROR(VLOOKUP("ID|"&BC${r}&"|"&BD${r},'명세서 번호 관리'!$A$6:$H$${tables.controls.length},4,FALSE),""),"")`,id?statementCode(prefix,id,special):''),D:formula(`IF(BC${r}>0,IFERROR(VLOOKUP("ID|"&BC${r}&"|"&BD${r},'명세서 번호 관리'!$A$6:$H$${tables.controls.length},8,FALSE),"ID 확인 필요"),${legacy?JSON.stringify(current):`IF(BK${r}>0,${provisionalStatement(r,prefix)},"ID 확인 필요")`})`,id?applied:'ID 확인 필요'),E:formula(`${quoted}!L2`,n),F:formula(`${quoted}!L4&""`,p),G:formula(`IF(BC${r}>0,"",IF(OR(E${r}="",SUBSTITUTE(E${r}," ","")="고객이름"),"고객명·연락처 입력","고객 ID 확인 필요"))`,id?'':'고객명·연락처 입력'),BA:formula(f.BA,nameKey(baseName(n))),BB:formula(f.BB,'p'+phoneKey(p)),BC:formula(f.BC,id),BD:formula(f.BD,special?1:0),BI:formula(f.BI,'p'+String(p).replace(/\D/g,''))};
  for(const [c,v]of Object.entries(data))row[columnIndex(c)-1]=v;rows.push(row);
  source=source.replace(/<row\b[^>]*\br="1"[^>]*>[\s\S]*?<\/row>/,row=>put(row,'M1',formula(`IF(OR('명세서 고객 ID 연결'!BC${r}>0,'명세서 고객 ID 연결'!BK${r}>0),'명세서 고객 ID 연결'!D${r},IF(OR(L2="",SUBSTITUTE(L2," ","")="고객이름"),${JSON.stringify(current)},"ID 확인 필요"))`,id?applied:(!n||n.replace(/\s/g,'')==='고객이름'?current:'ID 확인 필요'))));
  files[path]=bytes(source);
 }
 if(rows.length>5){newSheet(files,'명세서 고객 ID 연결',rows,{widths:[28,24,20,24,30,28,28],hiddenColumns:Array.from({length:56},(_,i)=>i+8)});addProvisionalSheet(files,tables,'명세서 고객 ID 연결',rows.length,true);}
 return rows.length-5;
}

// Refresh existing input tables only; their pricing/Remark formulas stay intact.
function refreshPolicyInputs(files,context,strings){
 const rowsOf=text=>[...text.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)].map(m=>({n:Number(m[1]),xml:m[0]}));
 const read=(row,c)=>readRow(row,c,strings);
 if(Array.isArray(context.shares)){
  const path=sheetPath(files,'Remark 및 특이사항')||sheetPath(files,'명세서 선공유');
  if(path){const text=txt(files[path]),physical=rowsOf(text),active=context.shares.filter(d=>d.active).sort((a,b)=>a.source_no-b.source_no||a.id-b.id),body=physical.filter(r=>r.n>=3&&r.n<=800);
   if(active.length>body.length)throw Error('Remark 입력 공간이 부족합니다.');
   const replacements=new Map();for(let i=0;i<body.length;i++){const r=body[i],d=active[i];if(!d&&!['A','B','C','D'].some(c=>read(r,c)))continue;replacements.set(r.n,patchRow(r.xml,r.n,d?{A:i+1,B:d.customer_name,C:d.phone_display||d.phone,D:d.content}:{A:'',B:'',C:'',D:''}));}
   files[path]=bytes(text.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>replacements.get(Number(n))||row));
  }
 }
 if(!Array.isArray(context.discounts))return;
 const path=sheetPath(files,'Row data');if(!path)return;
 const text=txt(files[path]),physical=rowsOf(text),byRow=new Map(physical.map(r=>[r.n,r])),tables=[];
 const key=v=>String(v??'').toLowerCase().replace(/[\s._-]/g,'');
 const groupKey=v=>key(v).replace(/(?:할인)?고객리스트$|할인$/g,'');
 const nameHeader=v=>['이름','성함','고객명','name','customername'].includes(key(v)),phoneHeader=v=>['전화번호','연락처','tel','phone','telephone','contact'].includes(key(v));
 for(const row of physical){for(let c=0;c<32;c++){if(!nameHeader(read(row,col(c))))continue;let p=-1,d=-1;for(let j=c+1;j<=c+6;j++){const v=read(row,col(j));if(phoneHeader(v))p=j;if(['할인','할인율','discount','discountrate'].includes(key(v)))d=j;}if(p<0||d<0)continue;
  let group='';outer:for(let n=row.n;n>=Math.max(1,row.n-12);n--){const prior=byRow.get(n);if(!prior)continue;for(let j=Math.max(0,c-1);j<=c+6;j++){const v=read(prior,col(j));if(!nameHeader(v)&&!phoneHeader(v)&&!['할인','할인율','할인금액','할인액','할인총합'].includes(key(v))&&/라선협|지상사|회원사|법인장|지인|아파트|기업|특별|파트너|협력사|할인/.test(v)){group=v.replace(/customer\s*list|discount\s*list|customer\s*discount|할인\s*고객\s*리스트|고객\s*리스트|할인\s*고객/gi,'').trim();if(group)break outer;}}}
  tables.push({row:row.n,c,p,d,group});
 }}
 const updates=new Map(),set=(n,c,v)=>{if(!updates.has(n))updates.set(n,{});updates.get(n)[col(c)]=v;};
 const rules=context.discounts,used=new Set();
 for(const table of tables){let n=table.row+1;const special=groupKey(table.group)==='특별';
  for(;byRow.has(n)&&read(byRow.get(n),col(table.c));n++){
   const row=byRow.get(n),name=read(row,col(table.c)),phone=read(row,col(table.p));
   const candidates=rules.filter(d=>nameKey(d.customer_name)===nameKey(name)&&(!d.group_name||groupKey(d.group_name)===groupKey(table.group)||special&&Number(d.special_discount_percent)>0));
   let matches=candidates.filter(d=>phoneKey(d.phone)===phoneKey(phone));
   if(!phoneKey(phone)){const active=candidates.filter(d=>d.active&&(d.excel_source_row===n||candidates.filter(x=>x.active).length===1));if(active.length===1)matches=active;}
   matches.sort((a,b)=>Number(b.active)-Number(a.active)||String(b.updated_at).localeCompare(String(a.updated_at)));
   const d=matches[0];if(!d){set(n,table.d,0);continue;}used.add(d.id+'|'+Number(special));
   const pct=special?Number(d.special_discount_percent??(groupKey(d.group_name)==='특별'?d.discount_percent:0)):Number(d.discount_percent)-Number(d.special_discount_percent||0);
   if(!Number.isFinite(pct)||pct<0||pct>1)continue;
   set(n,table.c,d.customer_name);if(phoneKey(phone)!==phoneKey(d.phone))set(n,table.p,d.phone);
   set(n,table.d,!d.active&&phoneKey(d.phone)?0:pct);
  }
  const additions=rules.filter(d=>d.active&&(special?Number(d.special_discount_percent??(groupKey(d.group_name)==='특별'?d.discount_percent:0))>0:groupKey(d.group_name)===groupKey(table.group))&&!used.has(d.id+'|'+Number(special))&&d.rate_override==null&&!d.bulk_threshold);
  for(const d of additions){const row=byRow.get(n);if(!row||[table.c,table.p,table.d].some(c=>read(row,col(c)))||tables.some(t=>t.row===n))break;
   const pct=special?Number(d.special_discount_percent??(groupKey(d.group_name)==='특별'?d.discount_percent:0)):Number(d.discount_percent)-Number(d.special_discount_percent||0);if(!Number.isFinite(pct)||pct<0||pct>1)continue;
   set(n,table.c,d.customer_name);set(n,table.p,d.phone);set(n,table.d,pct);used.add(d.id+'|'+Number(special));n++;
  }
 }
 files[path]=bytes(text.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>patchRow(row,n,updates.get(Number(n)))));
}

export function applyCustomerIdWorkbook(files,context,{prefix='LKS',shipments=[],base=false,preserveSharedMasters=true}={}){
 if(preserveSharedMasters)recoverDeliverySelectorMasters(files,sheetPath);
 const sharedMasters=preserveSharedMasters?captureSharedFormulaMasters(files):null;
 const result=applyCustomerIdWorkbookContent(files,context,{prefix,shipments,base});
 if(sharedMasters)restoreSharedFormulaMasters(files,sharedMasters);
 return result;
}
function applyCustomerIdWorkbookContent(files,context,{prefix='LKS',shipments=[],base=false}={}){
 const strings=sharedStrings(files),cargoPath=sheetPath(files,'물품 입고 내역'),deliveryRefs=new Map(),deliveryRefFormulas=new Map();
 refreshPolicyInputs(files,context,strings);
 // Refresh only editable delivery input columns, keeping existing calculation,
 // address-selection, validation and print sections intact.
 for(const [name,type,tag] of [['지방배송','province','L'],['시내배송','city','C']]){
  const path=sheetPath(files,name);if(!path)continue;
  const profiles=(context.deliveries??[]).filter(d=>d.delivery_type===type);
  let text=txt(files[path]);const physical=[...text.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)].map(m=>({n:Number(m[1]),xml:m[0]}));
  const read=(row,c)=>readRow(row,c,strings);
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
   const profileKey=matchKey(d.customer_name,d.phone_display||d.phone);
   let block=blocks.find(b=>(b.matchKey??=matchKey(read(b.first,'B'),read(b.first,'E')))===profileKey)||(numbered.length===1?numbered[0]:null);
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
  text=text.replace(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g,(row,n)=>patchRow(row,n,updates.get(Number(n))));
  files[path]=bytes(text);
 }
 const cargoData=cargoPath?files[cargoPath]:new Uint8Array();
 const {hasRanking,last}=worksheetIdentityRange(cargoData);
 const tables=makeIdentityTables(context,{prefix,shipments,deliveryRefs,deliveryRefFormulas,cargoLast:last,cargo:!!cargoPath});
 const legacy=context.numberingMode==='legacy';
 newSheet(files,'고객 ID',tables.ids,{widths:[48,32,28,15,18],hiddenColumns:[1]});
 newSheet(files,'명세서 번호 관리',tables.controls,{widths:[22,18,34,20,20,14,20,20,14,22],hiddenColumns:[1,11,12,13,15],inputColumns:[{column:'F',values:['자동','잠금']}]});
 newSheet(files,'배송 매칭 확인',tables.delivery,{widths:[45,18,18,18,70,20,30,26,20,16,14,28,28,24,16,18,50,35],hiddenColumns:[1,2,3,9,10,11,12,13,14,15,16,17,18,19]});
 if(!cargoPath||last<=6){const spotCount=connectSpotStatements(files,tables,strings,prefix,legacy);return {tables,applied:spotCount>0,spotCount,version:ID_WORKBOOK_VERSION};}
 addProvisionalSheet(files,tables,'물품 입고 내역',last);
 const idByKey=new Map(tables.ids.slice(5).map(r=>[r[0],r[3]]));
 const controlByKey=new Map(tables.controls.slice(5).map(r=>[r[0],r[7].value]));
 const deliveryByKey=new Map(tables.delivery.slice(5).map(r=>[r[0],r]));
 const summaries=new Map(),recoveryByReceipt=new Map(tables.controls.slice(5).map(r=>[r[7].value,Number(r[13])||0]));
 files[cargoPath]=rewriteWorksheetRows(cargoData,(row,n)=>{
  const r=Number(n);if(r<6||r>last)return row;
  const cells=parsedCells(row),get=c=>cellValue(cells.get(c)??'',strings);
  const name=get('E'),phone=get('F'),key=matchKey(name,phone),id=idByKey.get(key)||0,special=specialName(name),control=legacy?(get('N')?'LEGACY|'+get('N'):''):id?identityKey(id,special):get('AC')==='1'?'UNKNOWN':'',receipt=legacy?get('N'):control?controlByKey.get(control):name||phone?get('N')||'ID 확인 필요':'',delivery=deliveryByKey.get(key);
  const priorY=get('Y'),cache={BK:0,BL:id?customerCode(id):'',BJ:unknownPrefixZone(name)&&special?(recoveryByReceipt.get(receipt)||1e12+r):id,R:get('R'),BG:legacy?get('N'):get('BG')||get('N'),BH:get('BH')||key,BI:'p'+String(phone??'').replace(/\D/g,''),BA:nameKey(baseName(name)),BB:'p'+phoneKey(phone),BC:id,BD:special?1:0,BE:control||(!name&&!phone?'':get('AC')==='1'?'UNKNOWN':'SRC|'+key),Y:control||priorY,N:receipt,AH:delivery?.[1]?.value??'',BF:id?(delivery?.[3]?.value==='확인 필요'?'배송 매칭 확인 필요':''):name&&get('AC')!=='1'?'고객 ID 확인 필요':''};
  const updates={BG:cache.BG,BH:cache.BH};
  if(!cache.AH)cache.R=cache.BF;
  const formulas=identityCargoFormulas(r,last,tables.ids.length,tables.controls.length,tables.delivery.length,prefix);
  if(!hasRanking){
   // Older cargo templates already own their delivery/price formulas. Add only
   // identity grouping and ordering helpers in previously unused columns.
   delete formulas.R;delete formulas.AH;
   formulas.AA=`IF(Y${r}="","",IF(COUNTIF($Y$6:Y${r},Y${r})=1,1,0))`;
   formulas.AC=`IF(AND(BC${r}=0,ISNUMBER(SEARCH("수취인 불명",E${r}))),1,0)`;
  }
  if(legacy){
   formulas.BE=`IF(AND(E${r}="",F${r}=""),"",IF(BG${r}="","","LEGACY|"&BG${r}))`;
   formulas.N=`IF(BE${r}="","",IFERROR(VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$H$${tables.controls.length},8,FALSE),BG${r}))`;
   formulas.AB=`IF(AA${r}<>1,"",IFERROR(VLOOKUP(BE${r},'명세서 번호 관리'!$A$6:$M$${tables.controls.length},13,FALSE),""))`;
   cache.BE=control;cache.Y=control;
  }
  for(const [column,f] of Object.entries(formulas))updates[column]=formula(f,cache[column]??'');
  if(receipt&&!summaries.has(receipt))summaries.set(receipt,{id,receipt,recovered:recoveryByReceipt.get(receipt)||0,priority:unknownPrefixZone(name)&&special?7:special?6:receipt.endsWith(' XX')?5:delivery?.[1]?.value?.startsWith('L|')?1:delivery?.[1]?.value?.startsWith('C|')?2:/^박성호\s*대표님?$/.test(name)?4:3});
  return patchRow(row,r,updates,cells);
 },header=>hideColumns(header.replace(/<dimension\b[^>]*\/>/,`<dimension ref="A1:BL${Math.max(last,1010)}"/>`),53,64));
 const customerPath=sheetPath(files,'고객 리스트');
 if(customerPath){let i=0;const ordered=[...summaries.values()].sort((a,b)=>legacy?(a.recovered&&b.recovered?a.recovered-b.recovered:a.recovered?1:b.recovered?-1:a.receipt.localeCompare(b.receipt,'en',{numeric:true})):a.priority-b.priority||(a.priority===7?(a.recovered||1e12)-(b.recovered||1e12):a.id-b.id));let text=txt(files[customerPath]);
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
