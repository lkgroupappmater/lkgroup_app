$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$project = (Get-Location).Path

function Replace-Once([string]$path,[string]$old,[string]$new) {
  $text = [IO.File]::ReadAllText($path)
  if (-not $text.Contains($old)) { throw "Patch162 anchor not found: $path" }
  $text = $text.Replace($old,$new)
  [IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($false)))
}

$exporter = Join-Path $project 'supabase/functions/export-shipment-excel/index.ts'
$statement = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
if (!(Test-Path $exporter)) { throw "missing $exporter" }
if (!(Test-Path $statement)) { throw "missing $statement" }

# 1) Excel exporter: special_note_auto를 source-of-truth cargo와 같이 읽기
Replace-Once $exporter `
"'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,received_at,created_at'" `
"'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,special_note_auto,received_at,created_at'"

# 2) 물품 입고 내역 P열: 수기 비고 + 자동 할인/배송 문구를 함께 출력
$old = "    ['P', 'notes', 'text'],"
$new = @"
    ['P', 'notes', 'text'],
"@
Replace-Once $exporter $old $new

# updateCargoSheet 직전 shipment 복사본에 notes를 합성하도록 좁은 anchor 삽입
$anchor = @"
    const shipment = shipmentByBox.get(fixedBox.toUpperCase());
    if (!shipment) continue;

    matchedBoxes.add(fixedBox.toUpperCase());
"@
$insert = @"
    const sourceShipment = shipmentByBox.get(fixedBox.toUpperCase());
    if (!sourceShipment) continue;
    const manualNote = String(sourceShipment.notes ?? '').trim();
    const autoNote = String(sourceShipment.special_note_auto ?? '').trim();
    const shipment = {
      ...sourceShipment,
      notes: [manualNote, autoNote]
        .filter((v, i, a) => v && a.indexOf(v) === i)
        .join(' / '),
    };

    matchedBoxes.add(fixedBox.toUpperCase());
"@
Replace-Once $exporter $anchor $insert

# 3) Row data에 문서 자동화 테이블을 추가하는 함수 삽입
$denoAnchor = "Deno.serve(async (req) => {"
$helper = @'
function appendDocumentAutomationBlock(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  deliveries: Record<string, unknown>[],
  extraCosts: Record<string, unknown>[],
  settlement: Record<string, unknown> | null,
): void {
  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;
  let xml = strFromU8(files[path]);
  const close = xml.lastIndexOf('</sheetData>');
  if (close < 0) return;

  const normalizeName = (v: unknown) => String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
  const phoneMatch = (a: unknown, b: unknown) => {
    const aa = normalizePhone(a); const bb = normalizePhone(b);
    return !!aa && !!bb && (aa === bb || (aa.length >= 8 && bb.length >= 8 && aa.slice(-8) === bb.slice(-8)));
  };
  const groups = new Map<string, Record<string, unknown>[]>();
  for (const s of shipments) {
    const receipt = String(s.receipt_number ?? '').trim();
    if (!receipt) continue;
    const list = groups.get(receipt) ?? []; list.push(s); groups.set(receipt, list);
  }
  const receiptAmounts = new Map<string, number>();
  const rawReceipts = Array.isArray(settlement?.receipts) ? settlement!.receipts as Record<string, unknown>[] : [];
  for (const r of rawReceipts) receiptAmounts.set(String(r.receipt_number ?? '').trim(), Number(r.net_usd ?? 0));
  const extraMap = new Map<string, number>();
  for (const e of extraCosts) {
    const receipt = String(e.receipt_number ?? '').trim();
    extraMap.set(receipt, (extraMap.get(receipt) ?? 0) + Number(e.amount_usd ?? 0));
  }

  const existingRows = [...xml.matchAll(/<row\b[^>]*r="(\d+)"/g)].map(m => Number(m[1]));
  let row = (existingRows.length ? Math.max(...existingRows) : 0) + 2;
  const out: string[] = [];
  const add = (vals: Array<string | number>) => {
    const cols = ['X','Y','Z','AA','AB','AC','AD','AE'];
    const cells = vals.map((v,i) => typeof v === 'number' ? numericCell(`${cols[i]}${row}`,'',v) : inlineCell(`${cols[i]}${row}`,'',v)).join('');
    out.push(`<row r="${row}">${cells}</row>`); row++;
  };
  add(['DOCUMENT AUTOMATION','Customer','Phone','Remark Auto','Inland / Delivery','Delivery Type','Extra USD','Amount USD']);
  for (const [receipt, rows] of groups) {
    const first = rows[0];
    const name = String(first.consignee_name ?? '').trim();
    const phone = String(first.consignee_phone ?? '').trim();
    const d = deliveries.find(x => {
      if (!phoneMatch(phone, x.phone)) return false;
      const target = normalizeName(name);
      return [x.customer_name,x.alternate_name,x.company_name].some(v => normalizeName(v) === target && target !== '');
    });
    const paidBy = String(d?.paid_by ?? '').toLowerCase();
    const type = d ? (String(d.delivery_type ?? '') === 'city' ? 'city' : (paidBy.includes('한국') || paidBy.includes('korea') || paidBy.includes('prepaid') ? 'province_prepaid_kr' : 'province')) : '';
    const delivery = d ? [d.source_no ? `(${d.source_no})` : '', d.alternate_name || d.customer_name || name, d.phone_display || d.phone || phone, d.local_company, d.destination_address].filter(Boolean).join(', ') : '';
    const auto = [...new Set(rows.map(x => String(x.special_note_auto ?? '').trim()).filter(Boolean))].join(' / ');
    const extra = extraMap.get(receipt) ?? 0;
    add([receipt,name,phone,auto,delivery,type,extra,(receiptAmounts.get(receipt) ?? 0) + extra]);
  }
  xml = `${xml.substring(0, close)}${out.join('')}${xml.substring(close)}`;
  files[path] = strToU8(xml);
}

