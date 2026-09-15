#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$WorkbookPath,
  [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$recipe = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'formulas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $WorkbookPath).Path
if ([IO.Path]::GetExtension($source) -ne '.xlsm') { throw '자동화 원본 XLSM 파일을 지정하세요.' }
if (-not $OutputPath) {
  $OutputPath = Join-Path ([IO.Path]::GetDirectoryName($source)) ([IO.Path]::GetFileNameWithoutExtension($source) + '_배송비추가.xlsm')
}
$target = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $target) { throw "출력 파일이 이미 있습니다. 다른 OutputPath를 지정하세요: $target" }
if ($source -eq $target) { throw '원본과 출력 경로는 달라야 합니다.' }
function Expand-Formula([string]$text, [hashtable]$variables) {
  foreach ($key in $variables.Keys) { $text = $text.Replace('{' + $key + '}', [string]$variables[$key]) }
  return $text
}
$excel = $null; $book = $null
try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false
  $excel.EnableEvents = $false
  # Do not execute workbook macros while installing the formula update.
  $excel.AutomationSecurity = 3
  $book = $excel.Workbooks.Open($source, 0, $false)
  $originalCalculation = $excel.Calculation
  $excel.Calculation = -4135
  if ($book.ReadOnly) { throw '원본이 다른 Excel에서 열려 있습니다. 닫은 뒤 다시 실행하세요.' }
  $forms = @($book.Worksheets | Where-Object { $_.Name -match '^LK[SA] (\d+|XX)$' -or $_.Name -eq '명세서 빠르게 확인' })
  $base = @($forms | Where-Object { $_.Name -match '^LK[SA] 01$' })
  if ($base.Count -ne 1) { throw '한국-라오스 해상 또는 항공 원본 양식을 확인할 수 없습니다.' }
  $prefix = ([string]$base[0].Name).Substring(0,3)
  $sourceEnd = if ($prefix -eq 'LKS') { 1005 } else { 205 }
  $incoming = $book.Worksheets.Item('물품 입고 내역')
  $customers = $book.Worksheets.Item('고객 리스트')
  if ($book.Worksheets.Item(5).Name -ne '물품 입고 내역') { throw '기존 매크로의 시트 순서가 다릅니다. 수정하지 않았습니다.' }
  $oldFit = 'If n <= 10 Then wanted = 10 Else wanted = n + 1'
  $newFit = 'If n < 10 Or (n = 10 And Len(s.Range("W6").Value) = 0) Then wanted = 10 Else wanted = n + 1'
  # Access is checked before any worksheet modification. Never change Trust Center settings.
  try {
    $module = $book.VBProject.VBComponents.Item('Module1').CodeModule
    $code = [string]$module.Lines(1, $module.CountOfLines)
  } catch {
    throw 'Excel 보안 설정 때문에 매크로 수정에 접근할 수 없습니다. Excel > 파일 > 옵션 > 보안 센터 > 보안 센터 설정 > 매크로 설정에서 VBA 프로젝트 개체 모델에 대한 신뢰할 수 있는 액세스를 허용한 뒤 다시 실행하세요. 원본은 저장하지 않았습니다.'
  }
  if (-not $code.Contains($oldFit) -and -not $code.Contains($newFit)) { throw '행 자동 조절 매크로가 예상 원본과 다릅니다. 수정하지 않았습니다.' }
  foreach ($sheet in $forms) {
    $total = [int]$sheet.Range('R6').Value2
    if ($total -lt 16 -or -not ([string]$sheet.Range('B6').Formula).Contains('VLOOKUP')) { throw "지원하지 않는 명세서 구조: $($sheet.Name)" }
  }
  $input = @($book.Worksheets | Where-Object { $_.Name -eq $recipe.inputSheet })
  $newSheet = $input.Count -eq 0
  if ($newSheet) {
    # Append after all original sheets: VBA Worksheets(5) remains valid.
    $fees = $book.Worksheets.Add([Type]::Missing, $book.Worksheets.Item($book.Worksheets.Count))
    $fees.Name = $recipe.inputSheet
    $fees.Range('A1:G1').Merge()
    $fees.Range('A1').Value2 = '한국-라오스 배송비 입력 (USD)'
    $fees.Range('A2:G2').Merge()
    $fees.Range('A2').Value2 = '선결제 배송비는 기본 할인 미적용입니다. 비용 이름·금액·할인 적용만 편집하세요.'
    $fees.Range('A3:G3').Merge()
    $fees.Range('A3').Value2 = '화물 수가 바뀌면 기존 명세서 행 맞춤 버튼을 실행하세요. 금액 빈칸은 미입력, 0은 무료입니다.'
    $headers = @('영수번호','배송구분 (자동)','비용 이름','금액 (USD)','할인 적용','고객명 (자동)','입력 상태')
    for ($i = 0; $i -lt $headers.Count; $i++) { $fees.Cells.Item(4,$i+1).Value2 = $headers[$i] }
  } else { $fees = $input[0] }
  $known = @{}; $nextRow = [int]$recipe.inputStart
  for ($r = [int]$recipe.inputStart; $r -le [int]$recipe.inputEnd; $r++) {
    $key = ([string]$fees.Cells.Item($r,1).Value2).Trim()
    if ($key) {
      if ($known.ContainsKey($key)) { throw "배송비 입력에 중복 영수번호가 있습니다: $key" }
      $known[$key] = $r; $nextRow = $r + 1
    }
  }
  $receipts = [ordered]@{}
  for ($r = 4; $r -le 205; $r++) {
    $key = ([string]$customers.Cells.Item($r,1).Value2).Trim()
    if ($key -match ('^' + $prefix + '\s*(\d+|XX)$')) { $receipts[$key] = $true }
  }
  for ($r = 6; $r -le $sourceEnd; $r++) {
    $key = ([string]$incoming.Cells.Item($r,14).Value2).Trim()
    if ($key -match ('^' + $prefix + '\s*(\d+|XX)$')) { $receipts[$key] = $true }
  }
  foreach ($key in $receipts.Keys) {
    if ($known.ContainsKey($key)) { continue }
    if ($nextRow -gt [int]$recipe.inputEnd) { throw '배송비 영수번호 201개를 초과했습니다. 수식 범위 확장이 필요합니다.' }
    $fees.Cells.Item($nextRow,1).Value2 = $key
    $fees.Cells.Item($nextRow,5).Value2 = '미적용'
    $known[$key] = $nextRow; $nextRow++
  }
  foreach ($r in $known.Values) {
    $vars = @{row=$r; sourceEnd=$sourceEnd}
    foreach ($property in $recipe.inputFormulas.PSObject.Properties) {
      $cell = $fees.Range($property.Name + $r)
      # Keep manually renamed cost names; calculated columns can be refreshed safely.
      if ($property.Name -ne 'C' -or $cell.HasFormula -or [string]::IsNullOrEmpty([string]$cell.Value2)) {
        $cell.Formula = Expand-Formula $property.Value $vars
      }
    }
  }
  $fees.Range('A4:G205').Font.Name = '맑은 고딕'
  $fees.Range('A4:G205').Font.Size = 10
  $fees.Range('A4:G4').Interior.Color = 5783578
  $fees.Range('A4:G4').Font.Color = 16777215
  $fees.Range('A4:G4').Font.Bold = $true
  $fees.Range('A:G').ColumnWidth = 20
  $fees.Range('C:C').ColumnWidth = 24
  $fees.Range('D5:E205').Interior.Color = 13434879
  $fees.Range('C5:C205').Interior.Color = 13434879
  $fees.Range('D5:D205').NumberFormat = '#,##0.00'
  $fees.Range('D5:D205').Validation.Delete()
  $fees.Range('D5:D205').Validation.Add(2,1,7,'0') # decimal >= 0, blanks allowed
  $fees.Range('D5:D205').Validation.IgnoreBlank = $true
  $fees.Range('D5:D205').Validation.ShowError = $true
  $fees.Range('E5:E205').Validation.Delete()
  $fees.Range('E5:E205').Validation.Add(3,1,1,('미적용' + $excel.International(5) + '적용'))
  $fees.Range('E5:E205').Validation.ShowError = $true
  if (-not $fees.AutoFilterMode) { $fees.Range('A4:G205').AutoFilter() | Out-Null }
  if ($code.Contains($oldFit)) {
    for ($line = 1; $line -le $module.CountOfLines; $line++) {
      $text = [string]$module.Lines($line,1)
      if ($text.Contains($oldFit)) { $module.ReplaceLine($line, $text.Replace($oldFit,$newFit)) }
    }
  }
  # Use the largest receipt so the quick selector can show every current receipt.
  $counts = @{}
  for ($r = 6; $r -le $sourceEnd; $r++) {
    $key = ([string]$incoming.Cells.Item($r,14).Value2).Trim()
    if ($key -match ('^' + $prefix + '\s*(\d+|XX)$')) { if (-not $counts.ContainsKey($key)) {$counts[$key]=0}; $counts[$key]++ }
  }
  $largest = 0
  foreach ($count in $counts.Values) { $largest = [Math]::Max($largest,$count) }
  foreach ($sheet in $forms) {
    foreach ($property in $recipe.helpers.PSObject.Properties) {
      $sheet.Range($property.Name).Formula = Expand-Formula $property.Value @{sourceEnd=$sourceEnd}
    }
    $receipt = ([string]$sheet.Range('N2').Value2).Trim()
    $count = if ($sheet.Name -eq '명세서 빠르게 확인') { $largest } elseif ($counts.ContainsKey($receipt)) { $counts[$receipt] } else { 0 }
    $wanted = [Math]::Max(10, $count + 1)
    $total = [int]$sheet.Range('R6').Value2
    if ($wanted -gt $total - 6) {
      $extra = $wanted - ($total - 6)
      $sheet.Rows.Item($total).Resize($extra).Insert(-4121) | Out-Null
      $sheet.Range('A6:N6').Copy($sheet.Range('A' + $total + ':N' + ($total + $extra - 1)))
      $total += $extra
    }
    for ($r = 6; $r -lt $total; $r++) {
      $sheet.Cells.Item($r,1).Value2 = $r - 5
      foreach ($property in $recipe.detailFormulas.PSObject.Properties) {
        $sheet.Range($property.Name + $r).Formula = Expand-Formula $property.Value @{row=$r;sourceEnd=$sourceEnd}
      }
    }
    $vars = @{grossRow=$total+1;autoRow=$total+2;fixedRow=$total+3}
    $sheet.Range('N' + ($total+2)).Formula = Expand-Formula $recipe.automaticDiscount $vars
    $sheet.Range('N' + ($total+3)).Formula = Expand-Formula $recipe.fixedDiscount $vars
    $sheet.PageSetup.PrintArea = '$A$1:$N$' + ($total + 18)
  }
  $excel.CalculateFull()
  foreach ($sheet in $forms) {
    foreach ($ref in @('W6','W7','W8','W9','W10','W11')) {
      if ([string]$sheet.Range($ref).Text -match '^#') { throw "수식 오류: $($sheet.Name)!$ref" }
    }
  }
  $excel.Calculation = $originalCalculation
  $book.SaveAs($target,52) # xlOpenXMLWorkbookMacroEnabled
  Write-Host "완료: $target"
  Write-Host '원본은 그대로 보존했습니다. 배송비 입력 시트에서 금액 및 할인 적용 여부를 입력하세요.'
} finally {
  if ($book) { $book.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($book) }
  if ($excel) { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
