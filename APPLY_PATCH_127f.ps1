$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch127f: Excel 빈 화물셀 핵심 수정 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch127f" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

# 기존 regex는 <c .../> 자기종결 셀을 paired cell로 잘못 잡아서,
# 뒤쪽 O열 수식까지 한 셀의 body로 삼는 문제가 있었음.
# 그래서 C~N 빈 셀이 O열 수식셀로 오인되어 "수식 보존" 처리되고 쓰기가 전부 skip됨.
$oldRegex = @'
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>|<c\\b([^>]*)r="${ref}"([^>]*)\\/>`,
  );
'@

$newRegex = @'
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
'@

$count = ([regex]::Matches($ts, [regex]::Escape($oldRegex))).Count
if ($count -lt 2) {
    throw "Patch127f: 수정 대상 cellRe 2곳을 찾지 못했습니다. 현재 index.ts가 예상 버전과 다릅니다."
}
$ts = $ts.Replace($oldRegex, $newRegex)

# updateCell()의 attrs 추출도 새 regex 그룹 구조에 맞춤
$oldAttrs = @'
  const attrs = existing
    ? `${existing[1] ?? existing[4] ?? ''}${existing[2] ?? existing[5] ?? ''}`
    : '';
'@
$newAttrs = @'
  const attrs = existing
    ? `${existing[1] ?? ''}${existing[2] ?? ''}`
    : '';
'@
if (-not $ts.Contains($oldAttrs)) {
    throw "Patch127f: updateCell attrs 블록을 찾지 못했습니다."
}
$ts = $ts.Replace($oldAttrs, $newAttrs)

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] 자기종결 빈 셀(<c .../>) 인식 오류 수정 완료" -ForegroundColor Green
Write-Host "[OK] C~N 화물 데이터가 O열 수식으로 오인되던 원인 제거" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
