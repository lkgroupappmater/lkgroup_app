$ErrorActionPreference = 'Stop'

# Microsoft Excel이 설치된 Windows 개발 PC에서만 사용하는 "원본 Form asset 재생성" 도구입니다.
# XLSX 파일 자체는 수정하지 않습니다.
# Excel의 실제 PrintArea를 CopyPicture(xlPrinter/xlPicture)로 캡처하여
# 앱 assets의 PNG를 다시 만듭니다.

$project = Split-Path -Parent $PSScriptRoot
$templateDir = Join-Path $project 'QUOTATION_EXCEL_TEMPLATES'
$qOut = Join-Path $project 'assets\quotation_forms'
$sOut = Join-Path $project 'assets\statement_forms'

if (-not (Test-Path $templateDir)) {
  throw "QUOTATION_EXCEL_TEMPLATES 폴더를 찾을 수 없습니다: $templateDir"
}

New-Item -ItemType Directory -Force -Path $qOut | Out-Null
New-Item -ItemType Directory -Force -Path $sOut | Out-Null

$routeMap = [ordered]@{
  'KR_LA_SEA'     = 'kr_la_sea'
  'KR_LA_AIR'     = 'kr_la_air'
  'LA_KR_AIR_EXP' = 'la_kr_air_exp'
  'LA_TH_LAND'    = 'la_th_land'
  'TH_LA_LAND'    = 'th_la_land'
  'LA_VN_LAND'    = 'la_vn_land'
  'VN_LA_LAND'    = 'vn_la_land'
  'LA_CH_LAND'    = 'la_ch_land'
  'CH_LA_LAND'    = 'ch_la_land'
  'LA_KH_LAND'    = 'la_kh_land'
  'KH_LA_LAND'    = 'kh_la_land'
}

function Get-RouteKey([string]$fileName) {
  $u = [IO.Path]::GetFileNameWithoutExtension($fileName).ToUpperInvariant()
  foreach ($prefix in $routeMap.Keys) {
    if ($u.StartsWith($prefix)) { return $routeMap[$prefix] }
  }
  return $null
}

function Export-PrintAreaPng($sheet, [string]$outputPath) {
  $printArea = [string]$sheet.PageSetup.PrintArea
  if ([string]::IsNullOrWhiteSpace($printArea)) {
    $range = $sheet.UsedRange
  } else {
    $range = $sheet.Range($printArea)
  }

  # Excel 자체 렌더링을 사용: 서식/폰트/병합셀/색상/테두리 그대로.
  $range.CopyPicture(2, -4147) # xlPrinter, xlPicture

  $chartObj = $sheet.ChartObjects().Add(0, 0, $range.Width, $range.Height)
  try {
    $chartObj.Chart.Paste() | Out-Null
    $chartObj.Chart.ChartArea.Format.Line.Visible = 0
    $ok = $chartObj.Chart.Export($outputPath, 'PNG')
    if (-not $ok) { throw "PNG export 실패: $outputPath" }
  } finally {
    $chartObj.Delete()
  }
}

