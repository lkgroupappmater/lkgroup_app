import test from 'node:test';
import assert from 'node:assert/strict';
import {freightFromSheets,readCells} from './workbook-freight.mjs';
const s=(r,v)=>'<c r="'+r+'" t="inlineStr"><is><t>'+v+'</t></is></c>';
const n=(r,v,f)=>'<c r="'+r+'">'+(f?'<f>'+f.replaceAll('&','&amp;').replaceAll('>','&gt;')+'</f>':'')+(v===null?'':'<v>'+v+'</v>')+'</c>';
function fixture(){
 const row=readCells(s('C7','최소값')+s('D7','적용 운임')+n('C8',0)+n('D8',58.8,'Sheet1!M3')+n('C9',2)+n('D9',18.1,'Sheet1!M6'));
 const form=readCells(n('C6',18.1,"VLOOKUP(MAX(E6,J6),'Row data'!$C$8:$D$9,2,TRUE)")+n('L6',null,"(IF(0=F6*C6,0,IF('Row data'!$D$8*D6>=C6*F6,'Row data'!$D$8*D6,C6*F6)))")+n('J6',null,'(G6*H6*I6)*0.00022'));
 return [{name:'Row data',cells:row},{name:'이름(LTxx-xx)',cells:form}];
}
test('linked formula values, tier thresholds and per-cargo minimum match the source workbook',()=>{
 const p=freightFromSheets(fixture());
 assert.deepEqual(p.tiers,[{min_weight_kg:0,rate_per_kg:58.8},{min_weight_kg:2,rate_per_kg:18.1}]);assert.equal(p.minimum_charge,58.8);assert.equal(p.volumetric_factor,.00022);
 const amount=w=>Math.max(w*(w>=2?18.1:58.8),p.minimum_charge);
 assert.equal(amount(.5),58.8);assert.equal(amount(2),58.8);assert.equal(amount(5),90.5);
});
test('invalid, missing cached, duplicate, unsorted and nonzero first tiers fail before DB writes',()=>{
 for(const [ref,value] of [['D8',''],['D8','#VALUE!'],['C9',0],['C8',1],['D9',-1]]){
 const f=fixture();f[0].cells.get(ref).value=value;assert.throws(()=>freightFromSheets(f));
 }
});
test('minimum uses actual formula reference, not out-of-date footer text or arbitrary first rate',()=>{
 const f=fixture();f[0].cells.set('D20',{ref:'D20',value:20});f[1].cells.get('L6').formula='IF(F6="","",MAX(\'Row data\'!$D$20*D6,C6*F6))';
 assert.equal(freightFromSheets(f).minimum_charge,20);
});
test('flat-rate route supports numeric rate, minimum formula and changed volume factor',()=>{
 const f=fixture();f[0].cells=new Map();f[1].cells.get('C6').formula='14';f[1].cells.get('L6').formula='IF(F6="","",MAX(14*D6,C6*F6))';f[1].cells.get('J6').formula='(G6*H6*I6)*0.00025';
 const p=freightFromSheets(f);assert.deepEqual(p.tiers,[{min_weight_kg:0,rate_per_kg:14}]);assert.equal(p.volumetric_factor,.00025);
});
test('mismatched form minima fail instead of picking the first form',()=>{
 const f=fixture();f.push({name:'LKA XX',cells:readCells(n('L6',null,'IF(F6="","",MAX(14*D6,C6*F6))'))});assert.throws(()=>freightFromSheets(f));
});
test('guarded air/sea rate formulas preserve blank rows while supplying the common rate',()=>{
 const f=fixture();f[0].cells=new Map();f[1].cells.get('C6').formula='IF(" "=D6," ",IF(0<D6,3.2))';f[1].cells.get('L6').formula='IF(F6="","",MAX(3.2*D6,C6*F6))';
 assert.deepEqual(freightFromSheets(f).tiers,[{min_weight_kg:0,rate_per_kg:3.2}]);
 f.push({name:'명세서 고객 ID 연결',cells:readCells(n('C6',456))},{name:'명세서 번호 관리',cells:readCells(n('C6',999))});
 f[1].cells.get('J6').formula='IFERROR((G6*H6*I6)*0.00022," ")';
 assert.deepEqual(freightFromSheets(f).tiers,[{min_weight_kg:0,rate_per_kg:3.2}]);
 f[1].cells.get('C6').formula='IF(D6="","",3.2)';
 f[1].cells.get('J6').formula='IF(G6="","",G6*H6*I6*0.00022)';
 f[1].cells.set('M20',{ref:'M20',formula:'MAX(0,SUM(N6:N10)-L20)',value:''});
 assert.equal(freightFromSheets(f).tiers[0].rate_per_kg,3.2);
 f[1].cells.set('C7',{ref:'C7',formula:'IF(D7="","",12)',value:''});
 assert.throws(()=>freightFromSheets(f),/C열 단가가 서로 다릅니다/);
});
