$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$p = Join-Path $project 'lib/screens/statement_preview_dialog.dart'

if (-not (Test-Path $p)) {
  throw "statement_preview_dialog.dart not found: $p"
}

$t = Get-Content $p -Raw -Encoding UTF8

$old = @"
    required this.baseRows,
    required this.detailRows,
  });
"@

$new = @"
    required this.baseRows,
    required this.detailRows,
    required this.sourceTop,
  });
"@

if ($t.Contains($old)) {
  $t = $t.Replace($old, $new)
} elseif (-not $t.Contains("required this.sourceTop,")) {
  throw "StatementPainter constructor pattern not found"
}

Set-Content $p $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch097b 완료: _StatementPainter sourceTop constructor 초기화 수정' -ForegroundColor Green
Write-Host 'flutter analyze 실행하세요.'
