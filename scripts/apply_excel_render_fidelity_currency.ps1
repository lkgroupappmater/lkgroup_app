$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

function Read-Utf8($path) { Get-Content $path -Raw -Encoding UTF8 }
function Write-Utf8($path,$text) { Set-Content $path $text -Encoding UTF8 }

# ------------------------------------------------------------
# 1) RouteCatalog: 기존 경로는 Excel form title을 그대로 사용.
#    신규/동적 경로가 BASE를 상속할 때만 title overlay 허용.
# ------------------------------------------------------------
$rPath = Join-Path $project 'lib/core/route_catalog.dart'
$r = Read-Utf8 $rPath
$marker = "  static String formRouteKeyFor(String labelOrKey) =>`r`n      baseRouteKeyFor(labelOrKey);"
if (-not $r.Contains($marker)) {
  $marker = "  static String formRouteKeyFor(String labelOrKey) =>`n      baseRouteKeyFor(labelOrKey);"
}
if (-not $r.Contains("static bool usesInheritedForm")) {
  $addition = $marker + @'

  /// 기존 내장/실제 경로는 자기 Excel form 제목을 그대로 사용하고,
  /// 신규 동적 경로가 다른 BASE form을 상속하는 경우에만 최소 title overlay를 허용합니다.
  static bool usesInheritedForm(String labelOrKey) {
    final key = keyFor(labelOrKey);
    return baseRouteKeyFor(labelOrKey) != key;
  }
'@
  $r = $r.Replace($marker,$addition)
}
Write-Utf8 $rPath $r

# ------------------------------------------------------------
# 2) Quotation: Excel 원본 form을 기본. 임의 crop 제거.
#    기존 경로 title/receipt overlay 제거, 동적 상속 경로만 허용.
# ------------------------------------------------------------
$qPath = Join-Path $project 'lib/screens/quotation_preview_dialog.dart'
$q = Read-Utf8 $qPath

$q = [regex]::Replace(
  $q,
  "Rect _documentRect\(ui\.Image image\) \{[\s\S]*?\r?\n  \}",
@"
Rect _documentRect(ui.Image image) {
    final logical = _logicalSize(image);
    // 실제 Excel PrintArea/Form 경계를 그대로 저장한다.
    // 앱 Preview 바깥 padding은 저장 PNG에 포함되지 않는다.
    return Rect.fromLTWH(0, 0, logical.width, logical.height);
  }
"@,
  1
)

$q = $q.Replace(
"    _paintRouteHeader(canvas);",
"    if (RouteCatalog.usesInheritedForm(routeLabel)) {`r`n      _paintRouteHeader(canvas);`r`n    }"
)
Write-Utf8 $qPath $q

# ------------------------------------------------------------
# 3) Statement: Excel 원본 title을 유지.
#    신규 동적 상속 경로만 title overlay.
# ------------------------------------------------------------
$sPath = Join-Path $project 'lib/screens/statement_preview_dialog.dart'
$s = Read-Utf8 $sPath

$s = $s.Replace(
"    _paintRouteTitle(canvas, w, h);",
"    if (RouteCatalog.usesInheritedForm(routeLabel)) {`r`n      _paintRouteTitle(canvas, w, h);`r`n    }"
)

# MoneyFormat import
if (-not $s.Contains("import '../core/money_format.dart';")) {
  $s = $s.Replace(
    "import '../core/route_catalog.dart';",
    "import '../core/route_catalog.dart';`r`nimport '../core/money_format.dart';"
  )
}

$s = $s.Replace(
"'\\$${freight.totalUsd.toStringAsFixed(2)}'",
"MoneyFormat.usd(freight.totalUsd)"
)
$s = $s.Replace(
"'${freight.totalKip.toStringAsFixed(0)}'",
"MoneyFormat.number(freight.totalKip)"
)
$s = $s.Replace(
"'${freight.totalThb.toStringAsFixed(1)}'",
"MoneyFormat.number(freight.totalThb, decimals: 2)"
)
$s = $s.Replace(
"'${freight.totalKrw.toStringAsFixed(0)}'",
"MoneyFormat.number(freight.totalKrw)"
)
Write-Utf8 $sPath $s

# ------------------------------------------------------------
# 4) Cargo management + shipment search의 통화 표시를 공통 formatter로 통일
# ------------------------------------------------------------
foreach ($rel in @(
  'lib/screens/cargo_management_screen.dart',
  'lib/screens/shipment_search_screen.dart'
)) {
  $p = Join-Path $project $rel
  if (-not (Test-Path $p)) { continue }
  $t = Read-Utf8 $p

  if (-not $t.Contains("import '../core/money_format.dart';")) {
    if ($t.Contains("import '../core/route_catalog.dart';")) {
      $t = $t.Replace(
        "import '../core/route_catalog.dart';",
        "import '../core/route_catalog.dart';`r`nimport '../core/money_format.dart';"
      )
    } else {
      $t = "import '../core/money_format.dart';`r`n" + $t
    }
  }

  # group freight / statement popups
  $t = $t.Replace(
    "'USD  \\$${result.totalUsd.toStringAsFixed(2)}'",
    "'USD  ${MoneyFormat.usd(result.totalUsd)}'"
  )
  $t = $t.Replace(
    "'KIP  ${result.totalKip.toStringAsFixed(0)}'",
    "'KIP  ${MoneyFormat.kip(result.totalKip)}'"
  )
  $t = $t.Replace(
    "'THB  ${result.totalThb.toStringAsFixed(1)}'",
    "'THB  ${MoneyFormat.thb(result.totalThb)}'"
  )
  $t = $t.Replace(
    "'KRW  ${result.totalKrw.toStringAsFixed(0)}'",
    "'KRW  ${MoneyFormat.krw(result.totalKrw)}'"
  )

  $t = $t.Replace(
    "'USD  \\$${freight.totalUsd.toStringAsFixed(2)}'",
    "'USD  ${MoneyFormat.usd(freight.totalUsd)}'"
  )
  $t = $t.Replace(
    "'KIP  ${freight.totalKip.toStringAsFixed(0)}'",
    "'KIP  ${MoneyFormat.kip(freight.totalKip)}'"
  )
  $t = $t.Replace(
    "'THB  ${freight.totalThb.toStringAsFixed(1)}'",
    "'THB  ${MoneyFormat.thb(freight.totalThb)}'"
  )
  $t = $t.Replace(
    "'KRW  ${freight.totalKrw.toStringAsFixed(0)}'",
    "'KRW  ${MoneyFormat.krw(freight.totalKrw)}'"
  )

  # individual freight line USD
  $t = $t.Replace(
    "'\\$${line.amountUsd.toStringAsFixed(2)}'",
    "MoneyFormat.usd(line.amountUsd)"
  )

  Write-Utf8 $p $t
}

Write-Host ''
Write-Host 'Patch100 적용 완료' -ForegroundColor Green
Write-Host '- 기존 경로: Excel form title을 Flutter가 덮어쓰지 않음'
Write-Host '- 신규 상속 경로: 필요한 경우에만 최소 title overlay'
Write-Host '- 견적/명세서 저장: 임의 crop 제거, Form 경계 그대로'
Write-Host '- 앱 통화 표시에 공통 천단위/소수점 formatter 적용'
Write-Host ''
Write-Host '선택: QUOTATION_EXCEL_TEMPLATES의 최신 PrintArea를 assets로 다시 만들려면'
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\rebuild_excel_printarea_assets.ps1'
Write-Host ''
Write-Host '그 다음 flutter analyze -> flutter run'
