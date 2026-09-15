import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const root=new URL('.',import.meta.url).pathname;
const fixtureDir=process.argv[2];
if(!fixtureDir) throw new Error('Provide the temporary cached-fixture directory. Originals must not be overwritten.');
const recipe=JSON.parse(await fs.readFile(root+'/formulas.json','utf8'));
const expand=(f,vars)=>f.replace(/\{(\w+)\}/g,(_,k)=>String(vars[k]));
const report=[];
for(const prefix of ['LKS','LKA']) {
  // Disposable cached copy: unrelated heavy legacy formulas are not recalculated.
  // Original XLSM/VBA/drawings are never exported through this test fixture.
  const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(`${fixtureDir}/${prefix}-cached.xlsx`));
  const incoming=wb.worksheets.getItem('물품 입고 내역');
  const form=wb.worksheets.getItem(prefix+' 01');
  const input=wb.worksheets.add(recipe.inputSheet);
  const sourceEnd=prefix==='LKS'?1005:205;
  incoming.getRange(`N6:N${sourceEnd}`).clear({applyTo:'contents'});
  input.getRange('A4:G4').values=[['영수번호','배송구분','비용 이름','금액 USD','할인 적용','고객명','입력 상태']];
  input.getRange('A5').values=[[prefix+'01']];
  input.getRange('E5').values=[['미적용']];
  for(const [col,f] of Object.entries(recipe.inputFormulas)) input.getRange(col+'5').formulas=[[expand(f,{row:5,sourceEnd})]];
  form.getRange('N2').values=[[prefix+'01']];
  for(const [ref,f] of Object.entries(recipe.helpers)) form.getRange(ref).formulas=[[expand(f,{sourceEnd})]];
  // Keep the template's 10 cargo slots for the rendered 9-cargo case.
  const setDetail=(end)=>{
    for(let row=6;row<=end;row++){
      form.getRange('A'+row).values=[[row-5]];
      for(const [col,f] of Object.entries(recipe.detailFormulas)) form.getRange(col+row).formulas=[[expand(f,{row,sourceEnd})]];
    }
  };
  setDetail(15);
  form.getRange('N17').formulas=[['=SUM(N6:N15)']];
  form.getRange('N18').formulas=[[expand(recipe.automaticDiscount,{grossRow:17,autoRow:18})]];
  form.getRange('N19').formulas=[[expand(recipe.fixedDiscount,{grossRow:17,autoRow:18,fixedRow:19})]];
  form.getRange('N21').formulas=[['=N17-N18-N19']];
  const value=(ref)=>form.getRange(ref).values[0][0];
  const cases=[
    {name:'province-default',kind:'지방배송(선결재)',amount:20,rate:0.2,fixed:0,flag:'미적용',expected:92,label:'지방배송'},
    {name:'city-default',kind:'시내배송(선결제)',amount:20,rate:0.2,fixed:0,flag:'미적용',expected:92,label:'시내배송'},
    {name:'explicit-discount',kind:'지방배송(선결제)',amount:20,rate:0.2,fixed:0,flag:'적용',expected:88,label:'지방배송'},
    {name:'full-freight-discount',kind:'시내배송(선불)',amount:20,rate:1,fixed:0,flag:'미적용',expected:20,label:'시내배송'},
    {name:'oversize-fixed-discount',kind:'지방배송(선결제)',amount:20,rate:0.2,fixed:500,flag:'미적용',expected:20,label:'지방배송'},
    {name:'blank-not-zero',kind:'시내배송(선결제)',amount:null,rate:0.2,fixed:0,flag:'미적용',expected:72,label:'시내배송'},
    {name:'explicit-zero',kind:'시내배송(선결제)',amount:0,rate:0.2,fixed:0,flag:'미적용',expected:72,label:'시내배송'},
    {name:'ordinary-no-fee',kind:'지방배송',amount:20,rate:0.2,fixed:0,flag:'미적용',expected:72,label:''},
  ];
  for(const scenario of cases){
    for(let r=6;r<=14;r++) {
      incoming.getRange('A'+r).values=[[prefix+'01_'+(r-5)]];
      incoming.getRange('B'+r).values=[['CARGO-'+(r-5)]];
      incoming.getRange('N'+r).values=[[prefix+'01']];
      incoming.getRange('R'+r).values=[[scenario.kind]];
      form.getRange('L'+r+':M'+r).values=[[10,0]];
    }
    form.getRange('L15:M15').values=[['','']];
    form.getRange('M18').values=[[scenario.rate]];form.getRange('M19').values=[[scenario.fixed]];
    input.getRange('D5').values=[[scenario.amount]];input.getRange('E5').values=[[scenario.flag]];
    wb.recalculate();
    assert.ok(Math.abs(Number(value('N21'))-scenario.expected)<1e-8,`${prefix} ${scenario.name}: ${value('N21')} != ${scenario.expected}`);
    assert.equal(value('B15'),scenario.label);
    if(scenario.name==='blank-not-zero') assert.equal(value('N15'),'');
    if(scenario.name==='explicit-zero') assert.equal(value('N15'),0);
    report.push({route:prefix,case:scenario.name,netUsd:value('N21'),passed:true});
  }
  // Formula row placement independently covers the native macro's 10/11 cargo edge.
  for(const count of [0,9,10,11]){
    incoming.getRange(`N6:N${sourceEnd}`).clear({applyTo:'contents'});
    if(count) incoming.getRange(`N6:N${5+count}`).values=[[prefix+'01']];
    input.getRange('C5').values=[['시내배송']];input.getRange('D5').values=[[20]];
    const row=6+count;setDetail(row);wb.recalculate();
    assert.equal(value('B'+row),'시내배송');assert.equal(value('N'+row),20);
    report.push({route:prefix,case:`last-cargo-${count}`,deliveryRow:row,passed:true});
  }
  input.getRange('A4:G4').format.fill='#183B63';input.getRange('A4:G4').format.font.color='#FFFFFF';
  input.getRange('A:G').format.columnWidth=21;
  input.getRange('C5:E5').format.fill='#FFF1D6';input.getRange('D5').setNumberFormat('#,##0.00');
  input.getRange('E5:E205').dataValidation={rule:{type:'list',values:['미적용','적용']}};
  wb.recalculate();
  const image=await wb.render({sheetName:recipe.inputSheet,range:'A4:G6',scale:1.5});
  await fs.writeFile(`${fixtureDir}/${prefix}-inputs.png`,new Uint8Array(await image.arrayBuffer()));
  const output=await SpreadsheetFile.exportXlsx(wb);
  await output.save(`${fixtureDir}/${prefix}-formula-verification.xlsx`);
  console.log(prefix,'12 scenarios passed');
}
await fs.writeFile(root+'/formula-validation.json',JSON.stringify({engine:'Artifact Tool',originalXlsmModified:false,nativeExcelMacroVerified:false,scenarios:report},null,2)+'\n');
