import {test} from 'node:test';
import assert from 'node:assert/strict';
import {copySharedDeliveryLayout} from '../supabase/functions/export-shipment-excel/shared-delivery-layout.mjs';
const b=s=>new TextEncoder().encode(s),s=b=>new TextDecoder().decode(b);
function fixture(source=false){
 const p=source?'sheet7':'sheet2';
 const files={
 'xl/workbook.xml':b(`<workbook><sheets><sheet name="운임" sheetId="1" r:id="rId1"/><sheet name="지방배송" sheetId="2" r:id="rId2"/></sheets><definedNames><definedName name="_xlnm.Print_Area" localSheetId="1">'지방배송'!$A$1:$H$${source?8:4}</definedName><definedName name="RouteRate">'운임'!$A$1</definedName></definedNames></workbook>`),
 'xl/_rels/workbook.xml.rels':b(`<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/${p}.xml"/></Relationships>`),
 'xl/styles.xml':b(`<styleSheet><numFmts count="1"><numFmt numFmtId="164" formatCode="${source?'0.0':'0.00'}"/></numFmts><fonts count="1"><font><name val="${source?'SourceFont':'TargetFont'}"/></font></fonts><fills count="1"><fill><patternFill patternType="solid"><fgColor rgb="FF00FF00"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><dxfs count="1"><dxf><font><b/></font></dxf></dxfs></styleSheet>`),
 'xl/worksheets/sheet1.xml':b('<worksheet><sheetData><row r="1"><c r="A1" s="0"><f>3*7</f><v>21</v></c></row></sheetData></worksheet>'),
 'xl/sharedStrings.xml':b('<sst><si><t>Customer</t></si><si><r><t>HAL</t></r></si><si><t>ANS</t></si></sst>'),
 'xl/vbaProject.bin':new Uint8Array([1,2,3]),
 '[Content_Types].xml':b('<Types><Default Extension="bin" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.printerSettings"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>')
 };
 files[`xl/worksheets/${p}.xml`]=b(`<worksheet><sheetPr codeName="${source?'SourceCode':'TargetCode'}"/><dimension ref="A1:AD8"/><cols><col min="1" max="8" width="${source?22:10}" style="0"/></cols><sheetData><row r="3" ht="33" customHeight="1"><c r="A3"><v>1</v></c><c r="B3" t="s"><v>0</v></c><c r="F3" t="s"><v>1</v></c><c r="G3" t="inlineStr"><is><t>first address</t></is></c><c r="H3" t="inlineStr"><is><t>사용</t></is></c><c r="AD3"><f>IF(H3="사용",1,0)</f><v>1</v></c></row>${source?'<row r="4" ht="44"><c r="F4" t="s"><v>2</v></c><c r="G4" s="0"/><c r="H4" s="0"/></row><row r="5" ht="20"><c r="F5" t="inlineStr"><is><t>Third carrier</t></is></c></row>':''}</sheetData><mergeCells count="1"><mergeCell ref="A3:A5"/></mergeCells><conditionalFormatting sqref="A3:H5"><cfRule type="expression" dxfId="0"><formula>H3="사용"</formula></cfRule></conditionalFormatting><dataValidations count="1"><dataValidation sqref="H3:H8" type="list"><formula1>"사용,"</formula1></dataValidation></dataValidations><pageSetup r:id="rId1"/></worksheet>`);
 files[`xl/worksheets/_rels/${p}.xml.rels`]=b('<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/printerSettings" Target="../printerSettings/printerSettings2.bin"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://maps.example.test/delivery" TargetMode="External"/></Relationships>');
 files['xl/printerSettings/printerSettings2.bin']=new Uint8Array(source?[8,9]:[4,5]);return files;
}
test('copies every carrier, blank slot, order and complete sheet geometry',()=>{
 const dst=fixture(),src=fixture(true),before=structuredClone(dst),result=copySharedDeliveryLayout(dst,src),xml=s(dst['xl/worksheets/sheet2.xml']);
 assert.equal(result[0].rows,3);assert.ok(xml.indexOf('HAL')<xml.indexOf('ANS'));assert.match(xml,/Third carrier/);assert.match(xml,/<c r="G4" s="\d+"\/>/);
 assert.match(xml,/ht="44"/);assert.match(xml,/width="22"/);assert.match(xml,/A3:A5/);assert.match(xml,/H3:H8/);assert.match(xml,/codeName="TargetCode"/);assert.doesNotMatch(xml,/t="s"/);
 for(const path of ['xl/worksheets/sheet1.xml','xl/vbaProject.bin','xl/sharedStrings.xml','xl/printerSettings/printerSettings2.bin'])assert.deepEqual(dst[path],before[path]);
 assert.match(s(dst['xl/workbook.xml']),/\$H\$8/);assert.match(s(dst['xl/workbook.xml']),/RouteRate/);
 assert.deepEqual(dst['xl/lk_delivery_layout/province/xl/printerSettings/printerSettings2.bin'],src['xl/printerSettings/printerSettings2.bin']);
 assert.match(s(dst['xl/worksheets/_rels/sheet2.xml.rels']),/TargetMode="External"/);
});
test('remaps styles without changing existing style IDs or accumulating duplicates',()=>{
 const dst=fixture(),src=fixture(true);copySharedDeliveryLayout(dst,src);const once=s(dst['xl/styles.xml']);
 assert.match(once,/TargetFont/);assert.match(once,/SourceFont/);assert.match(once,/numFmtId="165" formatCode="0.0"/);
 assert.match(s(dst['xl/worksheets/sheet1.xml']),/s="0"/);
 copySharedDeliveryLayout(dst,src);assert.equal(s(dst['xl/styles.xml']),once);
});
test('fails before publishing unsupported embedded objects',()=>{
 const dst=fixture(),src=fixture(true);src['xl/worksheets/_rels/sheet7.xml.rels']=b('<Relationships><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/oleObject" Target="../embedded.bin"/></Relationships>');
 assert.throws(()=>copySharedDeliveryLayout(dst,src),/Unsupported/);
});
