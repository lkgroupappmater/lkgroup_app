import test from 'node:test';import assert from 'node:assert/strict';import {commonFooter,workbookIndex} from './workbook-copy.mjs';
const cell=(ref,text)=>`<c r="${ref}" t="inlineStr"><is><t>${text}</t></is></c>`;
test('only common footer text is extracted; private and normal statement Remarks are excluded',()=>{
 const xml='<worksheet><sheetData><c r="A1"/>'+cell('L2','private customer')+cell('A11','합 계')+cell('A12','Remark/비 고')+cell('A13','* private statement remark')+cell('A21','* New common notice')+cell('A22','* Storage terms updated')+cell('B23','* customer address')+'</sheetData></worksheet>';
 assert.deepEqual(commonFooter(xml),['* New common notice','* Storage terms updated']);
});
test('unrecognized layout and formulas never become a footer',()=>{assert.equal(commonFooter(cell('A21','* private cargo note')),null);assert.equal(commonFooter(cell('A11','합 계')+cell('A12','Remark')+'<c r="A21" t="str"><f>Customer!A1</f><v>* Customer detail</v></c>'),null)});
test('shared strings and empty cells preserve exact edited common text',()=>{const xml='<c r="A1"/>'+cell('A11','Total')+cell('A12','Remark')+'<c r="A21" t="s"><v>0</v></c>';assert.deepEqual(commonFooter(xml,'<sst><si><r><t>* Fee &amp; </t></r><r><t>storage notice</t></r></si></sst>'),['* Fee & storage notice']);});
