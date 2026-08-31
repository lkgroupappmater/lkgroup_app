$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root
$p = Join-Path $root "supabase\functions\export-shipment-excel\index.ts"

$candidates = @(
  "$p.bak_before_patch132c",
  "$p.bak_before_patch132"
)

$source = $null
foreach ($c in $candidates) {
  if (Test-Path $c) {
    $text = Get-Content $c -Raw -Encoding UTF8
    # 132c의 깨진 주석 흔적이 없는 백업만 사용
    if ($text -notmatch "Patch132c HOTFIX") {
      $source = $text
      Write-Host "[OK] 정상 백업 선택: $c" -ForegroundColor Green
      break
    }
  }
}
if ($null -eq $source) {
  throw "사용 가능한 Patch132 이전/132c 이전 백업을 찾지 못했습니다. index.ts를 더 이상 변경하지 않았습니다."
}

# cargo 검사 구문은 버전별 공백/괄호 차이를 허용하여 정규식으로 최소 변경.
$pattern = 'if\s*\(\s*!cargoSheetPath\s*\|\|\s*!files\[cargoSheetPath\]\s*\)\s*\{'
if ($source -match $pattern) {
  $source = [regex]::Replace(
    $source,
    $pattern,
    "if ((!cargoSheetPath || !files[cargoSheetPath]) && routeKey !== 'th_la_land') {",
    1
  )
  Write-Host "[OK] TH-LA LAND cargo-sheet 422 검사 예외 적용" -ForegroundColor Green
} elseif ($source -match "routeKey\s*!==\s*'th_la_land'") {
  Write-Host "[OK] TH-LA LAND 예외가 이미 적용되어 있어 추가 변경 생략" -ForegroundColor Yellow
} else {
  Write-Host "[WARN] cargo-sheet 검사 위치를 찾지 못해 TH-LA 예외는 적용하지 않았습니다." -ForegroundColor Yellow
  Write-Host "[WARN] 우선 정상 TypeScript 복원만 수행합니다." -ForegroundColor Yellow
}

Copy-Item $p "$p.bak_before_patch132e" -Force
Set-Content $p $source -Encoding UTF8

Write-Host ""
Write-Host "[OK] index.ts 문법 정상본 복원 완료" -ForegroundColor Green
Write-Host "이제 배포:" -ForegroundColor Cyan
Write-Host "npx supabase functions deploy export-shipment-excel"
