$ErrorActionPreference = 'Stop'
$project = (Get-Location).Path
$path = Join-Path $project 'supabase/functions/export-shipment-excel/index.ts'
if (!(Test-Path $path)) { throw "missing $path" }

$text = [IO.File]::ReadAllText($path)

$start = $text.IndexOf('function wireStatementAutomationFormulas(')
$end = $text.IndexOf('Deno.serve(async (req) => {', $start)
if ($start -lt 0 -or $end -lt 0) {
  throw 'Patch162c anchors not found. Stop without writing.'
}

$new = @'
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
  const sheetName = names.find((name) => {
    const upper = name.toUpperCase();
    return !upper.includes('XX') &&
      upper.startsWith(prefix.toUpperCase()) &&
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

  for (const m of xml.matchAll(cellPattern)) {
    const text = cellText(m[0], strings).trim().toLowerCase();
    if (!remarkRef && (text.includes('remark') || text === '비고')) {
      remarkRef = m[1];
    }
    if (!inlandRef && (
      text.includes('inland') ||
      text.includes('지방 배송') ||
      text.includes('지방배송')
    )) {
      inlandRef = m[1];
    }
  }

  const below = (ref: string): string => {
    const colMatch = ref.match(new RegExp('^[A-Z]+'));
    const rowMatch = ref.match(new RegExp('\\d+$'));
    const col = colMatch?.[0] ?? '';
    const row = Number(rowMatch?.[0] ?? 0);
    return col && row ? `${col}${row + 1}` : '';
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

$text = $text.Substring(0, $start) + $new + $text.Substring($end)
[IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))

Write-Host 'Patch162c replaced the broken statement formula helper safely.' -ForegroundColor Green
Write-Host 'NEXT: npx supabase functions deploy export-shipment-excel'
