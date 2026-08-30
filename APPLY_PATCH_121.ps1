$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Source = Join-Path $Root "patch_files\supabase\066_fix_admin_excel_bulk_rows_for_voyage_total.sql"
$TargetDir = Join-Path $Root "supabase"
$Target = Join-Path $TargetDir "066_fix_admin_excel_bulk_rows_for_voyage_total.sql"
if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }
Copy-Item $Source $Target -Force
Write-Host "Patch121 적용 완료."
Write-Host "Supabase SQL Editor에서 supabase/066_fix_admin_excel_bulk_rows_for_voyage_total.sql 전체를 실행하세요."