'@
Replace-Once $exporter $denoAnchor ($helper + $denoAnchor)

# 3b) N2 영수번호 선택 시 Remark/Inland가 수식으로 즉시 바뀌도록 명세서 sheet 연결
$formulaHelper = @'
function setFormulaCellInSheet(sheetXml: string, ref: string, formula: string): string {
  const rowNumber = Number(ref.match(/\d+$/)?.[0] ?? 0);
  const column = ref.match(/^[A-Z]+/)?.[0] ?? '';
  if (!rowNumber || !column) return sheetXml;
  const rowRe = new RegExp(`<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`);
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;
  const rowXml = rowMatch[0];
  const cellRe = new RegExp(`<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`);
  const existing = rowXml.match(cellRe);
  const attrs = existing ? `${existing[1] ?? ''}${existing[2] ?? ''}` : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';
  const replacement = `<c r="${ref}"${style}><f>${escXml(formula)}</f><v></v></c>`;
  if (existing) return sheetXml.replace(rowXml, rowXml.replace(cellRe, replacement));
  return sheetXml.replace(rowXml, updateCell(rowXml, rowNumber, column, '', 'text').replace(new RegExp(`<c\\b[^>]*r="${ref}"[^>]*(?:\\/>|>[\\s\\S]*?<\\/c>)`), replacement));
}

