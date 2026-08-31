$ErrorActionPreference = 'Stop'
$project = (Get-Location).Path
$path = Join-Path $project 'supabase/functions/export-shipment-excel/index.ts'
if (!(Test-Path $path)) { throw "missing $path" }

$text = [IO.File]::ReadAllText($path)

$replacements = @(
  @(
    'const names = [...workbook.matchAll(/<sheet\\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\\/?>/g)].map(m => m[1]);',
    'const names = [...workbook.matchAll(/<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g)].map(m => m[1]);'
  ),
  @(
    'return prefix ? upper.startsWith(prefix.toUpperCase()) && /\\d+\\s*$/.test(name) : false;',
    'return prefix ? upper.startsWith(prefix.toUpperCase()) && /\d+\s*$/.test(name) : false;'
  ),
  @(
    'for (const m of xml.matchAll(/<c\\b[^>]*r="([A-Z]+\\d+)"[^>]*>[\\s\\S]*?<\\/c>/g)) {',
    'for (const m of xml.matchAll(/<c\b[^>]*r="([A-Z]+\d+)"[^>]*>[\s\S]*?<\/c>/g)) {'
  )
)

$changed = 0
foreach ($pair in $replacements) {
  $old = $pair[0]
  $new = $pair[1]
  if ($text.Contains($old)) {
    $text = $text.Replace($old, $new)
    $changed++
  } elseif (-not $text.Contains($new)) {
    throw "Patch162b expected anchor not found. Stop without writing: $old"
  }
}

[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))

Write-Host "Patch162b repaired regex literals. changed=$changed" -ForegroundColor Green
Write-Host 'NEXT: npx supabase functions deploy export-shipment-excel'
Write-Host 'THEN: flutter analyze'
