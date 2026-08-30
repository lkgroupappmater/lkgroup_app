$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$p = Join-Path $project 'scripts\rebuild_excel_printarea_assets.ps1'

if (-not (Test-Path $p)) {
  throw "rebuild_excel_printarea_assets.ps1 not found: $p"
}

$t = Get-Content $p -Raw -Encoding UTF8

$old = @"
      `$quoteSheet = `$null
      `$statementSheet = `$null

      foreach (`$sheet in `$wb.Worksheets) {
        `$n = [string]`$sheet.Name
        if (-not `$quoteSheet -and (`$n -match '가견적|견적|QUOT')) {
          `$quoteSheet = `$sheet
        }
        if (-not `$statementSheet -and (`$n -match '명세|STATEMENT')) {
          `$statementSheet = `$sheet
        }
      }
"@

$new = @"
      `$quoteSheet = `$null
      `$statementSheet = `$null
      `$visibleCandidates = @()

      foreach (`$sheet in `$wb.Worksheets) {
        `$n = [string]`$sheet.Name
        `$normalized = (`$n -replace '[\s_\-\(\)\[\]\.]','').ToUpperInvariant()

        Write-Host "  Sheet: [`$n] / normalized=[`$normalized]" -ForegroundColor DarkGray

        if (`$sheet.Visible -eq -1) {
          `$visibleCandidates += `$sheet
        }

        if (-not `$quoteSheet -and (
              `$normalized -match '가견적' -or
              `$normalized -match '견적' -or
              `$normalized -match 'QUOTATION' -or
              `$normalized -match 'QUOTE'
            )) {
          `$quoteSheet = `$sheet
        }

        if (-not `$statementSheet -and (
              `$normalized -match '명세' -or
              `$normalized -match '거래명세' -or
              `$normalized -match 'STATEMENT'
            )) {
          `$statementSheet = `$sheet
        }
      }

      # QUOTATION 전용 workbook에서 이름이 예상과 달라도
      # 실제 사용 가능한 visible sheet가 하나라면 그것을 견적서로 사용.
      if (-not `$quoteSheet -and `$visibleCandidates.Count -eq 1) {
        `$quoteSheet = `$visibleCandidates[0]
        Write-Host "  견적서 Sheet fallback(유일 visible sheet): `$(`$quoteSheet.Name)" -ForegroundColor Yellow
      }

      # visible sheet가 여러 개면 PrintArea가 있는 sheet를 우선 선택.
      if (-not `$quoteSheet -and `$visibleCandidates.Count -gt 1) {
        foreach (`$candidate in `$visibleCandidates) {
          `$pa = [string]`$candidate.PageSetup.PrintArea
          if (-not [string]::IsNullOrWhiteSpace(`$pa)) {
            `$quoteSheet = `$candidate
            Write-Host "  견적서 Sheet fallback(PrintArea): `$(`$quoteSheet.Name)" -ForegroundColor Yellow
            break
          }
        }
      }

      # 그래도 못 찾으면 첫 visible sheet를 마지막 fallback으로 사용.
      if (-not `$quoteSheet -and `$visibleCandidates.Count -gt 0) {
        `$quoteSheet = `$visibleCandidates[0]
        Write-Host "  견적서 Sheet fallback(first visible): `$(`$quoteSheet.Name)" -ForegroundColor Yellow
      }
"@

if ($t.Contains($old)) {
  $t = $t.Replace($old,$new)
} else {
  $pattern = "(?s)\s*`$quoteSheet = `\$null\s*`$statementSheet = `\$null\s*foreach \(`\$sheet in `\$wb\.Worksheets\) \{.*?\r?\n\s*\}"
  if ($t -match $pattern) {
    $t = [regex]::Replace($t,$pattern,"`r`n$new",1)
  } else {
    throw "sheet detection block not found"
  }
}

Set-Content $p $t -Encoding UTF8

Write-Host ''
Write-Host 'Patch100c 완료: Excel Sheet 자동 감지 보강' -ForegroundColor Green
Write-Host '- Sheet 이름 공백/기호 제거 후 견적/명세서 키워드 판별'
Write-Host '- 유일 visible sheet fallback'
Write-Host '- PrintArea 있는 visible sheet fallback'
Write-Host '- 실행 시 실제 Sheet 이름 출력'
Write-Host ''
Write-Host '다시 실행:'
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\rebuild_excel_printarea_assets.ps1'
