$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot

$dirs = @(
    (Join-Path $project "_patch106c"),
    (Join-Path $project "_rollback")
)

foreach ($dir in $dirs) {
    if (Test-Path -LiteralPath $dir) {
        Remove-Item -LiteralPath $dir -Recurse -Force
        Write-Host "REMOVED: $dir" -ForegroundColor Green
    } else {
        Write-Host "NOT FOUND (OK): $dir" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Patch106e cleanup complete." -ForegroundColor Cyan
Write-Host "Now run:"
Write-Host "flutter clean"
Write-Host "flutter pub get"
Write-Host "flutter analyze"
