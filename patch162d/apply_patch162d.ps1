$ErrorActionPreference = 'Stop'

$project = (Get-Location).Path
$path = Join-Path $project 'supabase/functions/export-shipment-excel/index.ts'
if (-not (Test-Path $path)) {
  throw "Patch162d target not found: $path"
}

$text = Get-Content $path -Raw -Encoding UTF8
$startToken = 'function wireStatementAutomationFormulas('
$endToken = "`nDeno.serve"
$start = $text.IndexOf($startToken)
if ($start -lt 0) {
  throw 'Patch162d start anchor not found.'
}
$end = $text.IndexOf($endToken, $start)
if ($end -lt 0) {
  throw 'Patch162d end anchor not found.'
}

$replacement = @'
function wireStatementAutomationFormulas(
  files: Record<string, Uint8Array>,
  routeKey: string,
): void {
  const prefix = routeReceiptPrefix(routeKey);
  if (!prefix) return;

  const workbook = strFromU8(files['xl/workbook.xml']);
  const sheetPattern = new RegExp(
    '<sheet\\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\\/?>',
    'g',
  );
  const names = Array.from(workbook.matchAll(sheetPattern), (m) => m[1]);
  const numberSuffix = new RegExp('\\d+\\s*$');
  const prefixUpper = prefix.toUpperCase();
  const sheetName = names.find((name) => {
    const upper = name.toUpperCase();
    return !upper.includes('XX') &&
      upper.startsWith(prefixUpper) &&
      numberSuffix.test(name);
  });
  if (!sheetName) return;

  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  let remarkRef = '';
  let inlandRef = '';
  const cellPattern = new RegExp(
    '<c\\b[^>]*r="([A-Z]+\\d+)"[^>]*>[\\s\\S]*?<\\/c>',
    'g',
  );

  for (const match of xml.matchAll(cellPattern)) {
    const label = cellText(match[0], strings).trim().toLowerCase();
    const isRemark =
      label.includes('remark') ||
      label === '\ube44\uace0';
    const isInland =
      label.includes('inland') ||
      label.includes('\uc9c0\ubc29 \ubc30\uc1a1') ||
      label.includes('\uc9c0\ubc29\ubc30\uc1a1');

    if (!remarkRef && isRemark) remarkRef = match[1];
    if (!inlandRef && isInland) inlandRef = match[1];
    if (remarkRef && inlandRef) break;
  }

  const below = (ref: string): string => {
    const col = ref.match(/^[A-Z]+/)?.[0] ?? '';
    const row = Number(ref.match(/\d+$/)?.[0] ?? 0);
    return col && row > 0 ? `${col}${row + 1}` : '';
  };

  const remarkTarget = below(remarkRef);
  const inlandTarget = below(inlandRef);
  const remarkFormula =
    `IFERROR(INDEX('Row data'!$AA:$AA,MATCH($N$2,'Row data'!$X:$X,0)),"")`;
  const inlandFormula =
    `IFERROR(INDEX('Row data'!$AB:$AB,MATCH($N$2,'Row data'!$X:$X,0)),"")`;
  const deliveryTypeFormula =
    `IFERROR(INDEX('Row data'!$AC:$AC,MATCH($N$2,'Row data'!$X:$X,0)),"")`;

  if (remarkTarget) {
    xml = setFormulaCellInSheet(xml, remarkTarget, remarkFormula);
  }
  if (inlandTarget) {
    xml = setFormulaCellInSheet(xml, inlandTarget, inlandFormula);
  }

  xml = setFormulaCellInSheet(xml, 'N3', remarkFormula);
  xml = setFormulaCellInSheet(xml, 'N4', inlandFormula);
  xml = setFormulaCellInSheet(xml, 'N5', deliveryTypeFormula);
  files[path] = strToU8(xml);
}
'@

$newText = $text.Substring(0, $start) + $replacement + $text.Substring($end)
[System.IO.File]::WriteAllText($path, $newText, [System.Text.UTF8Encoding]::new($false))

Write-Host 'Patch162d applied: wireStatementAutomationFormulas replaced safely.' -ForegroundColor Green
Write-Host 'NEXT: npx supabase functions deploy export-shipment-excel'
