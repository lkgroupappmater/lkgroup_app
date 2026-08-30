$ErrorActionPreference="Stop"
$p=Split-Path -Parent $PSScriptRoot
$q=Join-Path $p "lib\screens\quotation_preview_dialog.dart"
$s=Join-Path $p "lib\screens\statement_preview_dialog.dart"
foreach($f in @($q,$s)){if(!(Test-Path $f)){throw "Missing $f"}}

function Common($f){
 $x=Get-Content $f -Raw -Encoding UTF8
 # Requested header colors only: actual sum=orange, volume sum=green.
 $x=$x -replace "null, null, null, null, null, null, null, null, null, null, null,\s*actualColor, volumeColor, appliedColor","null, null, null, null, null, actualColor, null, null, null, null, volumeColor,`r`n      actualColor, volumeColor, appliedColor"
 # Slightly enlarge table/header typography.
 $x=$x.Replace("r.deflate(3), 15, bold: true, center: true","r.deflate(3), 16, bold: true, center: true")
 $x=$x.Replace("col >= 10 && col <= 12 ? 17 : 15","col >= 10 && col <= 12 ? 18 : 16")
 [IO.File]::WriteAllText($f,$x,[Text.UTF8Encoding]::new($false))
}
Common $q; Common $s

# Quotation: left company rows were compressed; align to the same 3-row grid.
$x=Get-Content $q -Raw -Encoding UTF8
$x=$x.Replace("Rect.fromLTWH(8, infoTop + 2, w * .49, 22)","Rect.fromLTWH(8, infoTop + 4, w * .49, 28)")
$x=$x.Replace("Rect.fromLTWH(8, infoTop + 24, w * .49, 22)","Rect.fromLTWH(8, infoTop + 39, w * .49, 28)")
$x=$x.Replace("Rect.fromLTWH(8, infoTop + 46, w * .49, 22)","Rect.fromLTWH(8, infoTop + 74, w * .49, 28)")
$x=$x.Replace("Rect.fromLTWH(w * .5, infoTop + 7, w * .49, 30)","Rect.fromLTWH(w * .5, infoTop + 4, w * .49, 28)")
$x=$x.Replace("Rect.fromLTWH(w * .5, infoTop + 41, w * .49, 30)","Rect.fromLTWH(w * .5, infoTop + 39, w * .49, 28)")
$x=$x.Replace("Rect.fromLTWH(w * .5, infoTop + 73, w * .49, 26)","Rect.fromLTWH(w * .5, infoTop + 74, w * .49, 28)")
[IO.File]::WriteAllText($q,$x,[Text.UTF8Encoding]::new($false))

# Statement: right customer area -> three clean rows, receipt gets its own labeled row.
$x=Get-Content $s -Raw -Encoding UTF8
$x=$x.Replace("Rect.fromLTWH(half + 8, infoTop + 8, half - 16, 38), emphasize: true);","Rect.fromLTWH(half + 8, infoTop + 4, half - 16, 28), emphasize: true);")
$x=$x.Replace("Rect.fromLTWH(half + 8, infoTop + 52, half - 220, 38), emphasize: true);","Rect.fromLTWH(half + 8, infoTop + 39, half - 16, 28), emphasize: true);")
$x=$x -replace "_text\(c, receiptNumber, Rect\.fromLTWH\(w - 220, infoTop \+ 52, 205, 38\),\s*23, bold: true, center: true\);","_kv(c, '영수번호', receiptNumber, Rect.fromLTWH(half + 8, infoTop + 74, half - 16, 28), emphasize: true);"
# Safety: obsolete extra painter value must stay removed.
$x=[regex]::Replace($x,"(?s)(f == null \? '-' : MoneyFormat\.usd\(f\.amountUsd\),)\s*\r?\n\s*actualWins \? .*?\r?\n\s*\];",'$1'+[Environment]::NewLine+'      ];',1)
[IO.File]::WriteAllText($s,$x,[Text.UTF8Encoding]::new($false))
Write-Host "Patch110 applied: quotation + statement alignment/header colors/font sizing." -ForegroundColor Green
