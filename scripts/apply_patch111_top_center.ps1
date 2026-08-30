$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"

foreach ($f in @($q,$s)) {
  if (!(Test-Path -LiteralPath $f)) { throw "Missing file: $f" }
}

# QUOTATION
$x = Get-Content -LiteralPath $q -Raw -Encoding UTF8

# True page-center title (full document width).
$x = [regex]::Replace(
  $x,
  "Rect\.fromLTWH\(180,\s*16,\s*1000,\s*58\)",
  "Rect.fromLTWH(0, 12, w, 62)",
  1
)

# Center both labels and values in every top info cell, slightly larger.
$oldQ = @'
  void _kv(Canvas c, String k, String v, Rect r) {
    _text(c, '$k  ', Rect.fromLTWH(r.left, r.top, 145, r.height), 15, bold: true);
    _text(c, v, Rect.fromLTWH(r.left + 145, r.top, r.width - 145, r.height),
        17, bold: v != '-');
  }
'@
$newQ = @'
  void _kv(Canvas c, String k, String v, Rect r) {
    const labelW = 165.0;
    _text(
      c,
      k,
      Rect.fromLTWH(r.left, r.top, labelW, r.height),
      16,
      bold: true,
      center: true,
    );
    _text(
      c,
      v,
      Rect.fromLTWH(r.left + labelW, r.top, r.width - labelW, r.height),
      19,
      bold: v != '-',
      center: true,
    );
  }
'@
if ($x.Contains($oldQ)) {
  $x = $x.Replace($oldQ,$newQ)
} else {
  Write-Host "Quotation _kv exact block not found; using regex." -ForegroundColor Yellow
  $x = [regex]::Replace(
    $x,
    "(?s)  void _kv\(Canvas c, String k, String v, Rect r\) \{.*?\r?\n  \}\r?\n\r?\n  void _labelValue",
    $newQ + [Environment]::NewLine + "  void _labelValue",
    1
  )
}
[IO.File]::WriteAllText($q,$x,[Text.UTF8Encoding]::new($false))

# STATEMENT
$x = Get-Content -LiteralPath $s -Raw -Encoding UTF8

# Keep title centered on the whole document, even if a previous patch changed it.
$x = [regex]::Replace(
  $x,
  "Rect\.fromLTWH\((?:0|190),\s*(?:14|16),\s*(?:w|940),\s*(?:60|58)\)",
  "Rect.fromLTWH(0, 12, w, 62)",
  1
)

# Center both labels and values in every top info cell, slightly larger.
$oldS = @'
  void _kv(Canvas c, String k, String v, Rect r, {bool emphasize = false}) {
    _text(c, '$k  ', Rect.fromLTWH(r.left, r.top, 145, r.height), 15, bold: true);
    _text(c, v.isEmpty ? '-' : v,
        Rect.fromLTWH(r.left + 145, r.top, r.width - 145, r.height),
        emphasize ? 19 : 16,
        bold: emphasize);
  }
'@
$newS = @'
  void _kv(Canvas c, String k, String v, Rect r, {bool emphasize = false}) {
    const labelW = 165.0;
    _text(
      c,
      k,
      Rect.fromLTWH(r.left, r.top, labelW, r.height),
      16,
      bold: true,
      center: true,
    );
    _text(
      c,
      v.isEmpty ? '-' : v,
      Rect.fromLTWH(r.left + labelW, r.top, r.width - labelW, r.height),
      emphasize ? 21 : 19,
      bold: emphasize,
      center: true,
    );
  }
'@
if ($x.Contains($oldS)) {
  $x = $x.Replace($oldS,$newS)
} else {
  Write-Host "Statement _kv exact block not found; using regex." -ForegroundColor Yellow
  $x = [regex]::Replace(
    $x,
    "(?s)  void _kv\(Canvas c, String k, String v, Rect r, \{bool emphasize = false\}\) \{.*?\r?\n  \}\r?\n\r?\n  void _labelValue",
    $newS + [Environment]::NewLine + "  void _labelValue",
    1
  )
}
[IO.File]::WriteAllText($s,$x,[Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Patch111 applied." -ForegroundColor Green
Write-Host "- Full-width centered titles"
Write-Host "- Centered company/customer labels and values"
Write-Host "- Slightly larger top information typography"
Write-Host "Run: flutter analyze"
Write-Host "Then: flutter run"
