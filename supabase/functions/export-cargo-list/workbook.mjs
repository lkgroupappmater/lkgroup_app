// The small Artifact Tool template preserves the existing A:Q cargo layout.
// Filling OOXML cells avoids loading/recalculating a macro workbook per download.
import {templateBase64} from './template.mjs';
export const cargoFields=['id','box_number','invoice_number','sender_name','consignee_name','consignee_phone','contents','package_type','quantity','weight_kg','length_cm','width_cm','height_cm','receipt_number','unloading_zone','notes','received_at'];
const headers={
 ko:['No.','화물번호','송장번호','보내는 분','수취인','연락처','품목','포장','수량','중량 (kg)','길이 (cm)','너비 (cm)','높이 (cm)','No. Bill','구획','비고','입고일'],
 en:['No.','Box No.','Invoice No.','Sender','Consignee','Phone','Contents','Package','Quantity','Weight (kg)','Length (cm)','Width (cm)','Height (cm)','No. Bill','Zone','Remark','Received'],
 lo:['No.','ເລກສິນຄ້າ','ເລກໃບສົ່ງ','ຜູ້ສົ່ງ','ຜູ້ຮັບ','ເບີໂທ','ລາຍການ','ຫີບຫໍ່','ຈຳນວນ','ນ້ຳໜັກ (kg)','ຍາວ (cm)','ກວ້າງ (cm)','ສູງ (cm)','No. Bill','ເຂດ','ໝາຍເຫດ','ວັນຮັບ']
};
const xml=v=>String(v).replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]/g,'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
export function cargoMatrix(rows){
 return [...rows].sort((a,b)=>String(a.box_number||'').localeCompare(String(b.box_number||''),'en',{numeric:true,sensitivity:'base'})||Number(a.id)-Number(b.id)).map((r,i)=>cargoFields.map((key,col)=>{
  if(col===0)return i+1;
  const value=r[key];if(value==null||value==='')return null;
  if(col>=8&&col<=12){const n=Number(value);return Number.isFinite(n)?n:String(value);}
  if(col===16){const date=String(value).match(/^\d{4}-\d{2}-\d{2}/)?.[0];if(date){const ms=Date.parse(date+'T00:00:00Z');if(Number.isFinite(ms))return ms/86400000+25569;}}
  return String(value);
 }));
}
export function buildCargoWorkbook(rows,{route,year,voyage,language='ko'},zip){
 const files=zip.unzipSync(Uint8Array.from(atob(templateBase64),c=>c.charCodeAt(0))),decoder=new TextDecoder(),encoder=new TextEncoder();
 const name='xl/worksheets/sheet1.xml',source=decoder.decode(files[name]);
 const sample=source.match(/<x:row\b[^>]*r="6"[^>]*>[\s\S]*?<\/x:row>/)?.[0]||'';
 const styles=Array.from({length:17},(_,i)=>sample.match(new RegExp('<x:c\\b[^>]*r="'+String.fromCharCode(65+i)+'6"[^>]*s="(\\d+)"'))?.[1]||'1');
 const cell=(value,col,row,style)=>{const ref=String.fromCharCode(65+col)+row,attr=`r="${ref}" s="${style}"`;return value==null?`<x:c ${attr}/>`:typeof value==='number'?`<x:c ${attr}><x:v>${value}</x:v></x:c>`:`<x:c ${attr} t="inlineStr"><x:is><x:t xml:space="preserve">${xml(value)}</x:t></x:is></x:c>`;};
 const matrix=cargoMatrix(rows),label=language==='ko'?'입고 내역':language==='lo'?'ລາຍການຮັບສິນຄ້າ':'Cargo list';
 let data=`<x:row r="1">${cell('LK Group · '+label,0,1,2)}</x:row><x:row r="3">${cell(`${route} · ${year} · V${voyage}`,0,3,1)}</x:row><x:row r="5" ht="36" customHeight="1">${(headers[language]||headers.ko).map((v,c)=>cell(v,c,5,6)).join('')}</x:row>`;
 data+=matrix.map((values,i)=>`<x:row r="${i+6}" ht="26" customHeight="1">${values.map((v,c)=>cell(v,c,i+6,styles[c])).join('')}</x:row>`).join('');
 files[name]=encoder.encode(source.replace(/<x:sheetData>[\s\S]*?<\/x:sheetData>/,`<x:sheetData>${data}</x:sheetData>`));
 return zip.zipSync(files,{level:6});
}
