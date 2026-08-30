$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127b: TypeScript 제목 문자열 문법 복구 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch127b" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

# Patch127 PowerShell here-string에서 TypeScript template literal의 backtick이 소실된 경우를 복구.
$patterns = @(
    '(?m)^(\s*)\$\{shipmentYear\}년\s+\$\{voyageLabel\}\s+\$\{shipmentRouteLabel\}\s+물품 입고 내역 \(Cargo list\),\s*$',
    '(?m)^(\s*)\$\{shipmentYear\}년\s+물품 입고 내역 \(Cargo list\),\s*$'
)

$replacement = '$1`${shipmentYear}년 ${voyageLabel} ${shipmentRouteLabel} 물품 입고 내역 (Cargo list)`,'
$changed = $false

foreach ($pattern in $patterns) {
    if ([regex]::IsMatch($ts, $pattern)) {
        $ts = [regex]::Replace($ts, $pattern, $replacement, 1)
        $changed = $true
        break
    }
}

if (-not $changed) {
    # 정확한 setStringCellInSheet 블록을 찾아 마지막 인자를 안전한 문자열 결합식으로 교체.
    $pattern = "(?s)(cargoTitleXml\s*=\s*setStringCellInSheet\(\s*cargoTitleXml,\s*'B1',\s*)(.*?)(\s*,\s*\);)"
    $m = [regex]::Match($ts, $pattern)
    if (-not $m.Success) {
        throw "Patch127b: cargoTitleXml 제목 블록을 찾지 못했습니다. 현재 index.ts 900~920줄을 보내주세요."
    }
    $safe = "'`$shipmentYear년 ' + voyageLabel + ' ' + shipmentRouteLabel + ' 물품 입고 내역 (Cargo list)'"
    # 위 PowerShell interpolation 위험을 피하기 위해 고정 TS 표현식 사용
    $safe = "String(shipmentYear) + '년 ' + voyageLabel + ' ' + shipmentRouteLabel + ' 물품 입고 내역 (Cargo list)'"
    $ts = $ts.Substring(0, $m.Index) + $m.Groups[1].Value + $safe + $m.Groups[3].Value + $ts.Substring($m.Index + $m.Length)
    $changed = $true
}

Set-Content $tsPath $ts -Encoding UTF8
Write-Host "[OK] index.ts TypeScript 문법 복구 완료" -ForegroundColor Green
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
