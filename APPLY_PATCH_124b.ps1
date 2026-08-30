$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$AnalysisOptions = Join-Path $Root "analysis_options.yaml"

if (!(Test-Path $AnalysisOptions)) {
  throw "analysis_options.yaml 을 찾을 수 없습니다: $AnalysisOptions"
}

Copy-Item $AnalysisOptions "$AnalysisOptions.bak_before_patch124b" -Force
$text = Get-Content $AnalysisOptions -Raw -Encoding UTF8

# Patch124의 설치용 원본 폴더(patch_files)가 flutter analyze 대상에 들어가
# 실제 lib 파일과 무관한 가짜 import 오류를 만들고 있습니다.
# 기존 analyzer exclude가 있으면 patch_files/**만 추가하고,
# 없으면 analyzer exclude 블록을 추가합니다.
if ($text -match '(?m)^\s*-\s*patch_files/\*\*\s*$') {
  Write-Host "patch_files/** 는 이미 analyzer 제외 상태입니다."
}
elseif ($text -match '(?m)^analyzer:\s*$') {
  if ($text -match '(?ms)^analyzer:\s*\r?\n(\s+)exclude:\s*\r?\n') {
    $text = [regex]::Replace(
      $text,
      '(?ms)^(analyzer:\s*\r?\n(?:[ \t]+.*\r?\n)*?[ \t]+exclude:\s*\r?\n)',
      '$1    - patch_files/**' + "`r`n",
      1
    )
  } else {
    $text = [regex]::Replace(
      $text,
      '(?m)^analyzer:\s*$',
      "analyzer:`r`n  exclude:`r`n    - patch_files/**",
      1
    )
  }
}
else {
  $text = $text.TrimEnd() + "`r`n`r`nanalyzer:`r`n  exclude:`r`n    - patch_files/**`r`n"
}

Set-Content $AnalysisOptions $text -Encoding UTF8

Write-Host "Patch124b 적용 완료."
Write-Host "Patch124의 실제 lib 파일은 건드리지 않았습니다."
Write-Host "설치용 patch_files/** 폴더만 flutter analyze 대상에서 제외했습니다."
Write-Host ""
Write-Host "다음 실행:"
Write-Host "flutter analyze"