function wireStatementAutomationFormulas(files: Record<string, Uint8Array>, routeKey: string): void {
  const prefix = routeReceiptPrefix(routeKey);
  const workbook = strFromU8(files['xl/workbook.xml']);
  const names = [...workbook.matchAll(/<sheet\\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\\/?>/g)].map(m => m[1]);
  const sheetName = names.find(name => {
    const upper = name.toUpperCase();
    if (upper.includes('XX')) return false;
    return prefix ? upper.startsWith(prefix.toUpperCase()) && /\\d+\\s*$/.test(name) : false;
  });
  if (!sheetName) return;
  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;
  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  let remarkRef = '';
  let inlandRef = '';
  for (const m of xml.matchAll(/<c\\b[^>]*r="([A-Z]+\\d+)"[^>]*>[\\s\\S]*?<\\/c>/g)) {
    const text = cellText(m[0], strings).trim().toLowerCase();
    if (!remarkRef && (text.includes('remark') || text === '비고')) remarkRef = m[1];
    if (!inlandRef && (text.includes('inland') || text.includes('지방 배송') || text.includes('지방배송'))) inlandRef = m[1];
  }
  const below = (ref: string) => {
    const col = ref.match(/^[A-Z]+/)?.[0] ?? '';
    const row = Number(ref.match(/\\d+$/)?.[0] ?? 0);
    return col && row ? `${col}${row + 1}` : '';
  };
  const remarkTarget = below(remarkRef);
  const inlandTarget = below(inlandRef);
  if (remarkTarget) {
    xml = setFormulaCellInSheet(xml, remarkTarget,
      `IFERROR(INDEX('Row data'!$AA:$AA,MATCH($N$2,'Row data'!$X:$X,0)),"")`);
  }
  if (inlandTarget) {
    xml = setFormulaCellInSheet(xml, inlandTarget,
      `IFERROR(INDEX('Row data'!$AB:$AB,MATCH($N$2,'Row data'!$X:$X,0)),"")`);
  }
  // N3/N4/N5는 동적 문서 계산 보조셀. 명세서 표시 셀과 같은 N2를 source로 사용합니다.
  xml = setFormulaCellInSheet(xml, 'N3', `IFERROR(INDEX('Row data'!$AA:$AA,MATCH($N$2,'Row data'!$X:$X,0)),"")`);
  xml = setFormulaCellInSheet(xml, 'N4', `IFERROR(INDEX('Row data'!$AB:$AB,MATCH($N$2,'Row data'!$X:$X,0)),"")`);
  xml = setFormulaCellInSheet(xml, 'N5', `IFERROR(INDEX('Row data'!$AC:$AC,MATCH($N$2,'Row data'!$X:$X,0)),"")`);
  files[path] = strToU8(xml);
}

'@
Replace-Once $exporter $denoAnchor ($formulaHelper + $denoAnchor)

# 4) exporter에서 배송 profile 로드
$settleAnchor = "    const filePrefixes: Record<string, string> = {"
$deliveryQuery = @'
    const { data: localDeliveryProfiles, error: localDeliveryError } = await admin
      .from('local_delivery_profiles')
      .select('source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes')
      .eq('route_key', routeKey)
      .eq('active', true);
    if (localDeliveryError) throw localDeliveryError;

'@
Replace-Once $exporter $settleAnchor ($deliveryQuery + $settleAnchor)

# 5) Row data 정산 반영 직전에 자동화 테이블 추가
$applyAnchor = @"
    applySettlementToExistingRowData(
      files,
      settlementForExcel as Record<string, unknown> | null,
      shipmentRouteLabel,
      shipmentYear,
      voyage,
    );
"@
$applyNew = $applyAnchor + @"
    appendDocumentAutomationBlock(
      files,
      enrichedShipments,
      (localDeliveryProfiles ?? []) as Record<string, unknown>[],
      voyageExtraCosts,
      settlementForExcel as Record<string, unknown> | null,
    );
"@
Replace-Once $exporter $applyAnchor $applyNew

$selectorCall = @"
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
"@
$selectorNew = @"
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
    wireStatementAutomationFormulas(files, routeKey);
"@
Replace-Once $exporter $selectorCall $selectorNew

# 6) 앱 명세서 Remark에 자동 할인/배송 문구도 동일하게 표시
$oldRemark = @"
    _text(c, docText.remark,
        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
        docText.remarkFontSize, maxLines: 6, lineHeight: 1.05);
"@
$newRemark = @"
    final autoNotes = rows
        .map((row) => _s(row['special_note_auto']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .join(' / ');
    final remarkText = autoNotes.isEmpty
        ? docText.remark
        : '4{docText.remark}\n\n4autoNotes';
    _text(c, remarkText,
        Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
        docText.remarkFontSize, maxLines: 6, lineHeight: 1.05);
"@
# PowerShell에서 $ interpolation을 피하기 위해 치환
$newRemark = $newRemark.Replace([char]2 + '4','$')
Replace-Once $statement $oldRemark $newRemark

Copy-Item (Join-Path $root 'supabase_094_document_automation_refresh.sql') (Join-Path $project 'supabase/supabase_094_document_automation_refresh.sql') -Force
Write-Host 'Patch162 files applied.' -ForegroundColor Green
Write-Host 'NEXT 1) Run supabase/supabase_094_document_automation_refresh.sql in Supabase SQL Editor'
Write-Host 'NEXT 2) supabase functions deploy export-shipment-excel'
Write-Host 'NEXT 3) flutter analyze'
