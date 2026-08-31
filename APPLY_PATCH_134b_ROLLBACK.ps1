$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$cargo = Join-Path $root "lib\screens\cargo_management_screen.dart"
$approval = Join-Path $root "lib\screens\change_approval_screen.dart"

$cargoBak = "$cargo.bak_before_patch134"
$approvalBak = "$approval.bak_before_patch134"

if (!(Test-Path $cargoBak)) {
  throw "백업 파일 없음: $cargoBak"
}
if (!(Test-Path $approvalBak)) {
  throw "백업 파일 없음: $approvalBak"
}

# 현재 깨진 파일도 혹시 몰라 별도 보존
if (Test-Path $cargo) {
  Copy-Item $cargo "$cargo.broken_after_patch134" -Force
}
if (Test-Path $approval) {
  Copy-Item $approval "$approval.after_patch134" -Force
}

# Patch134 적용 직전 상태로 정확히 복원
Copy-Item $cargoBak $cargo -Force
Copy-Item $approvalBak $approval -Force

Write-Host "[OK] cargo_management_screen.dart Patch134 이전 상태 복원" -ForegroundColor Green
Write-Host "[OK] change_approval_screen.dart Patch134 이전 상태 복원" -ForegroundColor Green
Write-Host ""
Write-Host "이제 실행:" -ForegroundColor Cyan
Write-Host "flutter analyze"
