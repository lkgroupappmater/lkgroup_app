$ErrorActionPreference = "Stop"
Write-Host "=== LKGroup Patch131 ===" -ForegroundColor Cyan

$src = Join-Path $PSScriptRoot "patch_files\supabase\071_fix_normal_cargo_receipt_zone_auto_assignment.sql"
$dstDir = Join-Path (Get-Location) "supabase"
$dst = Join-Path $dstDir "071_fix_normal_cargo_receipt_zone_auto_assignment.sql"

if (!(Test-Path $dstDir)) { throw "프로젝트 루트에서 실행해 주세요. supabase 폴더를 찾을 수 없습니다." }

Copy-Item $src $dst -Force
Write-Host ""
Write-Host "[완료] SQL 파일을 프로젝트에 복사했습니다:" -ForegroundColor Green
Write-Host "  supabase\071_fix_normal_cargo_receipt_zone_auto_assignment.sql"
Write-Host ""
Write-Host "다음 단계: Supabase SQL Editor에서 위 SQL 파일 전체 내용을 1회 실행하세요." -ForegroundColor Yellow
Write-Host "이 패치는 Flutter 파일/화면 디자인/운임 계산을 변경하지 않습니다."
