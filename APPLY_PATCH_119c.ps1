$ErrorActionPreference = "Stop"
$project = (Get-Location).Path
$target = Join-Path $project "pubspec.yaml"
$source = Join-Path $PSScriptRoot "pubspec.yaml"

if (!(Test-Path $target)) { throw "pubspec.yaml을 찾을 수 없습니다." }
Copy-Item $target "$target.bak_before_patch119c" -Force

# Read/write explicitly as UTF-8 to repair mojibake.
$content = Get-Content -Raw -Encoding UTF8 $source
[System.IO.File]::WriteAllText($target, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host "Patch119c 적용 완료"
Write-Host "- 손상된 pubspec.yaml UTF-8 복구"
Write-Host "- 기존 dependency/version 유지"
Write-Host "- Google Maps 아이콘 asset 포함"
Write-Host "- 앱 Dart 코드/DB/SQL 변경 없음"
