$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch128: 구획 수식 수량 인식 개선 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch128" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

if ($ts -notmatch "function upgradeZoneQuantityFormulas") {
    $anchor = "function seedCustomerListFromShipments("
    $idx = $ts.IndexOf($anchor)
    if ($idx -lt 0) { throw "index.ts: seedCustomerListFromShipments 위치를 찾지 못했습니다." }

    $helper = @'
function upgradeZoneQuantityFormulas(
  files: Record<string, Uint8Array>,
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // 기존 구획 판정용 F열은 G:DL에 조회된 "화물번호 개수"만 셌습니다.
  // 따라서 1개 화물번호에 수량 100개가 들어와도 1개로 판단했습니다.
  //
  // 새 방식:
  // 같은 영수번호의 '물품 입고 내역' I열(수량)을 합산합니다.
  // - S001 / 수량 1 + S002 / 수량 1 = 2개
  // - S001 / 수량 100 = 100개
  // 두 입력 방식 모두 동일하게 처리됩니다.
  //
  // 기존 Zone 기준표(C117:D120 등)는 그대로 유지합니다.
  for (let row = 4; row <= 114; row++) {
    const ref = `F${row}`;
    const cellRe = new RegExp(
      `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>`,
    );
    const match = xml.match(cellRe);
    if (!match) continue;

    const body = match[3] ?? '';
    if (!/<f\\b/.test(body)) continue;

    const formula =
      `SUMIF('물품 입고 내역'!$N$6:$N$1005,$A${row},'물품 입고 내역'!$I$6:$I$1005)`;

    const newBody = body.replace(
      /<f\b[^>]*>[\s\S]*?<\/f>/,
      `<f>${formula}</f>`,
    );

    xml = xml.replace(
      match[0],
      `<c${match[1]}r="${ref}"${match[2]}>${newBody}</c>`,
    );
  }

  files[path] = strToU8(xml);
}

'@
    $ts = $ts.Insert($idx, $helper)
}

if ($ts -notmatch "upgradeZoneQuantityFormulas\(files\);") {
    $needle = "    seedCustomerListFromShipments(files, enrichedShipments);"
    if (-not $ts.Contains($needle)) {
        throw "index.ts: seedCustomerListFromShipments 호출을 찾지 못했습니다."
    }
    $ts = $ts.Replace(
        $needle,
        $needle + "`r`n    upgradeZoneQuantityFormulas(files);"
    )
}

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] 구획 계산을 화물번호 개수 -> 실제 수량 합계 방식으로 개선" -ForegroundColor Green
Write-Host "[OK] 수량이 모두 1이면 기존 방식과 동일" -ForegroundColor Green
Write-Host "[OK] 동일 화물번호에 수량 여러 개면 그 수량만큼 인식" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
