$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

function Apply-File($sourceRel, $targetRel) {
  $source = Join-Path $Root $sourceRel
  $target = Join-Path $Root $targetRel
  if (!(Test-Path $source)) { throw "패치 파일 없음: $source" }
  $dir = Split-Path $target -Parent
  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (Test-Path $target) { Copy-Item $target "$target.bak_before_patch124" -Force }
  Copy-Item $source $target -Force
}

Apply-File "patch_files\lib\services\receipt_settlement_service.dart" "lib\services\receipt_settlement_service.dart"
Apply-File "patch_files\lib\screens\voyage_total_management_screen.dart" "lib\screens\voyage_total_management_screen.dart"

Write-Host "Patch124 적용 완료."
Write-Host "SQL 변경 없음."
Write-Host "다음: flutter analyze"
