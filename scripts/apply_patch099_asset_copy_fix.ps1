$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

$assetDst = Join-Path $project 'assets\statement_forms'

# Patch099 ZIP을 프로젝트 루트에 풀면 assets/statement_forms/*.png 는
# 이미 프로젝트 assets 폴더에 덮어써져 있습니다.
# 따라서 자기 자신으로 Copy-Item 하지 않고 존재 여부만 확인합니다.
$required = @(
  'kr_la_sea.png',
  'kr_la_air.png',
  'la_kr_air_exp.png',
  'la_th_land.png',
  'th_la_land.png',
  'la_vn_land.png',
  'vn_la_land.png',
  'la_ch_land.png',
  'ch_la_land.png',
  'la_kh_land.png',
  'kh_la_land.png'
)

$missing = @()
foreach ($name in $required) {
  $p = Join-Path $assetDst $name
  if (-not (Test-Path $p)) {
    $missing += $name
  }
}

if ($missing.Count -gt 0) {
  throw "Patch099 statement asset 누락: $($missing -join ', ')"
}

$mainScript = Join-Path $PSScriptRoot 'apply_excel_form_fidelity_final.ps1'
if (-not (Test-Path $mainScript)) {
  throw "apply_excel_form_fidelity_final.ps1 not found: $mainScript"
}

# 기존 Patch099 메인 스크립트의 self-copy 부분만 제거
$t = Get-Content $mainScript -Raw -Encoding UTF8

$old = @"
`$assetSrc = Join-Path `$PSScriptRoot '..\assets\statement_forms'
`$assetDst = Join-Path `$project 'assets\statement_forms'
New-Item -ItemType Directory -Force -Path `$assetDst | Out-Null
Copy-Item (Join-Path `$assetSrc '*.png') `$assetDst -Force
"@

$new = @"
`$assetDst = Join-Path `$project 'assets\statement_forms'
if (-not (Test-Path `$assetDst)) {
  throw "statement_forms asset folder not found: `$assetDst"
}
"@

if ($t.Contains($old)) {
  $t = $t.Replace($old, $new)
  Set-Content $mainScript $t -Encoding UTF8
} else {
  # 이미 수정됐거나 줄바꿈 형태가 다른 경우 Copy-Item 한 줄만 안전하게 제거
  $t = [regex]::Replace(
    $t,
    "(?m)^\s*`$assetSrc\s*=.*\r?\n",
    ""
  )
  $t = [regex]::Replace(
    $t,
    "(?m)^\s*New-Item -ItemType Directory -Force -Path `\$assetDst \| Out-Null\r?\n",
    ""
  )
  $t = [regex]::Replace(
    $t,
    "(?m)^\s*Copy-Item \(Join-Path `\$assetSrc '\*\.png'\) `\$assetDst -Force\r?\n",
    ""
  )
  Set-Content $mainScript $t -Encoding UTF8
}

Write-Host ''
Write-Host 'Patch099b 완료: statement asset self-copy 제거' -ForegroundColor Green
Write-Host '이제 기존 메인 스크립트를 다시 실행하세요:'
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\apply_excel_form_fidelity_final.ps1'
