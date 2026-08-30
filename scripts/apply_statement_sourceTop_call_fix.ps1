$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$p = Join-Path $project 'lib/screens/statement_preview_dialog.dart'

if (-not (Test-Path $p)) {
  throw "statement_preview_dialog.dart not found: $p"
}

$t = Get-Content $p -Raw -Encoding UTF8

# _StatementPainter 호출부에 sourceTop 전달이 빠진 경우 보강
$patterns = @(
@"
        detailRows: _detailRows,
      );
"@,
@"
        detailRows: _detailRows,
    );
"@
)

$replacement = @"
        detailRows: _detailRows,
        sourceTop: image.height * _cropRatio(),
      );
"@

$changed = $false
foreach ($old in $patterns) {
  if ($t.Contains($old)) {
    $t = $t.Replace($old, $replacement)
    $changed = $true
  }
}

# 이미 sourceTop이 들어가 있으면 정상으로 간주
if (-not $changed -and -not $t.Contains("sourceTop: image.height * _cropRatio()")) {
  throw "_StatementPainter call pattern not found"
}

Set-Content $p $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch097c 완료: _StatementPainter 호출부 sourceTop 전달 수정' -ForegroundColor Green
Write-Host 'flutter analyze 실행하세요.'
