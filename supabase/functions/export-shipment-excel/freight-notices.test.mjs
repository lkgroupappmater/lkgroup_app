import test from 'node:test';
import assert from 'node:assert/strict';
import {freightNoticePeriod,refreshFreightNotices} from './freight-notices.mjs';
import {captureStatementNotices} from './statement-notice-format.mjs';
import {canReuseValidatedBase} from './validated-base.mjs';

const bytes = s => new TextEncoder().encode(s);
const text = b => new TextDecoder().decode(b);
const sheetPath = 'xl/worksheets/sheet2.xml';
const header = (ref,label) => `<c r="${ref}" t="inlineStr"><is><t>${label}</t></is></c>`;
function fixture() {
  return {
    'xl/workbook.xml':bytes('<workbook><sheets><sheet name="Row data" r:id="r1"/><sheet name="이름(LVxx-xx)" r:id="r2"/></sheets></workbook>'),
    'xl/_rels/workbook.xml.rels':bytes('<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="worksheets/sheet2.xml"/></Relationships>'),
    'xl/worksheets/sheet1.xml':bytes('<worksheet><sheetData><row r="12">'+header('B12','최소값')+header('D12','적용 운임')+'</row><row r="13"><c r="B13"><v>0</v></c><c r="D13"><f>Sheet1!F3</f><v>23.75</v></c></row><row r="14"><c r="B14"><v>2</v></c><c r="D14"><v>15.2</v></c></row></sheetData></worksheet>'),
    'xl/sharedStrings.xml':bytes('<sst><si><t>* 모든 비용은 실측 기준이며 최소 운임은 $9.9/kg 입니다.</t></si></sst>'),
    [sheetPath]:bytes('<worksheet><sheetData><row r="13">'+header('A13','- valid end of Oct/2026.\n- 기한: 2026년 10월 말, 2025년 계약')+'</row><row r="21" ht="39.6"><c r="A21" s="17" t="s"><v>0</v></c></row><row r="22">'+header('A22','* 보관료 최소 3불/CBM/day')+'</row></sheetData><mergeCells><mergeCell ref="A21:N21"/></mergeCells></worksheet>'),
  };
}
test('Lao month at midnight, including year change',()=>{
  assert.equal(freightNoticePeriod(new Date('2026-09-30T17:00:00Z')),'2026-10');
  assert.equal(freightNoticePeriod(new Date('2026-11-30T17:00:00Z')),'2026-12');
  assert.equal(freightNoticePeriod(new Date('2026-12-31T16:59:59Z')),'2026-12');
  assert.equal(freightNoticePeriod(new Date('2026-12-31T17:00:00Z')),'2027-01');
});
test('printed tariff link, period and cache retain template styles, other dates and charges',()=>{
  const files=fixture(), options={period:'2026-12',routeRate:23.75};
  const originalTable=files['xl/worksheets/sheet1.xml'];
  const report=refreshFreightNotices(files,options), output=text(files[sheetPath]);
  assert.deepEqual([report.deadline_cells,report.minimum_cells,report.one_kg_rate],[1,1,23.75]);
  assert.match(output,/Dec\/2026/); assert.match(output,/2026년 12월 말, 2025년 계약/);
  assert.match(output,/s="17" t="str"/); assert.match(output,/&amp;'Row data'!\$D\$13&amp;/);
  assert.match(output,/\$23\.75\/kg/); assert.match(output,/최소 3불\/CBM\/day/);
  assert.deepEqual(files['xl/worksheets/sheet1.xml'],originalTable);
  assert.ok(captureStatementNotices(files)[0].notices[0].formula);
  assert.equal(refreshFreightNotices(files,options).changed,0);
  files[sheetPath]=bytes(output.replace(/<v>\*[^<]+<\/v>/,''));
  assert.equal(refreshFreightNotices(files,options).changed,1);
  assert.equal(text(files[sheetPath]),output);
});
test('DB price-only edit overrides stale BASE notice, voyage keeps its own band',()=>{
  const opts={period:'2027-01',routeRate:27.45};
  const base=fixture(),voyage=fixture();
  refreshFreightNotices(base,opts);
  refreshFreightNotices(voyage,{...opts,useWorkbookRate:true});
  assert.match(text(base[sheetPath]),/\$27\.45\/kg/);
  assert.match(text(voyage[sheetPath]),/\$23\.75\/kg/);
  assert.match(text(voyage[sheetPath]),/Jan\/2027/);
});
test('cached BASE with dated terms expires only on a new Lao calendar month',()=>{
  const sync={status:'ready',revision:3,completed_revision:3};
  const info={period:'2026-10',deadline_cells:1};
  const base={storage_path:'base/test/file.xlsx',policy_summary:{automation_version:'v',validated_source_revision:3,integrity:{stored_download_verified:true,shared_formula_errors:0,freight_notices:info}}};
  assert.equal(canReuseValidatedBase(base,sync,'v','2026-10'),true);
  assert.equal(canReuseValidatedBase(base,sync,'v','2026-12'),false);
  info.deadline_cells=0;
  assert.equal(canReuseValidatedBase(base,sync,'v','2026-12'),true);
});
