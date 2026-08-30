$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$p = Join-Path $project 'scripts\rebuild_excel_printarea_assets.ps1'

if (-not (Test-Path $p)) {
  throw "rebuild_excel_printarea_assets.ps1 not found: $p"
}

$t = Get-Content $p -Raw -Encoding UTF8

$old = @"
  `$files = Get-ChildItem `$templateDir -File |
    Where-Object { `$_.Extension -in '.xlsx','.xlsm','.xlsb' }

  if (`$files.Count -eq 0) {
    throw "템플릿 Excel 파일이 없습니다: `$templateDir"
  }
"@

$new = @"
  # 루트/하위폴더 모두 검색 + 기존 .xls까지 허용.
  # Excel 임시 잠금파일(~`$...)은 제외.
  `$files = @(
    Get-ChildItem `$templateDir -File -Recurse -ErrorAction Stop |
      Where-Object {
        `$_.Name -notlike '~`$*' -and
        `$_.Extension.ToLowerInvariant() -in '.xlsx','.xlsm','.xlsb','.xls'
      }
  )

  if (`$files.Count -eq 0) {
    Write-Host ''
    Write-Host 'QUOTATION_EXCEL_TEMPLATES 폴더에서 확인된 파일:' -ForegroundColor Yellow
    Get-ChildItem `$templateDir -File -Recurse |
      ForEach-Object { Write-Host " - `$(`$_.FullName)" }
    throw "사용 가능한 Excel 템플릿(.xlsx/.xlsm/.xlsb/.xls)을 찾지 못했습니다: `$templateDir"
  }

  Write-Host "검색된 Excel 템플릿: `$(`$files.Count)개" -ForegroundColor Green
  foreach (`$f in `$files) {
    Write-Host " - `$(`$f.FullName)"
  }
"@

if ($t.Contains($old)) {
  $t = $t.Replace($old,$new)
} else {
  $pattern = "(?s)\s*`$files = Get-ChildItem [`$]templateDir -File \|.*?throw `"템플릿 Excel 파일이 없습니다: [`$]templateDir`"\s*\}"
  if ($t -match $pattern) {
    $t = [regex]::Replace($t,$pattern,"`r`n$new",1)
  } else {
    throw "template discovery block not found"
  }
}

Set-Content $p $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch100b 완료: Excel 템플릿 검색 범위 수정' -ForegroundColor Green
Write-Host '- 하위 폴더 포함'
Write-Host '- .xlsx/.xlsm/.xlsb/.xls 지원'
Write-Host '- 검색된 파일 목록 표시'
Write-Host ''
Write-Host '다시 실행:'
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\rebuild_excel_printarea_assets.ps1'
