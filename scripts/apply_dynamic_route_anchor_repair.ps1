$ErrorActionPreference = 'Stop'

function Save-Utf8([string]$path,[string]$text) {
  Set-Content -Path $path -Value $text -Encoding UTF8
}

# 1) quotation_preview_dialog.dart
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

if(!$t.Contains('String get _formRouteKey')) {
  $pattern = "String get _routeKey => RouteCatalog\.keyFor\(widget\.routeLabel\);\s*_RouteFormConfig get _config => _RouteFormConfig\.forKey\(_routeKey\);"
  $replacement = @'
String get _routeKey => RouteCatalog.keyFor(widget.routeLabel);
  String get _formRouteKey =>
      RouteCatalog.formRouteKeyFor(widget.routeLabel);
  _RouteFormConfig get _config =>
      _RouteFormConfig.forKey(_formRouteKey);
'@
  $n=[regex]::Replace($t,$pattern,$replacement,1)
  if($n -eq $t){ throw 'quotation getter regex replacement failed' }
  $t=$n
}

$t=$t.Replace(
  "'assets/quotation_forms/`${_routeKey.toLowerCase()}.png'",
  "'assets/quotation_forms/`${_formRouteKey.toLowerCase()}.png'"
)
Save-Utf8 $p $t

# 2) statement_preview_dialog.dart
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p

if(!$t.Contains('String get _formRouteKey')) {
  $pattern = "String get _routeKey => RouteCatalog\.keyFor\(widget\.routeLabel\)\.toLowerCase\(\);"
  $replacement = @'
String get _routeKey => RouteCatalog.keyFor(widget.routeLabel).toLowerCase();
  String get _formRouteKey =>
      RouteCatalog.formRouteKeyFor(widget.routeLabel).toLowerCase();
'@
  $n=[regex]::Replace($t,$pattern,$replacement,1)
  if($n -eq $t){ throw 'statement getter regex replacement failed' }
  $t=$n
}

$t=$t.Replace(
  "'assets/statement_forms/`$_routeKey.png'",
  "'assets/statement_forms/`$_formRouteKey.png'"
)

$t=[regex]::Replace(
  $t,
  "int get _baseRows =>\s*_routeKey == 'kr_la_sea' \|\| _routeKey == 'kr_la_air' \? 10 : 5;",
  "int get _baseRows =>`r`n      _formRouteKey == 'kr_la_sea' || _formRouteKey == 'kr_la_air' ? 10 : 5;",
  1
)
Save-Utf8 $p $t

# 3) quote_request_screen.dart - idempotent runtime route getter
$p='lib/screens/quote_request_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
$t=$t.Replace(
  'final List<String> _transportRoutes = RouteCatalog.routes;',
  'List<String> get _transportRoutes => RouteCatalog.routes;'
)
Save-Utf8 $p $t

# 4) export-shipment-excel/index.ts
$p='supabase/functions/export-shipment-excel/index.ts'
$t=Get-Content -Raw -Encoding UTF8 $p

# receipt function signature
if(!$t.Contains('runtimeReceiptPrefix')) {
  $pattern = "function assignReceiptNumbers\(\s*shipments: Record<string, unknown>\[\],\s*routeKey: string,\s*\): Record<string, unknown>\[\] \{\s*const prefix = routeReceiptPrefix\(routeKey\);"
  $replacement = @'
function assignReceiptNumbers(
  shipments: Record<string, unknown>[],
  routeKey: string,
  runtimeReceiptPrefix = '',
): Record<string, unknown>[] {
  const prefix = runtimeReceiptPrefix.trim() || routeReceiptPrefix(routeKey);
'@
  $n=[regex]::Replace($t,$pattern,$replacement,1)
  if($n -eq $t){ throw 'export receipt function regex replacement failed' }
  $t=$n
}

# routeDefinition query after voyage
if(!$t.Contains('const { data: routeDefinition')) {
  $pattern = "const voyage = String\(body\.voyage \?\? ''\)\.trim\(\);\s*(?=if \(!routeKey \|\| !Number\.isInteger\(shipmentYear\) \|\| !voyage\))"
  $replacement = @'
const voyage = String(body.voyage ?? '').trim();

    const { data: routeDefinition, error: routeDefinitionError } = await admin
      .from('route_definitions')
      .select('display_name,file_prefix,receipt_prefix,base_route_key')
      .eq('route_key', routeKey)
      .maybeSingle();
    if (routeDefinitionError) throw routeDefinitionError;


'@
  $n=[regex]::Replace($t,$pattern,$replacement,1)
  if($n -eq $t){ throw 'export route definition regex replacement failed' }
  $t=$n
}

# assignReceiptNumbers call
$pattern = "assignReceiptNumbers\(\s*\(shipments \?\? \[\]\) as Record<string, unknown>\[\],\s*routeKey,\s*\)"
if([regex]::IsMatch($t,$pattern)) {
  $replacement = @'
assignReceiptNumbers(
      (shipments ?? []) as Record<string, unknown>[],
      routeKey,
      String(routeDefinition?.receipt_prefix ?? ''),
    )
'@
  $t=[regex]::Replace($t,$pattern,$replacement,1)
}

# dynamic file prefix
if(!$t.Contains("routeDefinition?.file_prefix")) {
  $pattern = "const prefix = filePrefixes\[routeKey\] \?\? routeKey\.toUpperCase\(\);"
  $replacement = @'
const prefix =
      String(routeDefinition?.file_prefix ?? '').trim() ||
      filePrefixes[routeKey] ||
      routeKey.toUpperCase();
'@
  $n=[regex]::Replace($t,$pattern,$replacement,1)
  if($n -eq $t){ throw 'export file prefix regex replacement failed' }
  $t=$n
}

Save-Utf8 $p $t

Write-Host ''
Write-Host 'Patch076 완료: quotation / statement / export anchor repair'
Write-Host '이제 SQL051 -> Edge Function deploy -> flutter analyze 순서로 진행하세요.'
