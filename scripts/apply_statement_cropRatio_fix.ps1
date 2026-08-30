$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$p = Join-Path $project 'lib/screens/statement_preview_dialog.dart'

if (-not (Test-Path $p)) {
  throw "statement_preview_dialog.dart not found: $p"
}

$t = Get-Content $p -Raw -Encoding UTF8

if (-not $t.Contains("double _cropRatio()")) {
  $marker = "  Size _logicalSize(ui.Image image) {"
  if (-not $t.Contains($marker)) {
    throw "_logicalSize marker not found"
  }

  $method = @"
  double _cropRatio() =>
      _formRouteKey == 'kr_la_sea' || _formRouteKey == 'kr_la_air'
          ? .402
          : .468;

"@

  $t = $t.Replace($marker, $method + $marker)
}

Set-Content $p $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch097d 완료: _cropRatio() 메서드 추가' -ForegroundColor Green
Write-Host 'flutter analyze 실행하세요.'
