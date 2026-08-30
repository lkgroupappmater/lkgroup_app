$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch129: 단일 선택형 거래명세서 기반 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch129" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

if ($ts -notmatch "function enableDynamicReceiptSelector") {
    $anchor = "function applySettlementToExistingRowData("
    $idx = $ts.IndexOf($anchor)
    if ($idx -lt 0) { throw "index.ts: applySettlementToExistingRowData 위치를 찾지 못했습니다." }

    $helper = @'
function enableDynamicReceiptSelector(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  routeKey: string,
  shipmentYear: number,
  voyage: string,
): void {
  const prefix = routeReceiptPrefix(routeKey);

  // 현재 템플릿의 실제 영수증 시트 중 "XX" 임시 시트는 제외하고
  // 첫 번째 영수증 시트를 단일 선택형 명세서로 사용합니다.
  const workbook = strFromU8(files['xl/workbook.xml']);
  const candidateNames = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )]
    .map((m) => m[1])
    .filter((name) => {
      const upper = name.toUpperCase();
      if (upper.includes('XX')) return false;
      if (!prefix) return /^\S+\s*\d+$/.test(name);
      return upper.startsWith(prefix.toUpperCase()) && /\d+\s*$/.test(name);
    });

  const sheetName = candidateNames[0];
  if (!sheetName) return;

  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;

  const receipts = [...new Set(
    shipments
      .map((row) => String(row.receipt_number ?? '').trim())
      .filter((value) => value.length > 0),
  )];

  if (receipts.length === 0) return;

  let xml = strFromU8(files[path]);

  // N2는 기존에 "현재 시트 이름"을 영수번호로 사용하던 셀입니다.
  // 이를 선택 가능한 영수번호 입력셀로 바꾸면,
  // 기존 명세서의 고객명/전화/화물/운임 수식은 전부 N2를 기준으로 이미 연결되어 있어
  // 시트를 복제하지 않고도 한 장에서 영수번호만 바꿔 전체 명세서를 볼 수 있습니다.
  xml = setStringCellInSheet(xml, 'N2', receipts[0]);

  // 기존 데이터 유효성 검사가 있으면 N2 selector만 추가하며,
  // 없으면 OOXML 순서상 pageMargins 바로 앞에 dataValidations를 삽입합니다.
  const selector =
    '<dataValidation type="list" allowBlank="1" showErrorMessage="1" ' +
    'showInputMessage="1" sqref="N2">' +
    '<formula1>INDIRECT(&quot;&apos;고객 리스트&apos;!$A$4:$A$150&quot;)</formula1>' +
    '</dataValidation>';

  if (/<dataValidations\b[^>]*>[\s\S]*?<\/dataValidations>/.test(xml)) {
    xml = xml.replace(
      /<dataValidations\b([^>]*)count="(\d+)"([^>]*)>([\s\S]*?)<\/dataValidations>/,
      (_m, before, count, after, body) => {
        const next = Number(count || 0) + 1;
        return `<dataValidations${before}count="${next}"${after}>${body}${selector}</dataValidations>`;
      },
    );
  } else {
    const block = `<dataValidations count="1">${selector}</dataValidations>`;
    if (xml.includes('<pageMargins ')) {
      xml = xml.replace('<pageMargins ', `${block}<pageMargins `);
    } else {
      xml = xml.replace('</worksheet>', `${block}</worksheet>`);
    }
  }

  // 제목의 xxth는 실제 항차로만 교체. 디자인은 그대로 유지.
  const titleMatch = xml.match(
    /<c\b([^>]*)r="C1"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/,
  );
  if (titleMatch) {
    const voyageNumber = String(voyage).replace(/^V/i, '').replace(/항차$/u, '');
    xml = setStringCellInSheet(
      xml,
      'C1',
      `Kor-Lao Sea ${voyageNumber}th 거래 명세서`,
    );
  }

  files[path] = strToU8(xml);
}

'@
    $ts = $ts.Insert($idx, $helper)
}

if ($ts -notmatch "enableDynamicReceiptSelector\(" -or
    ([regex]::Matches($ts, "enableDynamicReceiptSelector\(").Count -lt 2)) {
    $needle = "    upgradeZoneQuantityFormulas(files);"
    if (-not $ts.Contains($needle)) {
        throw "index.ts: upgradeZoneQuantityFormulas 호출을 찾지 못했습니다. Patch128 적용 여부를 확인하세요."
    }

    $call = @'

    // 한 장의 기존 명세서에서 N2 영수번호를 선택해 전체 내용을 바꾸는 동적 명세서 기반.
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
'@
    $ts = $ts.Replace($needle, $needle + $call)
}

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] 거래명세서 N2 영수번호 선택형 구조 적용" -ForegroundColor Green
Write-Host "[OK] 기존 명세서 수식/디자인 유지" -ForegroundColor Green
Write-Host "[OK] 수백 개 영수증 시트 생성 없이 1장 선택형 기반" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
