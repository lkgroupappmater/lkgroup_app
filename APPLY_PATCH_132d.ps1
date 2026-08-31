$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$p = Join-Path $root "supabase\functions\export-shipment-excel\index.ts"
$bak = "$p.bak_before_patch132c"
if (!(Test-Path $bak)) {
  throw "Patch132c 백업 파일이 없습니다: $bak"
}

# 132c 적용 전 정상 TypeScript로 정확히 복원
Copy-Item $bak $p -Force
$s = Get-Content $p -Raw -Encoding UTF8

# TH-LA LAND의 '물품 입고 내역' 필수 검사만 안전하게 예외 처리
$old = "if (!cargoSheetPath || !files[cargoSheetPath]) {"
$new = "if ((!cargoSheetPath || !files[cargoSheetPath]) && routeKey !== 'th_la_land') {"
if (!$s.Contains($old)) {
  throw "예상한 cargoSheetPath 검사 코드를 찾지 못했습니다. 파일 변경을 중단합니다."
}
$s = $s.Replace($old, $new)

Set-Content $p $s -Encoding UTF8

Write-Host "[OK] Patch132c 문법 오류 변경 전체 롤백" -ForegroundColor Green
Write-Host "[OK] TH-LA LAND 422 검사 예외만 최소 적용" -ForegroundColor Green
Write-Host ""
Write-Host "이제 실행:" -ForegroundColor Cyan
Write-Host "npx supabase functions deploy export-shipment-excel"
