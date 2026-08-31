$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$p = Join-Path $root "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $p)) { throw "파일 없음: $p" }

Copy-Item $p "$p.bak_before_patch133" -Force
$s = Get-Content $p -Raw -Encoding UTF8

# ------------------------------------------------------------
# 1) Row data settlement 위치를 고정 행(B14/C15/C16/C18)에서
#    실제 템플릿 라벨(Total / Amount / 총 할인 금액) 기반으로 변경.
#    단일단가 / 구간별단가 모두 같은 코드로 대응.
# ------------------------------------------------------------
$newFunction = @'
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
  const strings = sharedStrings(files);
  const voyageLabel = voyage.endsWith('항차') ? voyage : `${voyage}항차`;

  // Row data 위치는 노선별로 다릅니다.
  // 단일 단가형: 환율표 아래에서 곧바로 Total/Amount 영역이 시작될 수 있고,
  // 구간별 단가형: 환율표 -> Kg 구간 단가표 -> Total/Amount 영역 순서입니다.
  // 따라서 B14/C15... 같은 고정 행을 절대 사용하지 않고
  // 원본 Excel의 실제 라벨 위치를 찾아 중앙 FreightService snapshot을 기록합니다.
  const findLabelRow = (label: string): number | null => {
    for (const rowMatch of xml.matchAll(
      /<row\b[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g,
    )) {
      const rowNumber = Number(rowMatch[1]);
      for (const cellMatch of rowMatch[2].matchAll(
        /<c\b[^>]*r="([A-Z]+\d+)"[^>]*(?:\/>|>[\s\S]*?<\/c>)/g,
      )) {
        const ref = cellMatch[1];
        if (colOf(ref) !== 'B') continue;
        if (cellText(cellMatch[0], strings).trim() === label) {
          return rowNumber;
        }
      }
    }
    return null;
  };

  const totalRow = findLabelRow('Total');
  const amountRow = findLabelRow('Amount');
  const discountRow = findLabelRow('총 할인 금액');

  if (totalRow == null || amountRow == null) {
    // 템플릿 원본에 업무용 요약 영역이 없으면 임의 위치에 쓰지 않습니다.
    return;
  }

  // 기존 LK 템플릿은 항차 제목이 Total 바로 윗행에 배치되어 있습니다.
  // SEA/AIR의 B14, TH-LA LAND의 B23처럼 구조가 달라도 자동 대응합니다.
  const voyageTitleRow = totalRow - 1;
  if (voyageTitleRow > 0) {
    xml = setStringCellInSheet(
      xml,
      `B${voyageTitleRow}`,
      `${routeLabel} ${shipmentYear}년 ${voyageLabel}`,
    );
  }

  xml = setNumericCellInSheet(
    xml,
    `C${totalRow}`,
    Number(snapshot.total_quantity ?? 0),
  );
  xml = setNumericCellInSheet(
    xml,
    `C${amountRow}`,
    Number(snapshot.net_usd ?? 0),
  );

  if (discountRow != null) {
    xml = setNumericCellInSheet(
      xml,
      `C${discountRow}`,
      Number(snapshot.discount_usd ?? 0),
    );
  }

  files[path] = strToU8(xml);
}
'@

$functionPattern = '(?ms)function applySettlementToExistingRowData\([\s\S]*?\n\}\nfunction appendRowDataSettlementBlock\('
if (![regex]::IsMatch($s, $functionPattern)) {
  throw "applySettlementToExistingRowData 함수 위치를 찾지 못했습니다. 파일 변경을 중단합니다."
}

$s = [regex]::Replace(
  $s,
  $functionPattern,
  $newFunction + "`r`nfunction appendRowDataSettlementBlock(",
  1
)
Write-Host "[OK] Row data: 고정행 -> 라벨 기반 자동 위치 탐색" -ForegroundColor Green

