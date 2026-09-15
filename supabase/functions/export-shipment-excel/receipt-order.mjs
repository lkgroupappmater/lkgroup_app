// Shared by both offline workbooks and the App/Web export function.
export const RECEIPT_RULE_VERSION = '2026-09-11.representative-title-v1';
// AK is the validated, normalized real name; AC excludes unresolved recipients.
// These exact formulas are also authored into the offline Sea/Air templates.
export function fixedDiscountFormulas(row) {
 const valid = representativeFormula(row);
 const base = `IF(AJ${row}=0,0,INDEX('Row data'!$AM:$AM,AJ${row}))`;
 return {
  T: `IF(${valid},"대표 고정 할인 100% 적용",IF(AND(AK${row}="박성호",AD${row}=0),"",IF(AJ${row}=0,"",INDEX('Row data'!$AL:$AL,AJ${row}))))`,
  AD: `IF(${valid},1,IF(AND(AK${row}="박성호",${base}=1),0,${base}))`,
 };
}
export const isParkRepresentative = name => ['박성호대표','박성호대표님'].includes(String(name ?? '').replace(/\s/g,''));
function representativeFormula(row, recovered = true) {
 const name = recovered ? `IF(AL${row}=2,TRIM(MID(E${row},FIND("/",E${row}&"/")+1,LEN(E${row}))),E${row})` : `E${row}`;
 const compact = ['" "','CHAR(160)','CHAR(9)','CHAR(10)','CHAR(13)'].reduce((value,space)=>`SUBSTITUTE(${value},${space},"")`,name);
 return `AND(AC${row}=0,OR(${compact}="박성호대표",${compact}="박성호대표님"))`;
}
const ORIGINAL = {"AC": "IF(AND(TRIM(E6&\"\")=\"\",TRIM(F6&\"\")=\"\"),0,IF(TRIM(E6&\"\")<>\"\",IF(OR(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1))=\"\",LEN(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))<>LEN(SUBSTITUTE(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)),\"?\",\"\")),LEN(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))<>LEN(SUBSTITUTE(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)),\"*\",\"\")),LEN(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))<>LEN(SUBSTITUTE(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)),\"#\",\"\")),ISNUMBER(SEARCH(\"수취인 불명\",TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))),ISNUMBER(SEARCH(\"기호포함 이름\",TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))),ISNUMBER(SEARCH(\"미확인\",TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))),ISNUMBER(SEARCH(\"불확실\",TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))),ISNUMBER(SEARCH(\"unknown\",LOWER(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1))))),ISNUMBER(SEARCH(\"n/a\",LOWER(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)))))),1,0),IF(OR(LEN(F6&\"\")<>LEN(SUBSTITUTE(F6&\"\",\"?\",\"\")),LEN(F6&\"\")<>LEN(SUBSTITUTE(F6&\"\",\"*\",\"\")),LEN(F6&\"\")<>LEN(SUBSTITUTE(F6&\"\",\"#\",\"\")),ISNUMBER(SEARCH(\"수취인 불명\",F6&\"\")),ISNUMBER(SEARCH(\"기호포함 이름\",F6&\"\")),ISNUMBER(SEARCH(\"미확인\",F6&\"\")),ISNUMBER(SEARCH(\"불확실\",F6&\"\")),ISNUMBER(SEARCH(\"unknown\",LOWER(F6&\"\"))),ISNUMBER(SEARCH(\"n/a\",LOWER(F6&\"\")))),1,0)))", "AK": "IF(E6=\"\",\"\",IF(AND(AL6=1,AC6=0),LOWER(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)),\" \",\"\"),\"-\",\"\"),\"/\",\"\"),\"(\",\"\"),\")\",\"\"),\".\",\"\"),\",\",\"\"),\"'\",\"\"),\"대표님\",\"\"),\"사장님\",\"\"),\"대표\",\"\"),\"사장\",\"\"),\"님\",\"\"),CHAR(160),\"\"),CHAR(10),\"\")),X6))", "AL": "IF(E6=\"\",0,IF(OR(LEN(E6&\"\")<>LEN(SUBSTITUTE(E6&\"\",\"?\",\"\")),LEN(E6&\"\")<>LEN(SUBSTITUTE(E6&\"\",\"*\",\"\")),LEN(E6&\"\")<>LEN(SUBSTITUTE(E6&\"\",\"#\",\"\")),ISNUMBER(SEARCH(\"수취인 불명\",E6&\"\")),ISNUMBER(SEARCH(\"기호포함 이름\",E6&\"\")),ISNUMBER(SEARCH(\"미확인\",E6&\"\")),ISNUMBER(SEARCH(\"불확실\",E6&\"\")),ISNUMBER(SEARCH(\"unknown\",LOWER(E6&\"\"))),ISNUMBER(SEARCH(\"n/a\",LOWER(E6&\"\")))),1,0))", "AM": "IF(E6=\"\",\"\",IF(AND(AL6=1,AC6=0),TRIM(LEFT(E6,FIND(\"/\",E6&\"/\")-1)),E6))"};
const replaceTokens=(expr,tokens)=>tokens.reduce((s,t)=>`SUBSTITUTE(${s},${typeof t==='string'?JSON.stringify(t):t.formula},"")`,expr);
const nameFormula=expr=>`LOWER(${replaceTokens(expr,[' ','-','/','(',')','.',',',"'",'대표님','사장님','대표','사장','님',{formula:'CHAR(160)'},{formula:'CHAR(10)'}])})`;
const uncertainFormula=expr=>`OR(${['?','*','#'].map(t=>`LEN(${expr})<>LEN(SUBSTITUTE(${expr},"${t}",""))`).concat(['수취인 불명','기호포함 이름','미확인','불확실','unknown','n/a'].map(t=>`ISNUMBER(SEARCH("${t}",${expr}))`)).join(',')})`;
export function receiptOrderFormulas(row,lastRow,prefix='LKS') {
 const r=row,e=lastRow;
 const original=col=>ORIGINAL[col].replace(/(?<![A-Z0-9_])([A-Z]{1,3})6(?![0-9])/g,(_,c)=>c+r);
 const suffix=`TRIM(MID(E${r},FIND("/",E${r}&"/")+1,LEN(E${r})))`;
 const phone=replaceTokens(`F${r}&""`,[' ','-','(',')','+','/','.',"'",{formula:'CHAR(160)'},{formula:'CHAR(10)'}]);
 const nondigits=replaceTokens(phone,Array.from({length:10},(_,i)=>String(i)));
 const valid=`AND(SUBSTITUTE(TRIM(LEFT(E${r},FIND("/",E${r}&"/")-1))," ","")="수취인불명",${nameFormula(suffix)}<>"",NOT(${uncertainFormula(suffix)}),LEN(${phone})>=8,LEN(${phone})<=15,${nondigits}="")`;
 const base=`$AA$6:$AA$${e},1,$AC$6:$AC$${e},0,$Y$6:$Y$${e},"<>__PARK__"`;
 const same=`${base},$Z$6:$Z$${e},Z${r}`;
 const tie=`$AA$6:AA${r},1,$AC$6:AC${r},0,$Y$6:Y${r},"<>__PARK__",$Z$6:Z${r},Z${r}`;
 const rank=`INDEX($AB$6:$AB$${e},MATCH(Y${r},$Y$6:$Y$${e},0))`;
 return {
  AL:`IF(${valid},2,${original('AL')})`,
  AC:`IF(AL${r}=2,0,${original('AC')})`,
  AK:`IF(AL${r}=2,${nameFormula(suffix)},${original('AK')})`,
  // Display retains the former-unknown prefix; AK supplies the rule lookup name.
  AM:original('AM'),
  Y:`IF(AND(E${r}="",F${r}=""),"",IF(AC${r}=1,"${prefix} XX",IF(AL${r}=2,"R|"&AK${r}&"|"&W${r},IF(${representativeFormula(r,false)},"__PARK__",IF(AK${r}<>"","N|"&AK${r},IF(W${r}<>"","P|"&W${r},"${prefix} XX"))))))`,
  N:`IF(Y${r}="","",IF(AC${r}=1,"${prefix} XX",IF(Y${r}="__PARK__","${prefix} 100",IFERROR("${prefix} "&TEXT(IF(${rank}>=100,${rank}+1,${rank}),"00"),""))))`,
  Z:`IF(Y${r}="","",10*IF(AL${r}=2,6,IF(AC${r}=1,5,IF(ISNUMBER(SEARCH("지방배송",R${r}&"")),1,IF(ISNUMBER(SEARCH("시내배송",R${r}&"")),2,IF(Y${r}="__PARK__",4,3)))))+IF(AK${r}="",4,IF(AND(LEFT(AK${r},1)>="a",LEFT(AK${r},1)<="z"),1,IF(AND(LEFT(AK${r},1)>="가",LEFT(AK${r},1)<="힣"),2,3))))`,
  AB:`IF(OR(AA${r}<>1,AC${r}=1,Y${r}="__PARK__"),"",COUNTIFS(${base},$Z$6:$Z$${e},"<"&Z${r})+IF(AK${r}="",COUNTIFS(${same},$W$6:$W$${e},"<"&W${r})+COUNTIFS(${tie},$W$6:W${r},W${r}),COUNTIFS(${same},$AK$6:$AK$${e},"<"&AK${r})+COUNTIFS(${same},$AK$6:$AK$${e},AK${r},$W$6:$W$${e},"<"&W${r})+COUNTIFS(${tie},$AK$6:AK${r},AK${r},$W$6:W${r},W${r})))`,
 };
}
// Exact normalization used by the supplied Excel X/AK/Y helper columns.
export function excelName(name) {
  let s=String(name??'');
  for(const token of [' ','-','/','(',')','.',',',"'",'대표님','사장님','대표','사장','님','\u00a0','\n'])s=s.split(token).join('');
  return s.toLowerCase();
}
export const uncertain = s => /[?*#]|수취인 불명|기호포함 이름|미확인|불확실|unknown|n\/a/i.test(String(s??''));
export function excelPhone(phone) {
  let p=String(phone??'');
  for(const token of [' ','-','(',')','+','/','.',"'",'&CHAR(160)&','&CHAR(10)&'])p=p.split(token).join('');
  return p.slice(-8);
}
export function recoveredName(name,phone) {
 const raw=String(name??''),slash=raw.indexOf('/');
 if(slash<0||raw.slice(0,slash).trim().replaceAll(' ','')!=='수취인불명')return null;
 const suffix=raw.slice(slash+1).trim();
 const clean=String(phone??'').replace(/[ ()+/.\-\u00a0\n']/g,'');
 return excelName(suffix)&&!uncertain(suffix)&&/^[0-9]{8,15}$/.test(clean)?suffix:null;
}
export function excelIdentity(name,phone) {
  name=String(name??'');phone=String(phone??'');
  if(!name.trim()&&!phone.trim())return '';
  const recovered=recoveredName(name,phone);
  if(recovered!==null)return 'R|'+excelName(recovered)+'|'+excelPhone(phone);
  const first=name.split('/')[0].trim();
  if(name.trim()?(!first||uncertain(first)):uncertain(phone))return 'XX';
  const key=excelName(uncertain(name)?first:name);
  if(key)return 'N|'+key;
  const p=excelPhone(phone);
  return p?'P|'+p:'XX';
}
export function excelSortKey(identity) {
  const s=identity.slice(2);
  return (identity.startsWith('P|')?'4':/^[a-z]/.test(s)?'1':/^[가-힣]/.test(s)?'2':'3')+s;
}
