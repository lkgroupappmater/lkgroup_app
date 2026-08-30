$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127c: voyageLabel TypeScript 문법 복구 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch127c" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

$bad1 = "const voyageLabel = voyage.endsWith('항차') ? voyage : `${voyage}항차;"
$bad2 = "const voyageLabel = voyage.endsWith('항차') ? voyage : ${voyage}항차;"
$good = "const voyageLabel = voyage.endsWith('항차') ? voyage : voyage + '항차';"

$changed = $false

if ($ts.Contains($bad2)) {
    $ts = $ts.Replace($bad2, $good)
    $changed = $true
}
elseif ($ts -match "const voyageLabel = voyage\.endsWith\('항차'\) \? voyage : \$\{voyage\}항차;") {
    $ts = [regex]::Replace(
        $ts,
        "const voyageLabel = voyage\.endsWith\('항차'\) \? voyage : \$\{voyage\}항차;",
        $good
    )
    $changed = $true
}

if (-not $changed) {
    throw "Patch127c: 잘못된 voyageLabel 줄을 찾지 못했습니다. index.ts 905~915줄을 보내주세요."
}

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] voyageLabel 문법 복구 완료" -ForegroundColor Green
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
