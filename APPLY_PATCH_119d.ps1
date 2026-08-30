$ErrorActionPreference = "Stop"

$project = (Get-Location).Path
$source = Join-Path $PSScriptRoot "patch_payload\google_maps_icon.png"
$target = Join-Path $project "assets\images\google_maps_icon.png"

if (!(Test-Path $source)) {
  throw "새 Google Maps 아이콘 파일을 찾지 못했습니다."
}
if (!(Test-Path (Split-Path $target))) {
  New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
}

if (Test-Path $target) {
  Copy-Item $target "$target.bak_before_patch119d" -Force
}

Copy-Item $source $target -Force

# 적용용 임시 폴더는 flutter analyze 대상이 되지 않도록 자동 제거
$payloadDir = Join-Path $project "patch_payload"
if (Test-Path $payloadDir) {
  Remove-Item -Recurse -Force $payloadDir
}

Write-Host "Patch119d 적용 완료"
Write-Host "- Google Maps 아이콘만 새 첨부 이미지로 교체"
Write-Host "- 링크/타이틀/화물삭제/DB/기타 화면 변경 없음"
Write-Host "- SQL 없음"
