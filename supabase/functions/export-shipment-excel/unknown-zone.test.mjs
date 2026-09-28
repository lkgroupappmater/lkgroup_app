import test from 'node:test';import assert from 'node:assert/strict';
import {applyUnknownPrefixZones,unknownPrefixZone} from './unknown-zone.mjs';
import {validateWorkbookFormulas} from './workbook-integrity.mjs';
const e=new TextEncoder(),d=new TextDecoder();
test('identified unknown recipients remain F without changing ordinary or pickup rules',()=>{
 for(const n of ['수취인 불명 / 고객',' 수취인불명／고객','수취인 불명'])assert.equal(unknownPrefixZone(n),true);
 for(const n of ['고객','비엔티엔 픽업 / 고객','고객/수취인 불명'])assert.equal(unknownPrefixZone(n),false);
 const path='xl/worksheets/sheet1.xml',original='IF(N6="","",VLOOKUP(N6,Zones,3,FALSE))';
 const files={[path]:e.encode(`<worksheet><sheetData><row r="6"><c r="E6" t="inlineStr"><is><t>수취인 불명 / 고객</t></is></c><c r="O6" t="str"><f>${original}</f><v>A</v></c><c r="N6" t="str"><v>LKS 75</v></c></row></sheetData></worksheet>`)};
 const options={sheetPath:(_,n)=>n==='물품 입고 내역'?path:null,cellText:c=>c.match(/<t>(.*?)<\/t>|<v>(.*?)<\/v>/)?.slice(1).find(Boolean)||''};
 applyUnknownPrefixZones(files,options);const first=d.decode(files[path]);
 assert.ok(first.includes(original));assert.match(first,/<v>F<\/v>/);assert.match(first,/LKS 75/);
 applyUnknownPrefixZones(files,options);assert.equal(d.decode(files[path]),first);
 assert.equal(validateWorkbookFormulas(files).shared_formula_errors,0);
});