$excel = $null
try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $excel.ScreenUpdating = $false

  # 루트/하위폴더 모두 검색 + 기존 .xls까지 허용.
  # Excel 임시 잠금파일(~$...)은 제외.
  $files = @(
    Get-ChildItem $templateDir -File -Recurse -ErrorAction Stop |
      Where-Object {
        $_.Name -notlike '~$*' -and
        $_.Extension.ToLowerInvariant() -in '.xlsx','.xlsm','.xlsb','.xls'
      }
  )

  if ($files.Count -eq 0) {
    Write-Host ''
    Write-Host 'QUOTATION_EXCEL_TEMPLATES 폴더에서 확인된 파일:' -ForegroundColor Yellow
    Get-ChildItem $templateDir -File -Recurse |
      ForEach-Object { Write-Host " - $($_.FullName)" }
    throw "사용 가능한 Excel 템플릿(.xlsx/.xlsm/.xlsb/.xls)을 찾지 못했습니다: $templateDir"
  }

  Write-Host "검색된 Excel 템플릿: $($files.Count)개" -ForegroundColor Green
  foreach ($f in $files) {
    Write-Host " - $($f.FullName)"
  }

  foreach ($file in $files) {
    $routeKey = Get-RouteKey $file.Name
    if (-not $routeKey) {
      Write-Warning "경로 key 추론 실패, 건너뜀: $($file.Name)"
      continue
    }

    Write-Host "Excel 원본 렌더: $($file.Name) -> $routeKey" -ForegroundColor Cyan
    $wb = $excel.Workbooks.Open($file.FullName, 0, $true)
    try {
      $quoteSheet = $null
      $statementSheet = $null
      $visibleCandidates = @()

      foreach ($sheet in $wb.Worksheets) {
        $n = [string]$sheet.Name
        $normalized = ($n -replace '[\s_\-\(\)\[\]\.]','').ToUpperInvariant()

        Write-Host "  Sheet: [$n] / normalized=[$normalized]" -ForegroundColor DarkGray

        if ($sheet.Visible -eq -1) {
          $visibleCandidates += $sheet
        }

        if (-not $quoteSheet -and (
              $normalized -match '가견적' -or
              $normalized -match '견적' -or
              $normalized -match 'QUOTATION' -or
              $normalized -match 'QUOTE'
            )) {
          $quoteSheet = $sheet
        }

        if (-not $statementSheet -and (
              $normalized -match '명세' -or
              $normalized -match '거래명세' -or
              $normalized -match 'STATEMENT'
            )) {
          $statementSheet = $sheet
        }
      }

      # QUOTATION 전용 workbook에서 이름이 예상과 달라도
      # 실제 사용 가능한 visible sheet가 하나라면 그것을 견적서로 사용.
      if (-not $quoteSheet -and $visibleCandidates.Count -eq 1) {
        $quoteSheet = $visibleCandidates[0]
        Write-Host "  견적서 Sheet fallback(유일 visible sheet): $($quoteSheet.Name)" -ForegroundColor Yellow
      }

      # visible sheet가 여러 개면 PrintArea가 있는 sheet를 우선 선택.
      if (-not $quoteSheet -and $visibleCandidates.Count -gt 1) {
        foreach ($candidate in $visibleCandidates) {
          $pa = [string]$candidate.PageSetup.PrintArea
          if (-not [string]::IsNullOrWhiteSpace($pa)) {
            $quoteSheet = $candidate
            Write-Host "  견적서 Sheet fallback(PrintArea): $($quoteSheet.Name)" -ForegroundColor Yellow
            break
          }
        }
      }

      # 그래도 못 찾으면 첫 visible sheet를 마지막 fallback으로 사용.
      if (-not $quoteSheet -and $visibleCandidates.Count -gt 0) {
        $quoteSheet = $visibleCandidates[0]
        Write-Host "  견적서 Sheet fallback(first visible): $($quoteSheet.Name)" -ForegroundColor Yellow
      }

      if ($quoteSheet) {
        $path = Join-Path $qOut "$routeKey.png"
        Export-PrintAreaPng $quoteSheet $path
        Write-Host "  견적서 -> $path" -ForegroundColor Green
      } else {
        Write-Warning "  견적서 Sheet 없음: $($file.Name)"
      }

      if ($statementSheet) {
        $path = Join-Path $sOut "$routeKey.png"
        Export-PrintAreaPng $statementSheet $path
        Write-Host "  명세서 -> $path" -ForegroundColor Green
      }
    } finally {
      $wb.Close($false)
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($wb)
    }
  }
} finally {
  if ($excel) {
    $excel.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}

Write-Host ''
Write-Host 'Excel PrintArea 기반 Form asset 재생성 완료' -ForegroundColor Green
Write-Host '원본 Excel 파일은 수정하지 않았습니다.'


