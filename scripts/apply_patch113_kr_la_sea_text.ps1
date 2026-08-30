$ErrorActionPreference="Stop"
$p=Split-Path -Parent $PSScriptRoot
$q=Join-Path $p "lib\screens\quotation_preview_dialog.dart"
$s=Join-Path $p "lib\screens\statement_preview_dialog.dart"
foreach($f in @($q,$s)){if(!(Test-Path -LiteralPath $f)){throw "Missing $f"}}

# QUOTATION: exact KR-LA Sea wording from the shared reference form.
$x=Get-Content -LiteralPath $q -Raw -Encoding UTF8
$seaRemark="본 가견적은 입력된 중량/규격을 기준으로 한 예상 운임입니다. 실제 입고 후 실측 중량·용적중량 중 큰 값을 운임 적용중량으로 사용하며, 최종 청구금액은 실제 측정 결과에 따라 달라질 수 있습니다."
$seaFooter="* 운임은 USD 기준입니다.  * 입·출고지를 떠나기 전 고객님 운임 물품 및 개수 확인 부탁드립니다.  * 물품 출고 후 1주 후부터 보관료가 발생할 수 있습니다.  * 이용해 주셔서 감사합니다."

# Replace current Remark value expression with route-aware exact SEA text.
$x=$x.Replace(
  "RouteCatalog.remarkFor(routeLabel).isEmpty`r`n        ? '본 가견적은 입력된 중량/규격을 기준으로 한 예상 운임입니다. 실제 입고 후 실측 중량·용적중량 중 큰 값을 운임 적용중량으로 사용하며, 최종 청구금액은 실제 측정 결과에 따라 달라질 수 있습니다.'`r`n        : RouteCatalog.remarkFor(routeLabel)",
  "RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'`r`n        ? '$seaRemark'`r`n        : (RouteCatalog.remarkFor(routeLabel).isEmpty`r`n            ? '$seaRemark'`r`n            : RouteCatalog.remarkFor(routeLabel))"
)
$x=$x.Replace(
  "RouteCatalog.remarkFor(routeLabel).isEmpty`n        ? '본 가견적은 입력된 중량/규격을 기준으로 한 예상 운임입니다. 실제 입고 후 실측 중량·용적중량 중 큰 값을 운임 적용중량으로 사용하며, 최종 청구금액은 실제 측정 결과에 따라 달라질 수 있습니다.'`n        : RouteCatalog.remarkFor(routeLabel)",
  "RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'`n        ? '$seaRemark'`n        : (RouteCatalog.remarkFor(routeLabel).isEmpty`n            ? '$seaRemark'`n            : RouteCatalog.remarkFor(routeLabel))"
)

# Patch lower center notice routeNotice block.
$x=$x.Replace(
  "final routeNotice = RouteCatalog.remarkFor(routeLabel);",
  "final routeNotice = RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'`r`n        ? '$seaFooter'`r`n        : RouteCatalog.remarkFor(routeLabel);"
)
[IO.File]::WriteAllText($q,$x,[Text.UTF8Encoding]::new($false))

# STATEMENT: exact SEA-style footer wording; keep route remark if DB has a statement-specific remark.
$x=Get-Content -LiteralPath $s -Raw -Encoding UTF8
$x=$x.Replace(
  "final routeNotice = RouteCatalog.remarkFor(routeLabel);",
  "final routeNotice = RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'`r`n        ? '$seaFooter'`r`n        : RouteCatalog.remarkFor(routeLabel);"
)
[IO.File]::WriteAllText($s,$x,[Text.UTF8Encoding]::new($false))

Write-Host "Patch113 applied: KR-LA Sea route-specific wording." -ForegroundColor Green
Write-Host "Run: flutter analyze"
Write-Host "Then: flutter run"
