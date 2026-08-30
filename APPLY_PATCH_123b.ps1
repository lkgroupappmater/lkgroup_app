$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Pubspec = Join-Path $Root "pubspec.yaml"
$Facebook = Join-Path $Root "assets\images\facebook_icon.png"

if (!(Test-Path $Pubspec)) {
  throw "pubspec.yaml 을 찾을 수 없습니다: $Pubspec"
}
if (!(Test-Path $Facebook)) {
  throw "Facebook 이미지 파일을 찾을 수 없습니다: $Facebook`nPatch123을 먼저 적용했는지 확인해 주세요."
}

Copy-Item $Pubspec "$Pubspec.bak_before_patch123b" -Force
$text = Get-Content $Pubspec -Raw -Encoding UTF8

if ($text -match '(?m)^\s*-\s*assets/images/facebook_icon\.png\s*$') {
  Write-Host "facebook_icon.png 은 이미 pubspec.yaml에 등록되어 있습니다."
} else {
  $needleCRLF = "    - assets/images/google_maps_icon.png`r`n"
  $insertCRLF = "    - assets/images/google_maps_icon.png`r`n    - assets/images/facebook_icon.png`r`n"
  $needleLF = "    - assets/images/google_maps_icon.png`n"
  $insertLF = "    - assets/images/google_maps_icon.png`n    - assets/images/facebook_icon.png`n"

  if ($text.Contains($needleCRLF)) {
    $text = $text.Replace($needleCRLF, $insertCRLF)
  } elseif ($text.Contains($needleLF)) {
    $text = $text.Replace($needleLF, $insertLF)
  } else {
    throw "google_maps_icon.png asset 줄을 찾지 못했습니다. pubspec.yaml 구조를 확인해 주세요."
  }

  Set-Content $Pubspec $text -Encoding UTF8
  Write-Host "pubspec.yaml에 facebook_icon.png 등록 완료"
}

Write-Host ""
Write-Host "다음 실행:"
Write-Host "flutter pub get"
Write-Host "flutter run"
