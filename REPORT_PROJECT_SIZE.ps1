$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== LKGroup project size report ===" -ForegroundColor Cyan

function Get-DirSizeMB($path) {
    if (-not (Test-Path $path)) { return 0 }
    $sum = (Get-ChildItem $path -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $sum) { return 0 }
    return [math]::Round($sum / 1MB, 2)
}

$targets = @(
    ".git",
    "build",
    ".dart_tool",
    ".artifacts",
    "android\.gradle",
    ".idea",
    "assets",
    "lib",
    "supabase"
)

$rows = foreach ($t in $targets) {
    if (Test-Path $t) {
        [PSCustomObject]@{
            Path = $t
            SizeMB = Get-DirSizeMB $t
        }
    }
}
$rows | Sort-Object SizeMB -Descending | Format-Table -AutoSize

Write-Host ""
Write-Host "=== Top 40 large files ===" -ForegroundColor Cyan
Get-ChildItem . -Force -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "\\\.git\\" } |
    Sort-Object Length -Descending |
    Select-Object -First 40 @{N="MB";E={[math]::Round($_.Length/1MB,2)}}, FullName |
    Format-Table -AutoSize

Write-Host ""
Write-Host "=== Tracked backup/patch junk candidates ===" -ForegroundColor Yellow
$tracked = git ls-files 2>$null
$tracked | Where-Object {
    $_ -match '(^|/)(APPLY_.*\.ps1|PATCH.*\.py|README_PATCH.*\.txt)$' -or
    $_ -match '\.bak(_before_patch.*)?$' -or
    $_ -match '\.bak_before_patch'
} | Select-Object -First 300

Write-Host ""
Write-Host "=== Untracked patch/temp candidates ===" -ForegroundColor Yellow
git status --porcelain |
    Where-Object { $_ -match '^\?\?' } |
    ForEach-Object { $_.Substring(3) } |
    Where-Object {
        $_ -match '(^|/)(APPLY_.*\.ps1|PATCH.*\.py|README_PATCH.*\.txt|.*\.zip)$'
    }

Write-Host ""
Write-Host "Report only. Nothing deleted." -ForegroundColor Green
