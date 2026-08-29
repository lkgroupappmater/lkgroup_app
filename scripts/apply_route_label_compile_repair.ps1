$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# quotation_preview_dialog.dart
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

# constructor named parameter
if($t -notmatch "const _QuotationFormPainter\(\{\s*required this\.routeLabel,") {
  $t=[regex]::Replace(
    $t,
    "const _QuotationFormPainter\(\{\s*required this\.template,",
    "const _QuotationFormPainter({`r`n    required this.routeLabel,`r`n    required this.template,",
    1
  )
}
# field
$cls=$t.IndexOf("class _QuotationFormPainter extends CustomPainter")
if($cls -lt 0){ throw 'quotation painter class not found' }
$after=$t.Substring($cls)
if($after -notmatch "final String routeLabel;") {
  $idx=$t.IndexOf("  final ui.Image template;",$cls)
  if($idx -lt 0){ throw 'quotation template field not found' }
  $t=$t.Insert($idx,"  final String routeLabel;`r`n")
}

# Ensure calls pass routeLabel
$t=[regex]::Replace(
  $t,
  "_QuotationFormPainter\(\s*(?!routeLabel:)",
  "_QuotationFormPainter(`r`n      routeLabel: widget.routeLabel,`r`n      ",
  2
)

# remove stale unused getter warning
$t=[regex]::Replace(
  $t,
  "\s*String get _routeKey => RouteCatalog\.keyFor\(widget\.routeLabel\);\s*",
  "`r`n  ",
  1
)

Save-Utf8 $p $t

# statement_preview_dialog.dart
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

if($t -notmatch "const _StatementPainter\(\{\s*required this\.template,\s*required this\.routeLabel,") {
  $t=[regex]::Replace(
    $t,
    "const _StatementPainter\(\{\s*required this\.template,\s*required this\.rows,",
    "const _StatementPainter({`r`n    required this.template,`r`n    required this.routeLabel,`r`n    required this.rows,",
    1
  )
}
$cls=$t.IndexOf("class _StatementPainter extends CustomPainter")
if($cls -lt 0){ throw 'statement painter class not found' }
$after=$t.Substring($cls)
if($after -notmatch "final String routeLabel;") {
  $idx=$t.IndexOf("  final ui.Image template;",$cls)
  if($idx -lt 0){ throw 'statement template field not found' }
  $insertAt=$idx+"  final ui.Image template;".Length
  $t=$t.Insert($insertAt,"`r`n  final String routeLabel;")
}

# Ensure constructor call passes routeLabel
$t=[regex]::Replace(
  $t,
  "_StatementPainter\(\s*template: image,\s*(?!routeLabel:)",
  "_StatementPainter(`r`n        template: image,`r`n        routeLabel: widget.routeLabel,`r`n        ",
  2
)

# remove stale unused getter warning
$t=[regex]::Replace(
  $t,
  "\s*String get _routeKey => RouteCatalog\.keyFor\(widget\.routeLabel\)\.toLowerCase\(\);\s*",
  "`r`n  ",
  1
)

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch094 완료: routeLabel painter parameter compile repair'
