$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$files = @(
  (Join-Path $project "lib\screens\quotation_preview_dialog.dart"),
  (Join-Path $project "lib\screens\statement_preview_dialog.dart")
)
foreach($f in $files){
  if(!(Test-Path -LiteralPath $f)){ throw "Missing file: $f" }
}

function ReplaceSingleline([string]$inputText, [string]$pattern, [string]$replacement) {
  $rx = [System.Text.RegularExpressions.Regex]::new(
    $pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  return $rx.Replace($inputText, $replacement, 1)
}

function Patch-Form([string]$f, [bool]$isStatement) {
  $x = Get-Content -LiteralPath $f -Raw -Encoding UTF8

  # Inland delivery body blank when there is no linked delivery data.
  $x = ReplaceSingleline $x `
    "_text\(c,\s*'배송비/선불·착불/배송업체 등 추후 입력',\s*Rect\.fromLTWH\([^;]+?\);" `
    ""

  # QR/account area: full-width 4 equal panels.
  $pattern = "    final payTop = sumTop \+ 204;.*?    final noteTop = payTop \+ 150;"
  $replacement = @'
    final payTop = sumTop + 204;
    const payGap = 4.0;
    final payW = (w - payGap * 3) / 4;
    final payRects = <Rect>[
      Rect.fromLTWH(0, payTop, payW, 150),
      Rect.fromLTWH(payW + payGap, payTop, payW, 150),
      Rect.fromLTWH((payW + payGap) * 2, payTop, payW, 150),
      Rect.fromLTWH((payW + payGap) * 3, payTop, payW, 150),
    ];

    for (final r in payRects) {
      _box(c, r, Colors.white);
    }

    _payment(
      c,
      qrUsd,
      'BCEL (USD):',
      '(SungHo Park)\n010-12-01-\n017655-60-001',
      payRects[0],
    );
    _payment(
      c,
      qrKip,
      'BCEL (KIP):',
      '(SungHo Park)\n013-12-00-\n017655-60-001',
      payRects[1],
    );
    _payment(
      c,
      qrThb,
      'BCEL (Baht):',
      '(SungHo Park)\n010-12-02-\n017655-60-001',
      payRects[2],
    );
    _text(
      c,
      '한국 원화 계좌:\n경남은행\n571-22-0330221\n박성호',
      payRects[3].deflate(8),
      18,
      bold: true,
      center: true,
    );

    final noteTop = payTop + 150;
'@
  $before = $x
  $x = ReplaceSingleline $x $pattern $replacement
  if($before -eq $x){
    Write-Host "NOTE: payment block not matched in $f" -ForegroundColor Yellow
  }

  # Larger QR, preserve aspect ratio.
  $x = $x.Replace(
    "_imageContain(c, image, Rect.fromLTWH(r.left + 8, r.top + 5, 118, 118));",
    "_imageContain(c, image, Rect.fromLTWH(r.left + 6, r.top + 6, 132, 132));"
  )
  $x = $x.Replace(
    "Rect.fromLTWH(r.left + 132, r.top + 8, r.width - 136, 28)",
    "Rect.fromLTWH(r.left + 144, r.top + 8, r.width - 150, 30)"
  )
  $x = $x.Replace(
    "Rect.fromLTWH(r.left + 132, r.top + 38, r.width - 136, 92)",
    "Rect.fromLTWH(r.left + 144, r.top + 40, r.width - 150, 98)"
  )

  # Narrow signature boxes and center stamp.
  $x = $x.Replace("final signW = w * .34;", "final signW = w * .26;")
  $x = ReplaceSingleline $x `
    "_imageContain\(c, stamp, Rect\.fromLTWH\([^;]+?\);" `
    "_imageContain(c, stamp, Rect.fromLTWH((signW - 105) / 2, signTop + 34, 105, 64));"

  # Route-specific lower notice.
  if($isStatement){
    $fallback = "* 입·출고지를 떠나기 전 운임 물품 및 개수 확인 부탁드립니다.  * 물품 출고 후 보관료가 발생할 수 있습니다.  * 이용해 주셔서 감사합니다."
  } else {
    $fallback = "* 가견적은 예상 중량/크기 기준이며 실제 측정 결과에 따라 최종 운임이 달라질 수 있습니다.  * 운임은 USD 기준이며 환율 변동에 따라 기타 통화 금액이 달라질 수 있습니다."
  }

  $noticeReplacement = @"
    final routeNotice = RouteCatalog.remarkFor(routeLabel);
    _text(
      c,
      routeNotice.isEmpty ? '$fallback' : routeNotice,
      Rect.fromLTWH(signW + 18, signTop + 6, w - signW * 2 - 36, signH - 12),
      13,
      center: true,
    );
"@
  $x = ReplaceSingleline $x `
    "    _text\(c,\s*'\* 운임은 USD 기준입니다\..*?14, center: true\);" `
    $noticeReplacement

  [System.IO.File]::WriteAllText(
    $f,
    $x,
    [System.Text.UTF8Encoding]::new($false)
  )
}

Patch-Form $files[0] $false
Patch-Form $files[1] $true

Write-Host ""
Write-Host "Patch112b applied." -ForegroundColor Green
Write-Host "Run: flutter analyze"
Write-Host "Then: flutter run"
