$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$cm = Join-Path $project 'lib\screens\cargo_management_screen.dart'

if (-not (Test-Path -LiteralPath $cm)) {
    throw "파일을 찾을 수 없습니다: $cm"
}

$text = Get-Content -LiteralPath $cm -Raw -Encoding UTF8

# 1) Incoming IDs are still used to load the intended cargo set,
#    but Cargo Management must start with no checked rows.
$text = $text -replace '(?m)^\s*_selectedIds\.addAll\(widget\.initialSelectedIds\);\s*\r?\n', ''
$text = $text -replace 'if\s*\(widget\.initialSelectedIds\.isEmpty\)\s*_selectedIds\.clear\(\);', '_selectedIds.clear();'

# 2) Top "명세서 보기": if no cargo is checked, show requested message.
$pattern = 'onPressed:\s*_results\.isEmpty\s*\?\s*null\s*:\s*_showAllSearchResultStatements\s*,'
$replacement = @'
onPressed: _results.isEmpty
                          ? null
                          : () {
                              if (_selectedIds.isEmpty) {
                                _message('선택된 항차가 없습니다.');
                                return;
                              }
                              _showStatement();
                            },
'@

if ([regex]::IsMatch($text, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
    $text = [regex]::Replace(
        $text,
        $pattern,
        $replacement,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
} else {
    Write-Warning '상단 명세서 보기 버튼 패턴을 찾지 못했습니다. 체크 초기화 수정은 적용합니다.'
}

[System.IO.File]::WriteAllText(
    $cm,
    $text,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ''
Write-Host 'Patch104c 적용 완료' -ForegroundColor Green
Write-Host '- PowerShell Parser 오류 제거'
Write-Host '- 화물관리 진입 시 체크 상태 초기화'
Write-Host '- 미선택 상태 명세서 보기 안내 처리'
