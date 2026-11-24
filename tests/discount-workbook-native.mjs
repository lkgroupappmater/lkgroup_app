import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {zipSync,unzipSync,strToU8,strFromU8} from 'fflate';
import {applyDiscountMatching,validateDiscountWorksheet} from '../supabase/functions/export-shipment-excel/discount-workbook.mjs';
import {discountMatchRank,discountPhoneTokens} from '../supabase/functions/export-shipment-excel/discount-matching.mjs';
import {validateWorkbookFormulas} from '../supabase/functions/export-shipment-excel/workbook-integrity.mjs';
const out=path.resolve('test-results/discount-native');fs.mkdirSync(out,{recursive:true});
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const cell=(ref,v)=>typeof v==='number'?`<c r="${ref}"><v>${v}</v></c>`:`<c r="${ref}" t="inlineStr"><is><t>${esc(v)}</t></is></c>`;
const f=(ref,v)=>`<c r="${ref}"><f>${esc(v)}</f><v>0</v></c>`;
const sheet=rows=>`<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${rows}</sheetData></worksheet>`;
const rules=[
 {row:94,customer_name:'시험회원A',company_name:'시험 회사 / Sample Company',phone_display:'020-1111-0001 / 020 1111 0002'},
 {row:95,customer_name:'시험회원B/시험회원C/\r\n시험회원D(시험회원E)/시험회원F',company_name:'Sample Association',phone_display:'020 2222 0001 / 020 2222 0002 / 010 2222 0003 / 020 2222 0004 / 020 2222 0005 / 020 2222 0006'},
 {row:96,customer_name:'시험회원G/시험회원H(시험회원I)',company_name:'Second Company',phone_display:'020 3333 0001 / 020 3333 0002'}
];
const inputs=[];
for(const name of ['시험 회사/시험회원A','Sample Company/시험회원A','시험회원A/시험 회사','시험회원A/Sample Company','시험 회사','시험회원A'])for(const phone of ['020-1111-0001','020 1111 0002'])inputs.push({name,phone});
for(const name of ['시험회원B','시험회원C','시험회원D','시험회원E','시험회원F'])for(const phone of discountPhoneTokens(rules[1].phone_display))inputs.push({name,phone});
inputs.push({name:'수령인/시험회원I',phone:'02033330001'},{name:'시험회원I/수령인',phone:'02033330002'},{name:'수령인/시험회원C/기타',phone:'02099999991 / 02022220006 / 02099999992'},{name:'시험회원A2',phone:'02011110001'},{name:'시험회원B',phone:'02033330001'});
inputs.push(...['2','3','25','001','12345678901234567890'].map(suffix=>({name:'수령인/시험회원C'+suffix+'/기타',phone:'02022220006'})),{name:'시험회원C2Extra',phone:'02022220006'},{name:'시험회원C25',phone:'02099999999'});
inputs.push({name:'Sample Association',phone:'02022220001'},{name:'시험회원I',phone:'02033330002'},{name:'시험회원A',phone:'+856 20 1111 0001'},{name:'시험회원A',phone:'02099999999'},{name:'시험회원A',phone:''},{name:'다른 고객',phone:'02011110001'},{name:'시험회원A',phone:'02099999999 / 02011110001'},{name:'새 회원',phone:'02011112222'},{name:'새 회원',phone:'02033334444'},{name:'새 회원',phone:'02077778888'});
// Exercise the last cargo row of the Sea BASE, beyond the source chart range.
inputs.push({name:'Sample Company/시험회원A',phone:'02011110001',row:1010});
// Returned desktop workbook rows: both registered phones must recalculate.
inputs.push({name:'시험 회사/시험회원A',phone:'020-1111-0001',row:214},{name:'시험 회사/시험회원A',phone:'020 1111 0002',row:215},{name:'시험회원A/Sample Company',phone:'020-1111-0001',row:216});
function expected(input,rs){return rs.map(r=>({...r,rank:discountMatchRank(input.name,input.phone,r)})).filter(r=>r.rank<9999).sort((a,b)=>a.rank-b.rank||b.row-a.row)[0]?.row||0;}
const rowData=(rs,rate=.2,special=false)=>sheet(`<row r="93">${cell('H93','이름')+cell('J93','회사명')+cell('K93','전화번호')+cell('L93','할인율')}</row>`+rs.map(r=>`<row r="${r.row}">${cell('H'+r.row,r.customer_name)+cell('J'+r.row,r.company_name)+cell('K'+r.row,r.phone_display)+cell('L'+r.row,rate)+f('AG'+r.row,`IF(AM${r.row}=0,"","${special?'특별할인':'지상사협의회 회원사 할인'}")`)+f('AK'+r.row,`IF(AM${r.row}=0,"",H${r.row})`)+f('AM'+r.row,`IFERROR(IF(ISNUMBER(L${r.row}),L${r.row},VALUE(SUBSTITUTE(L${r.row},"%",""))/100),0)`)}</row>`).join(''));
const cargo=sheet(inputs.map((v,i)=>({...v,row:v.row||i+6})).sort((a,b)=>a.row-b.row).map(v=>{const r=v.row;return `<row r="${r}">${cell('E'+r,v.name)+cell('F'+r,v.phone)+f('Y'+r,`IF(AND(E${r}="",F${r}=""),"","SRC|"&E${r}&"|"&F${r})`)+cell('N'+r,'LKS '+r)+cell('AC'+r,0)+f('AD'+r,`IF(AJ${r}=0,0,INDEX('Row data'!$AM:$AM,AJ${r}))`)+f('AE'+r,`IF(AO${r}=0,0,INDEX('Row data'!$AM:$AM,AO${r}))`)+cell('AL'+r,0)+f('AJ'+r,"IFERROR(MATCH(E"+r+",'Row data'!H3:H256,0),0)")+f('AO'+r,'0')}</row>`;}).join(''));
const files={
 '[Content_Types].xml':strToU8('<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'),
 '_rels/.rels':strToU8('<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
 'xl/workbook.xml':strToU8('<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Row data" sheetId="1" r:id="rId1"/><sheet name="물품 입고 내역" sheetId="2" r:id="rId2"/></sheets><calcPr calcId="191029" calcMode="manual" fullCalcOnLoad="0" forceFullCalc="0" iterateCount="100"/></workbook>'),
 'xl/_rels/workbook.xml.rels':strToU8('<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>'),
 'xl/worksheets/sheet1.xml':strToU8(rowData(rules)),'xl/worksheets/sheet2.xml':strToU8(cargo),
};
const before=new Map(Object.entries(files).map(([k,v])=>[k,v.slice()]));
assert.equal(applyDiscountMatching(files).applicable,true);assert.equal(validateWorkbookFormulas(files).shared_formula_errors,0);
for(const setting of ['calcId="0"','calcMode="auto"','fullCalcOnLoad="1"','forceFullCalc="1"'])assert.ok(strFromU8(files['xl/workbook.xml']).includes(setting));
assert.ok(strFromU8(files['xl/workbook.xml']).includes('iterateCount="100"'));
const noCalculation=Object.fromEntries([...before].map(([k,v])=>[k,v.slice()]));
noCalculation['xl/workbook.xml']=strToU8(strFromU8(noCalculation['xl/workbook.xml']).replace(/<calcPr\b[^>]*\/>/,'<extLst/>'));
applyDiscountMatching(noCalculation);
assert.match(strFromU8(noCalculation['xl/workbook.xml']),/<calcPr calcId="0" calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"\/><extLst\/>/);
const helperPath='xl/worksheets/lk-discount-identity.xml',helper=strFromU8(files[helperPath]);
assert.doesNotMatch(helper,/<f[^>]*\bt="shared"/);
assert.doesNotMatch(helper,/_xlfn\.AGGREGATE/);
assert.ok(validateDiscountWorksheet(files[helperPath]).formula_count>10000);
assert.equal(validateDiscountWorksheet(files[helperPath]).array_formula_count,(Math.max(...inputs.map((v,i)=>v.row||i+6))-5)*4);
assert.match(helper,/<c r="O6"><f t="array" ref="O6">/);
assert.throws(()=>validateDiscountWorksheet(strToU8(helper.replace('ref="O6"','ref="O6:P6"'))),/single-cell array range/);
assert.throws(()=>validateDiscountWorksheet(strToU8(helper.replace(' t="array" ref="O6"',''))),/single-cell array range/);
assert.throws(()=>validateDiscountWorksheet(strToU8(helper.replace('<f>','<f t="shared" si="0">'))),/independent formulas/);
assert.throws(()=>validateDiscountWorksheet(strToU8(helper.replace('<f>','<f/>'))),/missing formula/);
assert.throws(()=>validateDiscountWorksheet(strToU8(helper.replace(' t="str"',''))),/cache type/);
assert.deepEqual(files['xl/worksheets/sheet1.xml'],before.get('xl/worksheets/sheet1.xml'));
const strip=x=>strFromU8(x).replace(/<c\b[^>]*r="(?:AJ|AO)\d+"[^>]*>[\s\S]*?<\/c>/g,'');
assert.equal(strip(files['xl/worksheets/sheet2.xml']),strip(before.get('xl/worksheets/sheet2.xml')));
files['xl/workbook.xml']=strToU8(strFromU8(files['xl/workbook.xml']).replace('</sheets>','<sheet name="명세서 검증" sheetId="9" r:id="rIdStatement"/></sheets>'));
files['xl/_rels/workbook.xml.rels']=strToU8(strFromU8(files['xl/_rels/workbook.xml.rels']).replace('</Relationships>','<Relationship Id="rIdStatement" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/statement-check.xml"/></Relationships>'));
files['[Content_Types].xml']=strToU8(strFromU8(files['[Content_Types].xml']).replace('</Types>','<Override PartName="/xl/worksheets/statement-check.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'));
files['xl/worksheets/statement-check.xml']=strToU8(sheet(inputs.map((v,i)=>{const r=v.row||i+6;return `<row r="${r}">${cell('A'+r,'LKS '+r)+f('B'+r,`IFERROR(INDEX('물품 입고 내역'!AD:AD,MATCH(A${r},'물품 입고 내역'!N:N,0)),0)`)+f('C'+r,`ROUND(4.5*B${r},3)`)+f('D'+r,`IFERROR(INDEX('물품 입고 내역'!AE:AE,MATCH(A${r},'물품 입고 내역'!N:N,0)),0)`)+f('E'+r,`ROUND(4.5*D${r},3)`)}</row>`;}).sort((a,b)=>Number(a.match(/r="(\d+)/)[1])-Number(b.match(/r="(\d+)/)[1])).join('')));
const firstResult=files['xl/worksheets/sheet2.xml'].slice(),firstHelper=files[helperPath].slice();applyDiscountMatching(files);assert.deepEqual(files['xl/worksheets/sheet2.xml'],firstResult);assert.deepEqual(files[helperPath],firstHelper);
function writeFixture(name,rs,rate=.2,special=false){
 // Change only the visible input cells AFTER installing the formulas. This
 // proves offline recalculation rather than generating a new matching cache.
 files['xl/worksheets/sheet1.xml']=strToU8(rowData(rs,rate,special));
 fs.writeFileSync(path.join(out,name+'.xlsx'),zipSync(files));
 fs.writeFileSync(path.join(out,name+'.json'),JSON.stringify(inputs.map((v,i)=>({...v,row:v.row||i+6,expected:special?0:expected(v,rs),expectedSpecial:special?expected(v,rs):0,rate:!special&&expected(v,rs)?rate:0,specialRate:special&&expected(v,rs)?rate:0})),null,2));
}
writeFixture('original',rules);
writeFixture('edited',[{...rules[0],customer_name:'새 회원',company_name:'새 회사',phone_display:'02011112222 / 02033334444 / 02077778888'},rules[1],rules[2]]);
writeFixture('air',rules,.05);
writeFixture('special',rules,.03,true);
if(process.argv.includes('--prepare-only')){console.log('Prepared native calculation fixtures');process.exit(0);}
for(const name of ['original','edited','air','special']){
 const resultDir=path.join(out,'recalculated');fs.mkdirSync(resultDir,{recursive:true});
 console.log(execFileSync('libreoffice',['-env:UserInstallation=file://'+path.join(out,'lo-profile'),'--headless','--convert-to','xlsx','--outdir',resultDir,path.join(out,name+'.xlsx')],{encoding:'utf8',timeout:120000}));
 const result=unzipSync(fs.readFileSync(path.join(resultDir,name+'.xlsx'))),xml=strFromU8(result['xl/worksheets/sheet2.xml']);
 const expectedRows=JSON.parse(fs.readFileSync(path.join(out,name+'.json')));
 for(const c of expectedRows){for(const [col,want] of [['AJ',c.expected],['AD',c.rate],['AO',c.expectedSpecial],['AE',c.specialRate]]){const tag=xml.match(new RegExp(`<c\\b[^>]*r="${col}${c.row}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0];assert.ok(tag,`Missing ${col}${c.row}`);const value=Number(tag.match(/<v>(.*?)<\/v>/)?.[1]);assert.equal(value,want,`${name}: ${c.name}, ${c.phone}: ${tag}`);}}
 const statement=strFromU8(result['xl/worksheets/sheet4.xml']||result['xl/worksheets/statement-check.xml']);
 for(const c of expectedRows)for(const [col,want] of [['B',c.rate],['C',Math.round(4.5*c.rate*1000)/1000],['D',c.specialRate],['E',Math.round(4.5*c.specialRate*1000)/1000]]){
  const tag=statement.match(new RegExp(`<c\\b[^>]*r="${col}${c.row}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0];assert.ok(tag,`Missing statement ${col}${c.row}`);assert.equal(Number(tag.match(/<v>(.*?)<\/v>/)?.[1]),want,`${name}: statement ${c.row} footer`);
 }
 console.log(`${name}: ${expectedRows.length} recalculated matches and statement footers passed`);
}
