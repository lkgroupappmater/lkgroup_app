$ErrorActionPreference = 'Stop'

# scripts 폴더의 부모가 프로젝트 루트입니다.
$project = Split-Path -Parent $PSScriptRoot

$excelPath = Join-Path $project 'lib/services/excel_import_service.dart'
$cargoPath = Join-Path $project 'lib/screens/cargo_management_screen.dart'

if (-not (Test-Path $excelPath)) {
  throw "excel_import_service.dart not found: $excelPath"
}
if (-not (Test-Path $cargoPath)) {
  throw "cargo_management_screen.dart not found: $cargoPath"
}

# Excel import의 Dart 전용 구획 계산 호출 제거.
$excel = Get-Content $excelPath -Raw -Encoding UTF8
$excel = $excel.Replace("`r`n    _applyCalculatedZones(rows, routeKey: routeKey);`r`n", "`r`n")
$excel = $excel.Replace("`n    _applyCalculatedZones(rows, routeKey: routeKey);`n", "`n")
Set-Content $excelPath $excel -Encoding UTF8

# 관리자 '박스 추가(행 추가)' 수동 Zone 입력 제거.
$cargo = Get-Content $cargoPath -Raw -Encoding UTF8
$cargo = $cargo.Replace("    final zone = TextEditingController();`r`n", "")
$cargo = $cargo.Replace("    final zone = TextEditingController();`n", "")
$cargo = $cargo.Replace("              TextField(controller: zone, decoration: const InputDecoration(labelText: '구획 (Zone)')),`r`n", "")
$cargo = $cargo.Replace("              TextField(controller: zone, decoration: const InputDecoration(labelText: '구획 (Zone)')),`n", "")
$cargo = $cargo.Replace("          unloadingZone: zone.text,`r`n", "")
$cargo = $cargo.Replace("          unloadingZone: zone.text,`n", "")
$cargo = $cargo.Replace("    zone.dispose();`r`n", "")
$cargo = $cargo.Replace("    zone.dispose();`n", "")
Set-Content $cargoPath $cargo -Encoding UTF8

Write-Host ''
Write-Host 'Patch096b 완료: 프로젝트 경로 수정 + 통합 자동화 Flutter 적용' -ForegroundColor Green
Write-Host '다음: Supabase SQL Editor에서 061 SQL 실행 후 flutter analyze'
