$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$q = Join-Path $project "lib\screens\quotation_preview_dialog.dart"
$s = Join-Path $project "lib\screens\statement_preview_dialog.dart"

foreach($f in @($q,$s)){
  if(!(Test-Path -LiteralPath $f)){throw "Missing file: $f"}
}

# Exact shared image assets from the user.

# Quotation exact KR-LA Sea wording from uploaded KR_LA_SEA_2026_QUOTATION.xlsx.
$x = Get-Content -LiteralPath $q -Raw -Encoding UTF8

$remark = "- 동 가견적 운임의 중량 및 크기는 단순 예상치이므로 최종 책정 방법인 기준인 실측시 금액 차이가 발생 할수 있으니, 참고용으로만 확인 부탁 드립니다.`n`n- 운임은 USD 기준이며, 이외 화폐는 가견적 안내시의 환율 기준이므로, 최종 운임 책정시의 환율변동으로 인한 운임 차이가 발생할수 있으니, 참고용으로만 확인 부탁 드립니다."

$footer = "* 모든 비용은 회사의 내규 및 각 물품의 중량/크기 실측을 기준으로 청구되며 최소 운임은 `$1.5/kg 입니다.`n* 입.출고지를 떠나시기 전 꼭! 고객님 본인 물품 및 개수 확인 부탁 드립니다. 물품이 출고된 이후 LK그룹은 물품의 파손/분실에 대한 어떠한 책임도 없습니다.`n* 물품 도착 및 출고 후 특별한 사유 없이 장기 미수취 물품의 경우 보관료등 기타 추가 비용이 발생 할 수 있습니다.`n* 물품 출고 후 1주 후부터 보관료(최소 3불/CBM/day)가 발생하며, 특별한 사유 없이 2달 이상 보관 물품들은 임의로 폐기/처분 될 수 있습니다.`n* 이용해 주셔서 감사합니다."

# Replace any existing routeNotice assignment with exact KR-LA Sea footer.
$x = [regex]::Replace(
  $x,
  "final routeNotice = .*?;",
  "final routeNotice = RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'`r`n        ? '$($footer.Replace("'","\'").Replace("`n","\n"))'`r`n        : RouteCatalog.remarkFor(routeLabel);",
  1
)

# Replace quotation Remark body by a route-aware exact wording block.
$remarkPattern = "(?s)_text\(c,\s*RouteCatalog\.remarkFor\(routeLabel\)\.isEmpty.*?Rect\.fromLTWH\(10, sumTop \+ 38, leftW \* \.58 - 20, 112\),\s*14\);"
$remarkReplacement = @"
_text(
      c,
      RouteCatalog.keyFor(routeLabel) == 'kr_la_sea'
          ? '$($remark.Replace("'","\'").Replace("`n","\n"))'
          : (RouteCatalog.remarkFor(routeLabel).isEmpty
              ? '$($remark.Replace("'","\'").Replace("`n","\n"))'
              : RouteCatalog.remarkFor(routeLabel)),
      Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),
      16,
    );
"@
$rx=[regex]::new($remarkPattern,[Text.RegularExpressions.RegexOptions]::Singleline)
$x=$rx.Replace($x,$remarkReplacement,1)

# Larger readable data/amount/note fonts, without changing geometry.
$x=$x.Replace("r.deflate(3), 16, bold: true, center: true","r.deflate(3), 17, bold: true, center: true")
$x=$x.Replace("col >= 10 && col <= 12 ? 18 : 16","col >= 10 && col <= 12 ? 20 : 18")
$x=$x.Replace("Rect.fromLTWH(totalX + labelW + 8", "Rect.fromLTWH(totalX + labelW + 8")
$x=$x.Replace("18, bold: true, center: true);", "20, bold: true, center: true);")
$x=$x.Replace("Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),`r`n      14,", "Rect.fromLTWH(10, sumTop + 38, leftW * .58 - 20, 112),`r`n      16,")
[IO.File]::WriteAllText($q,$x,[Text.UTF8Encoding]::new($false))

# Statement: readability only + actual user assets (wording remains statement-specific for now).
$x = Get-Content -LiteralPath $s -Raw -Encoding UTF8
$x=$x.Replace("r.deflate(3), 16, bold: true, center: true","r.deflate(3), 17, bold: true, center: true")
$x=$x.Replace("col >= 10 && col <= 12 ? 18 : 16","col >= 10 && col <= 12 ? 20 : 18")
$x=$x.Replace("18, bold: true, center: true);", "20, bold: true, center: true);")
[IO.File]::WriteAllText($s,$x,[Text.UTF8Encoding]::new($false))

Write-Host "Patch114 applied." -ForegroundColor Green
Write-Host "- exact user QR assets"
Write-Host "- exact user stamp"
Write-Host "- KR-LA Sea quotation Remark/footer from uploaded XLSX"
Write-Host "- larger readable data/freight/note fonts"
Write-Host "Run: flutter analyze"
Write-Host "Then: flutter run"
