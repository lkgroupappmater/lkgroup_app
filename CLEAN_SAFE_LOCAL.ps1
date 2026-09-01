$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== SAFE local cleanup ===" -ForegroundColor Cyan
Write-Host "This deletes only rebuildable generated folders and UNTRACKED patch/temp files." -ForegroundColor Yellow
Write-Host "Tracked source/history files are NOT deleted." -ForegroundColor Yellow

$generated = @(
    "build",
    ".dart_tool",
    ".artifacts",
    "coverage",
    ".pub"
)

foreach ($p in $generated) {
    if (Test-Path $p) {
        Write-Host "Removing $p ..."
        Remove-Item $p -Recurse -Force -ErrorAction Stop
    }
}

# android/.gradle is local Gradle cache and safely rebuildable.
if (Test-Path "android\.gradle") {
    Write-Host "Removing android\.gradle ..."
    Remove-Item "android\.gradle" -Recurse -Force -ErrorAction Stop
}

# Delete only UNTRACKED patch/temp artifacts, never tracked files.
$untracked = git status --porcelain |
    Where-Object { $_ -match '^\?\?' } |
    ForEach-Object { $_.Substring(3) }

foreach ($f in $untracked) {
    $normalized = $f -replace '/', '\'
    if ($f -match '(^|/)(APPLY_.*\.ps1|PATCH.*\.py|README_PATCH.*\.txt|.*\.zip)$') {
        if (Test-Path $normalized) {
            Write-Host "Removing untracked temp: $f"
            Remove-Item $normalized -Recurse -Force -ErrorAction Stop
        }
    }
}

Write-Host ""
Write-Host "Safe cleanup complete." -ForegroundColor Green
Write-Host "Run: flutter pub get" -ForegroundColor Cyan
Write-Host "Then: flutter analyze" -ForegroundColor Cyan
