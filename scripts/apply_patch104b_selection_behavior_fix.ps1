$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function ReadUtf8File([string]$path) {
  return Get-Content $path -Raw -Encoding UTF8
}

function WriteUtf8NoBom([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText(
    $path,
    $text,
    [System.Text.UTF8Encoding]::new($false)
  )
}

$cm = Join-Path $project 'lib\screens\cargo_management_screen.dart'
if (-not (Test-Path $cm)) {
  throw "파일을 찾을 수 없습니다: $cm"
}

$t = ReadUtf8File $cm

# 화물 조회 -> 화물 관리 이동 시, 전달받은 데이터는 불러오되 체크상태는 해제
$t = $t.Replace("    _selectedIds.addAll(widget.initialSelectedIds);`r`n", "")
$t = $t.Replace("    _selectedIds.addAll(widget.initialSelectedIds);`n", "")

# 검색 후에도 선택 상태를 초기화
$t = $t.Replace(
  "        if (widget.initialSelectedIds.isEmpty) _selectedIds.clear();",
  "        _selectedIds.clear();"
)

# 화물관리 상단 명세서 보기:
# 선택 없음 -> 안내문
# 선택 있음 -> 선택 화물 기준 명세서 보기
$oldCrlf = @"
                    TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : _showAllSearchResultStatements,
"@
$newCrlf = @"
                    TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : () {
                              if (_selectedIds.isEmpty) {
                                _message('선택된 항차가 없습니다.');
                                return;
                              }
                              _showStatement();
                            },
"@

if ($t.Contains($oldCrlf)) {
  $t = $t.Replace($oldCrlf, $newCrlf)
} else {
  $pattern = "(?s)TextButton\.icon\(\s*onPressed:\s*_results\.isEmpty\s*\?\s*null\s*:\s*_showAllSearchResultStatements,"
  $replacement = @"
TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : () {
                              if (_selectedIds.isEmpty) {
                                _message('선택된 항차가 없습니다.');
                                return;
                              }
                              _showStatement();
                            },
"@
  if ($t -match $pattern) {
    $t = [regex]::Replace($t, $pattern, $replacement, 1)
  } else {
    Write-Warning '화물관리 상단 명세서 보기 버튼 패턴을 찾지 못했습니다.'
  }
}

WriteUtf8NoBom $cm $t

Write-Host ''
Write-Host 'Patch104b 적용 완료' -ForegroundColor Green
Write-Host '- PowerShell R/W alias 충돌 제거'
Write-Host '- 화물조회 -> 화물관리 이동 시 체크 해제'
Write-Host '- 상단 명세서 보기: 미선택 시 "선택된 항차가 없습니다."'
