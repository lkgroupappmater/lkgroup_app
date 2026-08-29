$ErrorActionPreference = 'Stop'

$path = "lib/screens/statement_preview_dialog.dart"
if (!(Test-Path $path)) { throw "파일을 찾을 수 없습니다: $path" }

$text = Get-Content -Raw -Encoding UTF8 $path

# 실제 freight_service.dart의 반환 타입은 FreightCalculation.
# 잘못 사용한 FreightCalculationResult를 정확한 타입명으로 교체.
$count = ([regex]::Matches($text, "FreightCalculationResult")).Count
if ($count -eq 0) {
  Write-Host "FreightCalculationResult 토큰이 없습니다. 이미 수정된 상태일 수 있습니다."
} else {
  $text = $text.Replace("FreightCalculationResult", "FreightCalculation")
  Set-Content -Path $path -Value $text -Encoding UTF8
  Write-Host "FreightCalculationResult -> FreightCalculation 수정 완료 ($count 곳)"
}

Write-Host "Now run: flutter analyze"
