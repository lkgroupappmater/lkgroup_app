import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applyTaxStatementColors,stripStatementPresentation} from './statement-tax-colors.mjs';
const enc=s=>new TextEncoder().encode(s),dec=b=>new TextDecoder().decode(b);
test('tax customers use gray before delivery fills, preserving every cell and formula',()=>{
 const files={
 'xl/workbook.xml':enc('<workbook><sheets><sheet name="고객 리스트" r:id="r1"/><sheet name="물품 입고 내역" r:id="r2"/><sheet name="LKA 01" r:id="r3"/></sheets></workbook>'),
 'xl/_rels/workbook.xml.rels':enc('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/><Relationship Id="r3" Target="worksheets/sheet3.xml"/></Relationships>'),
 'xl/styles.xml':enc('<styleSheet><dxfs count="1"><dxf/></dxfs></styleSheet>'),
 'xl/worksheets/sheet1.xml':enc('<worksheet><sheetData><row r="4"><c r="A4" t="str"><f>bill()</f><v>LKA 01</v></c></row></sheetData><conditionalFormatting sqref="E4"><cfRule priority="1" dxfId="0"/></conditionalFormatting><pageMargins/></worksheet>'),
 'xl/worksheets/sheet2.xml':enc('<worksheet><sheetData><row r="6"><c r="N6" t="str"><v>LKA 01</v></c><c r="P6" t="str"><v>영세율 세금 계산서</v></c></row></sheetData></worksheet>'),
 'xl/worksheets/sheet3.xml':enc('<worksheet><sheetPr codeName="Sheet3"/><sheetData><row r="6"><c r="R6"><v>16</v></c></row></sheetData></worksheet>')
 };
 const before={...files};assert.equal(applyTaxStatementColors(files),3);
 const customers=dec(files['xl/worksheets/sheet1.xml']);assert.match(customers,/sqref="A4:E4"/);assert.match(customers,/dxfId="1" priority="1" stopIfTrue="1"/);
 assert.match(customers,/IFERROR\(SUMPRODUCT/);assert.match(customers,/세금계산서/);assert.match(dec(files['xl/styles.xml']),/<dxfs count="2"><dxf\/>/);
 assert.match(dec(files['xl/worksheets/sheet3.xml']),/<tabColor rgb="FFBFBFBF"\/>/);
 for(const p of ['xl/worksheets/sheet1.xml','xl/worksheets/sheet2.xml','xl/worksheets/sheet3.xml'])assert.equal(stripStatementPresentation(dec(files[p])),stripStatementPresentation(dec(before[p])));
 assert.equal(applyTaxStatementColors(files),0);
 // Regenerating a larger BASE must grow both ranges without accumulating rules.
 files['xl/worksheets/sheet2.xml']=enc(dec(files['xl/worksheets/sheet2.xml']).replace('</sheetData>','<row r="30"><c r="N30"><v>0</v></c></row></sheetData>'));
 files['xl/worksheets/sheet1.xml']=enc(dec(files['xl/worksheets/sheet1.xml']).replace('</sheetData>','<row r="9"><c r="A9"><v>0</v></c></row></sheetData>'));
 assert.equal(applyTaxStatementColors(files),1);
 const expanded=dec(files['xl/worksheets/sheet1.xml']);assert.match(expanded,/sqref="A4:E9"/);assert.match(expanded,/\$P\$6:\$P\$30/);
 assert.equal((expanded.match(/LK_TAX_CUSTOMER_GRAY_V1/g)||[]).length,1);assert.match(expanded,/priority="2" dxfId="0"/);
 assert.equal(applyTaxStatementColors(files),0);
});
