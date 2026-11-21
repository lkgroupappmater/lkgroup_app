import {test} from 'node:test';
import assert from 'node:assert/strict';
import {discardCalculationChain,validateWorkbookPackage} from './workbook-package.mjs';
const enc=new TextEncoder(),dec=new TextDecoder();
function fixture(){return Object.fromEntries(Object.entries({
 '[Content_Types].xml':'<Types><Default Extension="rels" ContentType="relationships"/><Default Extension="xml" ContentType="xml"/><Override PartName="/xl/calcChain.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.calcChain+xml"/></Types>',
 '_rels/.rels':'<Relationships><Relationship Id="book" Target="xl/workbook.xml"/></Relationships>',
 'xl/workbook.xml':'<workbook><sheets><sheet name="Test" sheetId="1" r:id="sheet"/></sheets></workbook>',
 'xl/_rels/workbook.xml.rels':'<Relationships><Relationship Id="sheet" Target="worksheets/sheet1.xml"/><Relationship Id="calc" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/calcChain" Target="calcChain.xml"/></Relationships>',
 'xl/calcChain.xml':'<calcChain><c r="A1" i="1"/></calcChain>',
 'xl/worksheets/sheet1.xml':'<worksheet><sheetData><row r="1"><c r="A1" s="1"><f>1+1</f><v>2</v></c></row></sheetData></worksheet>',
}).map(([k,v])=>[k,enc.encode(v)]));}
test('discard the chain part and both links together, preserving every worksheet byte',()=>{
 const files=fixture(),sheet=files['xl/worksheets/sheet1.xml'];assert.equal(validateWorkbookPackage(files).package_errors,0);
 assert.deepEqual(discardCalculationChain(files),{parts:1,relationships:1,content_types:1});assert.deepEqual(files['xl/worksheets/sheet1.xml'],sheet);
 assert.equal(validateWorkbookPackage(files).package_errors,0);assert.deepEqual(discardCalculationChain(files),{parts:0,relationships:0,content_types:0});
});
test('detect and repair the exporter regression where unzip omitted only calcChain.xml',()=>{
 const files=fixture();delete files['xl/calcChain.xml'];assert.throws(()=>validateWorkbookPackage(files),/target not found/);
 assert.deepEqual(discardCalculationChain(files),{parts:0,relationships:1,content_types:1});assert.equal(validateWorkbookPackage(files).package_errors,0);
});
test('reject missing drawings, stale content types and duplicate relationship IDs',()=>{
 for(const kind of ['drawing','type','duplicate']){
  const files=fixture(),path=kind==='type'?'[Content_Types].xml':'xl/_rels/workbook.xml.rels';
  let xml=dec.decode(files[path]);xml=kind==='type'?xml.replace('</Types>','<Override PartName="/xl/missing.xml" ContentType="xml"/></Types>'):xml.replace('</Relationships>',`<Relationship Id="${kind==='duplicate'?'sheet':'drawing'}" Target="${kind==='duplicate'?'worksheets/sheet1.xml':'drawings/missing.xml'}"/></Relationships>`);files[path]=enc.encode(xml);
  assert.throws(()=>validateWorkbookPackage(files),/not found|duplicated/);
 }
});
test('external URLs and percent-encoded internal part names are resolved correctly',()=>{
 const files=fixture();files['xl/media/photo one.png']=enc.encode('image');
 files['[Content_Types].xml']=enc.encode(dec.decode(files['[Content_Types].xml']).replace('</Types>','<Default Extension="png" ContentType="image/png"/></Types>'));
 files['xl/worksheets/_rels/sheet1.xml.rels']=enc.encode('<Relationships><Relationship Id="url" Target="https://example.com/?a=1&amp;b=2" TargetMode="External"/><Relationship Id="photo" Target="../media/photo%20one.png"/></Relationships>');
 assert.equal(validateWorkbookPackage(files).package_errors,0);
});
