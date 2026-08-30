$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function R($p) { Get-Content $p -Raw -Encoding UTF8 }
function W($p,$t) { [System.IO.File]::WriteAllText($p,$t,[System.Text.UTF8Encoding]::new($false)) }

# Cargo Management: do not auto-check incoming rows.
$cm = Join-Path $project 'lib\screens\cargo_management_screen.dart'
$t = R $cm
$t = $t.Replace("    _selectedIds.addAll(widget.initialSelectedIds);`r`n", "")
$t = $t.Replace("    _selectedIds.addAll(widget.initialSelectedIds);`n", "")
$t = $t.Replace("        if (widget.initialSelectedIds.isEmpty) _selectedIds.clear();", "        _selectedIds.clear();")

# Header statement button should work only with selected cargo; otherwise show requested message.
$old = @"
                    TextButton.icon(
                      onPressed: _results.isEmpty
                          ? null
                          : _showAllSearchResultStatements,
"@
$new = @"
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
if ($t.Contains($old)) {
  $t = $t.Replace($old,$new)
} else {
  Write-Warning '화물관리 상단 명세서 버튼 패턴을 찾지 못했습니다.'
}
W $cm $t

# Shipment Search: when transferring to management, preserve selected row list
# for loading, but management screen itself now opens unchecked.
$ss = Join-Path $project 'lib\screens\shipment_search_screen.dart'
$t = R $ss
# No visual behavior change needed here; callback still passes selected IDs so rows can load.
W $ss $t

Write-Host ''
Write-Host 'Patch104 화물 선택 동작 적용 완료' -ForegroundColor Green
Write-Host '- 화물조회 -> 화물관리 이동 시 체크 상태 해제'
Write-Host '- 화물관리 상단 명세서 보기: 선택이 없으면 "선택된 항차가 없습니다."'
