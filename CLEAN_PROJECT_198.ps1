$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Test-Path ".\pubspec.yaml") -or -not (Test-Path ".\lib")) {
  Write-Host "ERROR: lkgroup_app root에서 실행하세요." -ForegroundColor Red
  exit 1
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
git status --short | Out-File -Encoding utf8 "CLEANUP198_before_$stamp.txt"

$generated = @("build",".dart_tool",".artifacts","coverage",".pub","android\.gradle")
foreach ($p in $generated) {
  if (Test-Path $p) {
    Write-Host "Removing cache: $p"
    Remove-Item $p -Recurse -Force
  }
}

$tracked = @(git ls-files)
$remove = New-Object System.Collections.Generic.List[string]

foreach ($f in $tracked) {
  $name = [System.IO.Path]::GetFileName($f)
  $rootFile = ($f -notmatch '/')
  $hit =
    ($rootFile -and $name -match '^(?i:APPLY_.*\.ps1)$') -or
    ($rootFile -and $name -match '^(?i:apply_patch\d.*\.ps1)$') -or
    ($rootFile -and $name -match '^(?i:apply_cargo_.*\.ps1)$') -or
    ($rootFile -and $name -match '^(?i:PATCH\d.*_apply\.py)$') -or
    ($rootFile -and $name -match '^(?i:README_PATCH.*\.txt)$') -or
    ($f -match '(?i)\.bak_before_patch') -or
    ($f -match '(?i)\.bak_before_') -or
    ($f -match '^(?i:patch\d+[a-z]?)/') -or
    ($f -match '^(?i:scripts)/(?i:apply_.*\.ps1)$')
  if ($hit) { $remove.Add($f) }
}

Write-Host ("Tracked historical files to remove: " + $remove.Count) -ForegroundColor Yellow
foreach ($f in $remove) {
  if (Test-Path -LiteralPath $f) {
    Remove-Item -LiteralPath $f -Force
  }
}

$untracked = @(git status --porcelain | Where-Object { $_ -match '^\?\?' } | ForEach-Object { $_.Substring(3) })
foreach ($f in $untracked) {
  if ($f -like "CLEAN_PROJECT_198.ps1" -or $f -like "README_CLEANUP198.txt" -or $f -like "CLEANUP198_before_*.txt") { continue }
  if ($f -match '^(?i:APPLY_.*\.ps1)$' -or
      $f -match '^(?i:PATCH\d.*_apply\.py)$' -or
      $f -match '^(?i:README_PATCH.*\.txt)$' -or
      $f -match '(?i)\.bak_before_patch' -or
      $f -match '^(?i:Patch\d.*\.zip)$') {
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Recurse -Force }
  }
}

$ignore = ".gitignore"
$content = Get-Content $ignore -Raw
$marker = "# LKGroup local/dev housekeeping"
if ($content -notmatch [regex]::Escape($marker)) {
  $block = @"

# LKGroup local/dev housekeeping
node_modules/
.artifacts/
*.bak_before_patch*
*.bak_before_*
/APPLY_*.ps1
/apply_patch*.ps1
/PATCH*_apply.py
/README_PATCH*.txt
/Patch*.zip
/patch[0-9]*/
/scripts/apply_*.ps1
/CLEANUP198_before_*.txt
"@
  Add-Content -Path $ignore -Value $block -Encoding utf8
}

Write-Host ""
Write-Host "Cleanup finished." -ForegroundColor Green
Write-Host "보존: lib, assets, base, BASE_EXCEL_TEMPLATES, QUOTATION_EXCEL_TEMPLATES, supabase, pubspec, .git"
Write-Host "다음 실행:"
Write-Host "  flutter pub get"
Write-Host "  flutter analyze"
Write-Host "  git status --short"
