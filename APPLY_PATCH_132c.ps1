$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$p = Join-Path $root "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $p)) { throw "파일 없음: $p" }
Copy-Item $p "$p.bak_before_patch132c" -Force
$s = Get-Content $p -Raw -Encoding UTF8

# 1) SEA/AIR Excel repair popup hotfix:
# Patch129/132가 worksheet의 dataValidation XML을 직접 바꾸는 경로를 일단 중지.
# 기존 원본 수식/화물/Row data export는 그대로 유지.
$s = $s -replace '(?m)^(\s*)enableDynamicReceiptSelector\(\s*$', '$1// Patch132c HOTFIX: worksheet XML repair popup 방지를 위해 selector XML mutation 임시 중지.$([Environment]::NewLine)$1// enableDynamicReceiptSelector('
# 위 치환으로 다중행 호출의 나머지가 코드로 남는 문제를 피하기 위해 전체 호출 블록을 정리.
$s = [regex]::Replace(
  $s,
  '(?ms)^\s*// Patch132c HOTFIX: worksheet XML repair popup 방지를 위해 selector XML mutation 임시 중지\.\r?\n\s*// enableDynamicReceiptSelector\(\r?\n\s*files,\r?\n\s*enrichedShipments,\r?\n\s*routeKey,\r?\n\s*shipmentYear,\r?\n\s*voyage,\r?\n\s*\);\r?\n',
  "`r`n    // Patch132c HOTFIX: Excel 복구 팝업 방지를 위해 동적 validation XML 변경 임시 중지.`r`n"
)
$s = [regex]::Replace(
  $s,
  '(?ms)^\s*addStatementLanguageSelector\(files,\s*routeKey\);\s*',
  "    // Patch132c HOTFIX: language dataValidation XML 변경 임시 중지.`r`n"
)

# 2) TH-LA LAND:
# 이 노선은 '물품 입고 내역'이 필수가 아닌 스팟 직접명세서형.
# 기존 422 검사에서 th_la_land만 예외로 허용.
$s = $s.Replace(
  "if (!cargoSheetPath || !files[cargoSheetPath]) {",
  "if ((!cargoSheetPath || !files[cargoSheetPath]) && routeKey !== 'th_la_land') {"
)

# cargo sheet가 있을 때만 기존 정기항차 updateCargoSheet 실행.
$old = "files[cargoSheetPath] = strToU8(updateCargoSheet(strFromU8(files[cargoSheetPath]), strings, enrichedShipments));"
if ($s.Contains($old)) {
  $new = @"
if (cargoSheetPath && files[cargoSheetPath]) {
      files[cargoSheetPath] = strToU8(
        updateCargoSheet(strFromU8(files[cargoSheetPath]), strings, enrichedShipments),
      );
    }
"@
  $s = $s.Replace($old,$new)
}

Set-Content $p $s -Encoding UTF8
Write-Host "[OK] SEA/AIR dataValidation XML mutation 임시 중지" -ForegroundColor Green
Write-Host "[OK] TH-LA LAND 물품 입고 내역 필수검사 예외 적용" -ForegroundColor Green
Write-Host "[OK] TH-LA LAND 스팟 직접명세서 populate 호출은 유지" -ForegroundColor Green
Write-Host ""
Write-Host "배포: npx supabase functions deploy export-shipment-excel" -ForegroundColor Cyan