# ------------------------------------------------------------
# 2) Patch126의 맨 아래 SYSTEM SETTLEMENT 블록 추가는 중지.
#    정산 원본은 DB snapshot에 이미 보관되고,
#    실사용 Excel은 기존 Total/Amount/할인 위치만 갱신.
# ------------------------------------------------------------
$appendCallPattern = '(?ms)\s*// 기존 Row data의 수식/표는 건드리지 않고, 맨 아래에 DB 정산 원본 블록을 추가합니다\.[\s\S]*?appendRowDataSettlementBlock\(\s*files,\s*settlementSnapshot as Record<string, unknown> \| null,\s*routeKey,\s*shipmentYear,\s*voyage,\s*\);\s*'
if ([regex]::IsMatch($s, $appendCallPattern)) {
  $s = [regex]::Replace(
    $s,
    $appendCallPattern,
    "`r`n    // Patch133: Row data 하단 SYSTEM SETTLEMENT 중복 블록은 더 이상 추가하지 않습니다.`r`n",
    1
  )
  Write-Host "[OK] Row data 하단 SYSTEM SETTLEMENT 중복 블록 중지" -ForegroundColor Green
} else {
  # 주석이 달라진 경우 호출 자체만 안전하게 중지.
  $appendOnly = '(?ms)^\s*appendRowDataSettlementBlock\(\s*files,\s*settlementSnapshot as Record<string, unknown> \| null,\s*routeKey,\s*shipmentYear,\s*voyage,\s*\);\s*$'
  if ([regex]::IsMatch($s, $appendOnly)) {
    $s = [regex]::Replace(
      $s,
      $appendOnly,
      "    // Patch133: appendRowDataSettlementBlock disabled.",
      1
    )
    Write-Host "[OK] Row data 하단 settlement 호출 중지" -ForegroundColor Green
  } else {
    Write-Host "[INFO] appendRowDataSettlementBlock 호출을 찾지 못함 - 이미 중지됐을 수 있음" -ForegroundColor Yellow
  }
}

# ------------------------------------------------------------
# 3) TH-LA LAND는 물품 입고 내역 시트가 없을 수 있으므로
#    cargo title 변경도 targetPath가 있을 때만 실행.
# ------------------------------------------------------------
$titlePattern = @'
(?ms)    // 템플릿의 xx항차 제목을 실제 선택한 항차로 바꿉니다\.\s*
    let cargoTitleXml = strFromU8\(files\[targetPath\]\);\s*
    const voyageLabel = voyage\.endsWith\('항차'\) \? voyage : voyage \+ '항차';\s*
    cargoTitleXml = setStringCellInSheet\(\s*
      cargoTitleXml,\s*
      'B1',\s*
      `\$\{shipmentYear\}년 \$\{voyageLabel\} \$\{shipmentRouteLabel\} 물품 입고 내역 \(Cargo list\)`,\s*
    \);\s*
    files\[targetPath\] = strToU8\(cargoTitleXml\);
'@

$titleReplacement = @'
    // 템플릿의 xx항차 제목을 실제 선택한 항차로 바꿉니다.
    // TH-LA LAND 같은 스팟형은 물품 입고 내역 시트가 없으므로 건너뜁니다.
    if (targetPath && files[targetPath]) {
      let cargoTitleXml = strFromU8(files[targetPath]);
      const voyageLabel = voyage.endsWith('항차') ? voyage : voyage + '항차';
      cargoTitleXml = setStringCellInSheet(
        cargoTitleXml,
        'B1',
        `${shipmentYear}년 ${voyageLabel} ${shipmentRouteLabel} 물품 입고 내역 (Cargo list)`,
      );
      files[targetPath] = strToU8(cargoTitleXml);
    }
'@

if ([regex]::IsMatch($s, $titlePattern)) {
  $s = [regex]::Replace($s, $titlePattern, $titleReplacement, 1)
  Write-Host "[OK] TH-LA LAND cargo title null guard 적용" -ForegroundColor Green
} elseif ($s -match 'if \(targetPath && files\[targetPath\]\) \{\s*let cargoTitleXml') {
  Write-Host "[OK] cargo title guard가 이미 적용되어 있음" -ForegroundColor Yellow
} else {
  Write-Host "[INFO] cargo title 블록 형태가 달라 guard 변경 생략" -ForegroundColor Yellow
}

Set-Content $p $s -Encoding UTF8

Write-Host ""
Write-Host "[OK] Patch133 적용 완료" -ForegroundColor Green
Write-Host "배포:" -ForegroundColor Cyan
Write-Host "npx supabase functions deploy export-shipment-excel"
