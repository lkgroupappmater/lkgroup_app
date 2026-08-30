$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Target = Join-Path $Root "lib\screens\discount_management_screen.dart"
$Source = Join-Path $Root "patch_files\lib\screens\discount_management_screen.dart.txt"

if (!(Test-Path $Target)) {
  throw "대상 파일을 찾을 수 없습니다: $Target"
}
Copy-Item $Target "$Target.bak_before_patch120b" -Force
Copy-Item $Source $Target -Force
Write-Host "Patch120b 적용 완료: discount_management_screen.dart"
Write-Host "이제 flutter analyze 를 실행해 주세요."
