$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot

# pdf dependency
$pub = Join-Path $project 'pubspec.yaml'
$t = Get-Content $pub -Raw -Encoding UTF8
if ($t -notmatch '(?m)^\s*pdf:\s*\^') {
  $t = $t -replace "(?m)^(\s*intl:\s*\^[^\r\n]+)", "`$1`r`n  pdf: ^3.11.3"
}

# QR assets declarations
foreach ($asset in @(
  'assets/images/payment_qr_usd.png',
  'assets/images/payment_qr_kip.png',
  'assets/images/payment_qr_thb.png',
  'assets/images/company_stamp.png'
)) {
  if ($t -notmatch [regex]::Escape("- $asset")) {
    $needle = "    - assets/images/company_logo.png"
    if ($t.Contains($needle)) {
      $t = $t.Replace($needle, "$needle`r`n    - $asset")
    } else {
      throw "pubspec assets anchor not found"
    }
  }
}
Set-Content $pub $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch102 디지털 Form 적용 완료' -ForegroundColor Green
Write-Host '- Excel 배경 PNG 좌표 덧쓰기 구조 제거'
Write-Host '- LK Group 앱 전용 가견적서/명세서 Form'
Write-Host '- 실제중량 / 용적중량 조건부 색상'
Write-Host '- 채택 운임적용중량 파란 강조'
Write-Host '- 이름/연락처/영수번호/구획/금액 강조'
Write-Host '- 기존 QR 이미지 3종 유지'
Write-Host '- 최소 병합 개념의 독립 셀/영역 구조'
Write-Host '- 이미지 저장 + 출력용 PDF'
Write-Host '- 명세서 10행 초과 시 문서 높이 자동 증가'
Write-Host ''
Write-Host '실행: flutter pub get'
Write-Host '      flutter analyze'
Write-Host '      flutter run'
