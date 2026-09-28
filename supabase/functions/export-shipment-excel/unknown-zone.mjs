import {rewriteWorksheetRows} from './worksheet-rows.mjs';
export const unknownPrefixZone=name=>/^수취인불명([/／]|$)/.test(String(name??'').replace(/[\s　]/g,''));
const esc=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
export function unknownZoneCondition(ref){
 const n=`SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(CLEAN(${ref})," ",""),"　",""),CHAR(160),""),"／","/")`;
 return `OR(${n}="수취인불명",LEFT(${n},6)="수취인불명/")`;
}
// Wrap the existing calculation, including shared-formula masters. Customer
// matching, bill numbers, quantity rules and explicit ordinary zones are retained.
export function applyUnknownPrefixZones(files,{sheetPath,strings=[],cellText}){
 let changed=0;
 for(const [name,column,source,start,end] of [['물품 입고 내역','O','E',6,1005],['고객 리스트','C','B',4,114]]){
  const path=sheetPath(files,name);if(!path||!files[path])continue;
  files[path]=rewriteWorksheetRows(files[path],(row,n)=>{
   const r=Number(n);if(r<start||r>end)return row;
   const sourceCell=row.match(new RegExp(`<c\\b[^>]*r="${source}${r}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`))?.[0];
   const isF=unknownPrefixZone(sourceCell?cellText(sourceCell,strings):'');
   return row.replace(new RegExp(`<c\\b([^>]*r="${column}${r}"[^>]*)(?:\\/>|>([\\s\\S]*?)<\\/c>)`),(cell,attrs,body='')=>{
    const formula=body.match(/<f\b([^>]*?)>([^<]+)<\/f>/);
    if(formula&&!formula[2].includes('="수취인불명/"')){
     body=body.replace(formula[0],`<f${formula[1]}>IF(${esc(unknownZoneCondition(source+r))},"F",${formula[2]})</f>`);changed++;
    }else if(!/<f\b/.test(body)){
     const value=cellText(cell,strings),literal='"'+String(value).replaceAll('"','""')+'"';
     body=`<f>IF(${esc(unknownZoneCondition(source+r))},"F",${esc(literal)})</f><v>${esc(isF?'F':String(value))}</v>`;
     attrs=attrs.replace(/\s+t="[^"]*"/g,'')+' t="str"';changed++;
    }
    if(isF){body=body.replace(/<v\b[^>]*?(?:\/>|>[\s\S]*?<\/v>)/,'');body+='<v>F</v>';attrs=attrs.replace(/\s+t="[^"]*"/g,'')+' t="str"';}
    return `<c${attrs}>${body}</c>`;
   });
 });
 }return changed;
}
