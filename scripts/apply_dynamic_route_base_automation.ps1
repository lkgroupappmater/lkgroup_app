$ErrorActionPreference = 'Stop'

function Replace-Required([string]$text,[string]$old,[string]$new,[string]$label) {
  if ($text.Contains($new)) { return $text }
  if (!$text.Contains($old)) { throw "$label anchor not found" }
  return $text.Replace($old,$new)
}

# main.dart는 ZIP의 전체 교체본을 사용합니다.`r`n`r`n# quote_request_screen.dart: always read current runtime route list.
$p='lib/screens/quote_request_screen.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
$t=$t.Replace(
  "final List<String> _transportRoutes = RouteCatalog.routes;",
  "List<String> get _transportRoutes => RouteCatalog.routes;"
)
Set-Content $p $t -Encoding UTF8

# quotation preview: new route uses selected BASE visual form/layout.
$p='lib/screens/quotation_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
if(!$t.Contains("String get _formRouteKey")){
  $t=Replace-Required $t `
    "  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel);`r`n  _RouteFormConfig get _config => _RouteFormConfig.forKey(_routeKey);" `
    "  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel);`r`n  String get _formRouteKey => RouteCatalog.formRouteKeyFor(widget.routeLabel);`r`n  _RouteFormConfig get _config => _RouteFormConfig.forKey(_formRouteKey);" `
    "quotation form route getter"
}
$t=$t.Replace(
  "assets/quotation_forms/${_routeKey.toLowerCase()}.png",
  "assets/quotation_forms/${_formRouteKey.toLowerCase()}.png"
)
Set-Content $p $t -Encoding UTF8

# statement preview: new route uses selected BASE visual form/layout.
$p='lib/screens/statement_preview_dialog.dart'
$t=Get-Content -Raw -Encoding UTF8 $p
if(!$t.Contains("String get _formRouteKey")){
  $t=Replace-Required $t `
    "  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel).toLowerCase();" `
    "  String get _routeKey => RouteCatalog.keyFor(widget.routeLabel).toLowerCase();`r`n  String get _formRouteKey => RouteCatalog.formRouteKeyFor(widget.routeLabel).toLowerCase();" `
    "statement form route getter"
}
$t=$t.Replace(
  "assets/statement_forms/$_routeKey.png",
  "assets/statement_forms/$_formRouteKey.png"
)
$t=$t.Replace(
  "int get _baseRows => _routeKey == 'kr_la_sea' || _routeKey == 'kr_la_air' ? 10 : 5;",
  "int get _baseRows => _formRouteKey == 'kr_la_sea' || _formRouteKey == 'kr_la_air' ? 10 : 5;"
)
Set-Content $p $t -Encoding UTF8

# export-shipment-excel: get route metadata from DB instead of hardcoded-only prefixes.
$p='supabase/functions/export-shipment-excel/index.ts'
$t=Get-Content -Raw -Encoding UTF8 $p

if(!$t.Contains("runtimeReceiptPrefix")){
  $old=@'
function assignReceiptNumbers(
  shipments: Record<string, unknown>[],
  routeKey: string,
): Record<string, unknown>[] {
  const prefix = routeReceiptPrefix(routeKey);
'@
  $new=@'
function assignReceiptNumbers(
  shipments: Record<string, unknown>[],
  routeKey: string,
  runtimeReceiptPrefix = '',
): Record<string, unknown>[] {
  const prefix = runtimeReceiptPrefix.trim() || routeReceiptPrefix(routeKey);
'@
  $t=Replace-Required $t $old $new "export receipt function"
}

if(!$t.Contains("const { data: routeDefinition")){
  $old=@'
    const voyage = String(body.voyage ?? '').trim();

    if (!routeKey || !Number.isInteger(shipmentYear) || !voyage)
'@
  $new=@'
    const voyage = String(body.voyage ?? '').trim();

    const { data: routeDefinition, error: routeDefinitionError } = await admin
      .from('route_definitions')
      .select('display_name,file_prefix,receipt_prefix,base_route_key')
      .eq('route_key', routeKey)
      .maybeSingle();
    if (routeDefinitionError) throw routeDefinitionError;

    if (!routeKey || !Number.isInteger(shipmentYear) || !voyage)
'@
  $t=Replace-Required $t $old $new "export route definition query"
}

$old=@'
    const enrichedShipments = assignReceiptNumbers(
      (shipments ?? []) as Record<string, unknown>[],
      routeKey,
    ).map((shipment) => {
'@
$new=@'
    const enrichedShipments = assignReceiptNumbers(
      (shipments ?? []) as Record<string, unknown>[],
      routeKey,
      String(routeDefinition?.receipt_prefix ?? ''),
    ).map((shipment) => {
'@
$t=Replace-Required $t $old $new "export assign receipt call"

$old="    const prefix = filePrefixes[routeKey] ?? routeKey.toUpperCase();"
$new="    const prefix = String(routeDefinition?.file_prefix ?? '').trim() ||`r`n      filePrefixes[routeKey] || routeKey.toUpperCase();"
$t=Replace-Required $t $old $new "export file prefix"

Set-Content $p $t -Encoding UTF8

Write-Host "동적 신규 경로 + BASE Excel 자동화 패치 완료"
Write-Host "다음: SQL051 실행, Edge Function 2개 deploy, flutter analyze/run"
