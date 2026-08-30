$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot

$files = @(
  (Join-Path $project "lib\screens\quotation_preview_dialog.dart"),
  (Join-Path $project "lib\screens\statement_preview_dialog.dart")
)

foreach ($f in $files) {
  if (!(Test-Path $f)) { throw "Missing file: $f" }
  $s = Get-Content -LiteralPath $f -Raw -Encoding UTF8

  # Keep one guaranteed blank row after the actual boxes, while preserving the 10-row minimum.
  $s = $s.Replace("int get _visibleRows => widget.boxes.length < 10 ? 10 : widget.boxes.length;",
                  "int get _visibleRows => widget.boxes.length + 1 < 10 ? 10 : widget.boxes.length + 1;")
  $s = $s.Replace("int get _visibleRows => _rows.length < 10 ? 10 : _rows.length;",
                  "int get _visibleRows => _rows.length + 1 < 10 ? 10 : _rows.length + 1;")
  $s = $s.Replace("final rowCount = boxes.length < 10 ? 10 : boxes.length;",
                  "final rowCount = boxes.length + 1 < 10 ? 10 : boxes.length + 1;")
  $s = $s.Replace("final rowCount = rows.length < 10 ? 10 : rows.length;",
                  "final rowCount = rows.length + 1 < 10 ? 10 : rows.length + 1;")

  # Company address: one line, larger and centered in the existing cell.
  $s = $s.Replace("'비엔티엔시, 씨싿따낙구, 싸판텅 느아 09, 11번 골목,\n엘케이(LK) 빌딩, 1층 LK Trading',",
                  "'비엔티엔시, 씨싿따낙구, 싸판텅 느아 09, 11번 골목, 엘케이(LK) 빌딩, 1층 LK Trading',")
  $s = $s.Replace("valueSize: 14,`r`n      valueLines: 2,", "valueSize: 16,`r`n      valueLines: 1,")
  $s = $s.Replace("valueSize: 14,`n      valueLines: 2,", "valueSize: 16,`n      valueLines: 1,")

  # All document titles use the whole document width, so the title is truly page-centered.
  $s = [regex]::Replace($s,
    "Rect\.fromLTWH\(190,\s*16,\s*940,\s*58\)",
    "Rect.fromLTWH(0, 14, w, 60)")

  # Replace the annotated combined bank strip with clean individual QR/account panels.
  $old = @'
    final payTop = sumTop + 204;
    _imageContain(c, vatApplied ? bankStripVat : bankStripDefault,
        Rect.fromLTWH(8, payTop, w - 16, 150));
'@
  $new = @'
    final payTop = sumTop + 204;
    final payLeft = 8.0;
    final payW = w - 16;
    final payGap = 4.0;
    final payPanelW = (payW - payGap * 3) / 4;
    final payH = 150.0;
    _box(c, Rect.fromLTWH(payLeft, payTop, payPanelW, payH), Colors.white);
    _box(c, Rect.fromLTWH(payLeft + (payPanelW + payGap), payTop, payPanelW, payH), Colors.white);
    _box(c, Rect.fromLTWH(payLeft + (payPanelW + payGap) * 2, payTop, payPanelW, payH), Colors.white);
    _box(c, Rect.fromLTWH(payLeft + (payPanelW + payGap) * 3, payTop, payPanelW, payH), Colors.white);

    _payment(c, qrUsd, 'BCEL (USD):',
        '(SungHo Park)\n010-12-01-\n017655-60-001',
        Rect.fromLTWH(payLeft, payTop, payPanelW, payH));
    _payment(c, qrKip, 'BCEL (KIP):',
        '(SungHo Park)\n013-12-00-\n017655-60-001',
        Rect.fromLTWH(payLeft + (payPanelW + payGap), payTop, payPanelW, payH));
    _payment(c, qrThb, 'BCEL (Baht):',
        '(SungHo Park)\n010-12-02-\n017655-60-001',
        Rect.fromLTWH(payLeft + (payPanelW + payGap) * 2, payTop, payPanelW, payH));

    final fourth = Rect.fromLTWH(
        payLeft + (payPanelW + payGap) * 3, payTop, payPanelW, payH);
    if (vatApplied) {
      // VAT customer: keep the dedicated VAT account image and preserve its aspect ratio.
      _imageContain(c, bankStripVat, fourth.deflate(6));
    } else {
      _text(c, '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
          fourth.deflate(10), 18, bold: true, center: true,
          maxLinesOverride: 4);
    }
'@
  if ($s.Contains($old)) {
    $s = $s.Replace($old, $new)
  } else {
    Write-Host "Bank-strip block not exact-match in $f; trying regex..." -ForegroundColor Yellow
    $s = [regex]::Replace($s,
      "    final payTop = sumTop \+ 204;\r?\n    _imageContain\(c, vatApplied \? bankStripVat : bankStripDefault,\r?\n        Rect\.fromLTWH\(8, payTop, w - 16, 150\)\);",
      $new.TrimEnd())
  }

  # Center the stamp inside the LK Trading signature box instead of pushing it to the right.
  $s = [regex]::Replace($s,
    "_imageContain\(c, stamp, Rect\.fromLTWH\(signW - 125, signTop \+ 8, 110, 90\)\);",
    "_imageContain(c, stamp, Rect.fromLTWH((signW - 110) / 2, signTop + 30, 110, 68));")

  Set-Content -LiteralPath $f -Value $s -Encoding UTF8
  Write-Host "UPDATED: $f" -ForegroundColor Green
}

Write-Host ""
Write-Host "Patch107 applied. Run flutter analyze, then flutter run." -ForegroundColor Cyan
