$ErrorActionPreference = "Stop"
$project = (Get-Location).Path
$target = Join-Path $project "lib\core\document_text_catalog.dart"
$source = Join-Path $PSScriptRoot "patch_payload\document_text_catalog.dart"

if (!(Test-Path $target)) { throw "파일 없음: $target" }
Copy-Item $target "$target.bak_before_patch116c" -Force
Copy-Item $source $target -Force

Write-Host "Patch116c 적용 완료"
Write-Host "- Remark/하단 안내문의 USD 기호($) Dart 문자열 오류만 수정"
Write-Host "- 다른 화면/기능/권한/DB 변경 없음"
