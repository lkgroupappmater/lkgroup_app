import {test} from 'node:test';
import assert from 'node:assert/strict';
import {captureSharedFormulaMasters,restoreSharedFormulaMasters,recoverDeliverySelectorMasters,translateFormula,validateWorkbookFormulas} from './workbook-integrity.mjs';
const e=new TextEncoder(),d=new TextDecoder(),path='xl/worksheets/sheet2.xml';
const wrap=s=>`<worksheet><sheetData>${s}</sheetData></worksheet>`;
test('copying a shared master preserves absolute references, strings, names and sheets',()=>{
 assert.equal(translateFormula('IF(A1="A1",SUM($A$1,A$1,$A1,\'A1 sheet\'!A1,Sheet1!A1),LOG10(A1))+Table1[A1]','A1','B3'),'IF(B3="A1",SUM($A$1,B$1,$A3,\'A1 sheet\'!B3,Sheet1!B3),LOG10(B3))+Table1[A1]');
});
test('overwriting master reanchors surviving formulas and preserves their caches',()=>{
 const files={[path]:e.encode(wrap('<row r="2"><c r="H2"><f t="shared" si="7" ref="H2:H4">T2+$G$3</f><v>8</v></c></row><row r="3"><c r="H3"><f t="shared" si="7"/><v>9</v></c></row><row r="4"><c r="H4"><f t="shared" si="7"/><v>10</v></c></row>'))};
 const before=captureSharedFormulaMasters(files);files[path]=e.encode(d.decode(files[path]).replace(/<c r="H2">[\s\S]*?<\/c>/,'<c r="H2" t="inlineStr"><is><t>사용</t></is></c>'));
 assert.throws(()=>validateWorkbookFormulas(files),/0 masters/);
 assert.equal(restoreSharedFormulaMasters(files,before),1);
 assert.match(d.decode(files[path]),/ref="H3:H4">T3\+\$G\$3<\/f><v>9/);
 assert.equal(validateWorkbookFormulas(files).shared_formula_errors,0);
 assert.equal(restoreSharedFormulaMasters(files,before),0);
});
test('recover only demonstrated delivery selectors and reject unknown orphans',()=>{
 const f='IF(AND(T226&lt;&gt;&quot;&quot;,G226&lt;&gt;&quot;&quot;,COUNTIFS($T$3:$T$800,T226,$G$3:$G$800,&quot;&lt;&gt;&quot;)=1),&quot;사용&quot;,&quot;&quot;)';
 const files={[path]:e.encode(wrap(`<row r="113"><c r="H113"><f t="shared" si="23"/><v/></c></row><row r="226"><c r="H226"><f t="shared" si="47" ref="H226:H226">${f}</f><v/></c></row>`))};
 assert.equal(recoverDeliverySelectorMasters(files,(_,name)=>name==='지방배송'?path:null),1);
 assert.match(d.decode(files[path]),/ref="H113:H113">IF\(AND\(T113/);
 assert.equal(validateWorkbookFormulas(files).shared_formula_errors,0);
 const unknown={[path]:e.encode(wrap('<row r="113"><c r="H113"><f t="shared" si="23"/><v/></c></row>'))};
 assert.equal(recoverDeliverySelectorMasters(unknown,()=>path),0);assert.throws(()=>validateWorkbookFormulas(unknown),/0 masters/);
});
test('reject duplicate masters, out-of-range followers and duplicate caches',()=>{
 for(const xml of ['<c r="A1"><f t="shared" si="1" ref="A1:A2">B1</f></c><c r="A2"><f t="shared" si="1" ref="A1:A2">B2</f></c>','<c r="A1"><f t="shared" si="1" ref="A1:A2">B1</f></c><c r="A3"><f t="shared" si="1"/></c>','<c r="A1"><f>B1</f><v>1</v><v>2</v></c>'])assert.throws(()=>validateWorkbookFormulas({[path]:e.encode(wrap(xml))}));
});
