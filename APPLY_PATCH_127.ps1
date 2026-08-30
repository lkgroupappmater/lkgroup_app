$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127: Excel Export 실사용 연결 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$dartPath = Join-Path $projectRoot "lib\services\excel_export_service.dart"
$tsPath   = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"

if (!(Test-Path $dartPath)) { throw "파일 없음: $dartPath" }
if (!(Test-Path $tsPath))   { throw "파일 없음: $tsPath" }

Copy-Item $dartPath "$dartPath.bak_before_patch127" -Force
Copy-Item $tsPath "$tsPath.bak_before_patch127" -Force

# ----------------------------------------------------------------------
# 1) Flutter -> Edge Function에 실제 선택한 route_label 전달
#    템플릿에 저장된 과거 route_label로 다른 shipment 묶음을 조회하는 문제 방지
# ----------------------------------------------------------------------
$dart = Get-Content $dartPath -Raw -Encoding UTF8

if ($dart -notmatch "'route_label': batch\.routeLabel") {
    $old = @"
        'route_key': batch.routeKey,
        'shipment_year': batch.year,
        'voyage': batch.voyage,
"@
    $new = @"
        'route_key': batch.routeKey,
        'route_label': batch.routeLabel,
        'shipment_year': batch.year,
        'voyage': batch.voyage,
"@
    if (-not $dart.Contains($old)) {
        throw "excel_export_service.dart: Edge Function body 삽입 위치를 찾지 못했습니다."
    }
    $dart = $dart.Replace($old, $new)
    Set-Content $dartPath $dart -Encoding UTF8
    Write-Host "[OK] 실제 route_label 전달 추가" -ForegroundColor Green
} else {
    Write-Host "[SKIP] route_label 전달은 이미 적용됨" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------
# 2) Edge Function 수정
# ----------------------------------------------------------------------
$ts = Get-Content $tsPath -Raw -Encoding UTF8

# 2-1. request route_label 읽기
if ($ts -notmatch "requestedRouteLabel") {
    $old = "    const routeKey = String(body.route_key ?? '').trim();`r`n    const shipmentYear = Number(body.shipment_year);"
    if (-not $ts.Contains($old)) {
        $old = "    const routeKey = String(body.route_key ?? '').trim();`n    const shipmentYear = Number(body.shipment_year);"
    }
    if (-not $ts.Contains($old)) {
        throw "index.ts: routeKey/body 파싱 위치를 찾지 못했습니다."
    }
    $new = $old.Replace(
        "    const shipmentYear = Number(body.shipment_year);",
        "    const requestedRouteLabel = String(body.route_label ?? '').trim();`n    const shipmentYear = Number(body.shipment_year);"
    )
    $ts = $ts.Replace($old, $new)
}

# 2-2. 실제 shipment 조회 route는 앱이 선택한 route_label을 최우선 사용
if ($ts -notmatch "const shipmentRouteLabel =") {
    $anchor = "    const { data: shipments, error: shipmentError } = await admin"
    $idx = $ts.IndexOf($anchor)
    if ($idx -lt 0) { throw "index.ts: shipments 조회 위치를 찾지 못했습니다." }

    $insert = @"
    const shipmentRouteLabel =
      requestedRouteLabel ||
      String(routeDefinition?.display_name ?? '').trim() ||
      String(template.route_label ?? '').trim();

"@
    $ts = $ts.Insert($idx, $insert)
}

$ts = $ts.Replace(".eq('route', template.route_label)", ".eq('route', shipmentRouteLabel)")

# 2-3. 기존 Row data의 실제 Total/Amount/할인 위치에 중앙 정산 snapshot 값을 직접 기록
if ($ts -notmatch "function applySettlementToExistingRowData") {
    $anchor = "function appendRowDataSettlementBlock("
    $idx = $ts.IndexOf($anchor)
    if ($idx -lt 0) { throw "index.ts: appendRowDataSettlementBlock 위치를 찾지 못했습니다." }

    $helper = @'
function applySettlementToExistingRowData(
  files: Record<string, Uint8Array>,
  snapshot: Record<string, unknown> | null,
  routeLabel: string,
  shipmentYear: number,
  voyage: string,
): void {
  if (!snapshot) return;

  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const voyageLabel = voyage.endsWith('항차') ? voyage : `${voyage}항차`;

  // 기존 LK Excel의 실제 업무용 요약 위치.
  // 수백 장 명세서의 SUM 결과가 아니라 중앙 FreightService snapshot을 직접 기록합니다.
  xml = setStringCellInSheet(
    xml,
    'B14',
    `${routeLabel} ${shipmentYear}년 ${voyageLabel}`,
  );
  xml = setNumericCellInSheet(
    xml,
    'C15',
    Number(snapshot.total_quantity ?? 0),
  );
  xml = setNumericCellInSheet(
    xml,
    'C16',
    Number(snapshot.net_usd ?? 0),
  );
  xml = setNumericCellInSheet(
    xml,
    'C18',
    Number(snapshot.discount_usd ?? 0),
  );

  files[path] = strToU8(xml);
}

'@
    $ts = $ts.Insert($idx, $helper)
}

# 2-4. 화물 시트 작성 직후 고객 리스트 / 기존 영수증 cached values 갱신 + 제목 갱신
if ($ts -notmatch "seedCustomerListFromShipments\(files, enrichedShipments\);") {
    $anchor = @"
    files[targetPath] = strToU8(
      updateCargoSheet(
        sheetXml,
        strings,
        enrichedShipments,
      ),
    );

"@
    if (-not $ts.Contains($anchor)) {
        $anchor = $anchor -replace "`r`n","`n"
    }
    if (-not $ts.Contains($anchor)) {
        throw "index.ts: updateCargoSheet 호출 블록을 찾지 못했습니다."
    }

    $replacement = $anchor + @"
    // 실사용 Excel 연결: 고객 리스트와 기존 영수증 sheet의 cached value를 함께 갱신합니다.
    seedCustomerListFromShipments(files, enrichedShipments);
    refreshReceiptSheetCaches(files, enrichedShipments);

    // 템플릿의 xx항차 제목을 실제 선택한 항차로 바꿉니다.
    let cargoTitleXml = strFromU8(files[targetPath]);
    const voyageLabel = voyage.endsWith('항차') ? voyage : `${voyage}항차`;
    cargoTitleXml = setStringCellInSheet(
      cargoTitleXml,
      'B1',
      `${shipmentYear}년 ${voyageLabel} ${shipmentRouteLabel} 물품 입고 내역 (Cargo list)`,
    );
    files[targetPath] = strToU8(cargoTitleXml);

"@
    $ts = $ts.Replace($anchor, $replacement)
}

# 2-5. 환율 갱신 다음에 기존 Row data 요약 위치도 snapshot으로 갱신
if ($ts -notmatch "applySettlementToExistingRowData\(" -or
    ([regex]::Matches($ts, "applySettlementToExistingRowData\(").Count -lt 2)) {
    $anchor = @"
    // 기존 Row data의 수식/표는 건드리지 않고, 맨 아래에 DB 정산 원본 블록을 추가합니다.
"@
    if (-not $ts.Contains($anchor)) {
        $anchor = $anchor -replace "`r`n","`n"
    }
    if (-not $ts.Contains($anchor)) {
        throw "index.ts: Row data settlement 호출 위치를 찾지 못했습니다."
    }

    $insert = @"
    // 기존 Row data의 실제 Total / Amount / 총 할인 금액도 같은 snapshot으로 직접 갱신합니다.
    applySettlementToExistingRowData(
      files,
      settlementSnapshot as Record<string, unknown> | null,
      shipmentRouteLabel,
      shipmentYear,
      voyage,
    );

"@
    $ts = $ts.Replace($anchor, $insert + $anchor)
}

# 2-6. Patch126 dimension 축소 문제 보정:
#      기존 Row data가 DL열까지 쓰는 경우 F열로 used range가 줄어들지 않게 기존 끝 열 보존.
$oldDim = @"
        const start = String(ref).split(':')[0] || 'A1';
        return `<dimension${before}ref="${start}:F${finalRow}"${after}/>`;
"@
$newDim = @"
        const parts = String(ref).split(':');
        const start = parts[0] || 'A1';
        const originalEnd = parts.length > 1 ? parts[1] : start;
        const originalEndColumn =
          originalEnd.match(/^[A-Z]+/)?.[0] ?? 'F';
        const endColumn =
          columnIndex(originalEndColumn) > columnIndex('F')
            ? originalEndColumn
            : 'F';
        return `<dimension${before}ref="${start}:${endColumn}${finalRow}"${after}/>`;
"@
if ($ts.Contains($oldDim)) {
    $ts = $ts.Replace($oldDim, $newDim)
}

Set-Content $tsPath $ts -Encoding UTF8
Write-Host "[OK] Edge Function 실사용 Excel 연결 수정 완료" -ForegroundColor Green

Write-Host ""
Write-Host "Patch127 적용 완료." -ForegroundColor Cyan
Write-Host "다음 명령:" -ForegroundColor Cyan
Write-Host "  flutter analyze"
Write-Host "  npx supabase functions deploy export-shipment-excel"
Write-Host ""
Write-Host "SQL Editor에서는 supabase\070_fix_voyage_settlement_snapshot_service_role.sql 을 1회 실행하세요."
