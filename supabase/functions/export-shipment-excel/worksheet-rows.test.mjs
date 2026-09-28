import test from 'node:test';
import assert from 'node:assert/strict';
import {rewriteWorksheetRows,worksheetIdentityRange} from './worksheet-rows.mjs';
test('chunked worksheets preserve UTF-8, row boundaries and trailing XML',()=>{
 const e=new TextEncoder(),d=new TextDecoder();
 const source='<worksheet><cols></cols><sheetData>'+Array.from({length:18},(_,i)=>`<row r="${i+6}"><c r="E${i+6}" t="inlineStr"><is><t>${'한글ລາວ🙂'.repeat(1300)}</t></is></c><c r="AB${i+6}"><f>ROW()</f><v>${i}</v></c></row>`).join('')+'</sheetData><extLst>unchanged</extLst></worksheet>';
 const expected=source.replace('<cols></cols>','<cols><col min="53" max="64" hidden="1"/></cols>').replace(/<v>(\d+)<\/v>/g,(_,n)=>`<v>${Number(n)+1}</v>`);
 for(const input of [source,e.encode(source)]){
  const actual=rewriteWorksheetRows(input,row=>row.replace(/<v>(\d+)<\/v>/g,(_,n)=>`<v>${Number(n)+1}</v>`),header=>header.replace('<cols></cols>','<cols><col min="53" max="64" hidden="1"/></cols>'));
  assert.equal(d.decode(actual),expected);
  assert.deepEqual(worksheetIdentityRange(input),{hasRanking:true,last:23});
 }
});
