$ErrorActionPreference = "Stop"

Write-Host "=== LKGroup Patch132: Excel 자동화 1차 마감 ===" -ForegroundColor Cyan

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectRoot

$tsPath = Join-Path $projectRoot "supabase\functions\export-shipment-excel\index.ts"
if (!(Test-Path $tsPath)) { throw "파일 없음: $tsPath" }

Copy-Item $tsPath "$tsPath.bak_before_patch132" -Force
$ts = Get-Content $tsPath -Raw -Encoding UTF8

if ($ts -notmatch "function populateSpotTransportStatement") {
    $anchor = "function applySettlementToExistingRowData("
    $idx = $ts.IndexOf($anchor)
    if ($idx -lt 0) { throw "index.ts: applySettlementToExistingRowData 위치를 찾지 못했습니다." }

    $helper = @'
function blankValueCellInSheet(
  sheetXml: string,
  ref: string,
): string {
  const rowNumber = Number(ref.match(/\d+$/)?.[0] ?? 0);
  const column = ref.match(/^[A-Z]+/)?.[0] ?? '';
  if (!rowNumber || !column) return sheetXml;

  const rowRe = new RegExp(
    `<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`,
  );
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;

  const rowXml = rowMatch[0];
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
  const existing = rowXml.match(cellRe);
  if (!existing) return sheetXml;

  const attrs = `${existing[1] ?? ''}${existing[2] ?? ''}`;
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';
  const replacement = `<c r="${ref}"${style}></c>`;
  return sheetXml.replace(rowXml, rowXml.replace(cellRe, replacement));
}

function populateSpotTransportStatement(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  routeKey: string,
  voyage: string,
): void {
  // TH→LA LAND 등 스팟성 운송은 SEA/AIR의 영수번호 명세서 구조로 강제 변환하지 않습니다.
  // 기존 "이름(TLxx-xx)" 명세서에 수량/중량/크기 데이터를 직접 넣는 원래 업무 방식을 유지합니다.
  if (routeKey !== 'th_la_land') return;

  const sheetName = '이름(TLxx-xx)';
  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // 현재 원본 스팟 명세서의 화물 입력 행은 6~10행(5줄)입니다.
  // B=Box/화물번호, D=수량, E=중량, G/H/I=L/W/H
  // C/F/J/K/L/M/N의 기존 운임 수식은 절대 덮어쓰지 않습니다.
  const rows = [6, 7, 8, 9, 10];
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const cargo = shipments[i];

    if (!cargo) {
      for (const col of ['B', 'D', 'E', 'G', 'H', 'I']) {
        xml = blankValueCellInSheet(xml, `${col}${row}`);
      }
      continue;
    }

    xml = setStringCellInSheet(
      xml,
      `B${row}`,
      String(cargo.box_number ?? cargo.invoice_number ?? ''),
    );
    xml = setNumericCellInSheet(xml, `D${row}`, Number(cargo.quantity ?? 0));
    xml = setNumericCellInSheet(xml, `E${row}`, Number(cargo.weight_kg ?? 0));
    xml = setNumericCellInSheet(xml, `G${row}`, Number(cargo.length_cm ?? 0));
    xml = setNumericCellInSheet(xml, `H${row}`, Number(cargo.width_cm ?? 0));
    xml = setNumericCellInSheet(xml, `I${row}`, Number(cargo.height_cm ?? 0));
  }

  // 스팟 운송번호가 이미 TLxx-xx 형태로 들어온 경우에만 원본 번호 표시 셀에 반영.
  // V00 같은 일반 voyage 값을 TL 번호로 임의 변환하지 않습니다.
  const spotNo = String(voyage ?? '').trim();
  if (/^TL[\w-]+$/i.test(spotNo)) {
    xml = setStringCellInSheet(xml, 'M1', spotNo);
  }

  files[path] = strToU8(xml);
}

function addStatementLanguageSelector(
  files: Record<string, Uint8Array>,
  routeKey: string,
): void {
  // SEA/AIR 정기항차 명세서에 언어 선택 기반을 추가합니다.
  // 실제 다국어 문구 치환은 원본 문구별 매핑을 확정한 뒤 다음 패치에서 연결합니다.
  if (routeKey !== 'kr_la_sea' && routeKey !== 'kr_la_air') return;

  const prefix = routeReceiptPrefix(routeKey);
  const workbook = strFromU8(files['xl/workbook.xml']);
  const sheetName = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )]
    .map((m) => m[1])
    .find((name) =>
      !name.toUpperCase().includes('XX') &&
      name.toUpperCase().startsWith(prefix.toUpperCase()) &&
      /\d+\s*$/.test(name)
    );

  if (!sheetName) return;
  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // P2는 기존 명세서 출력영역(A:N) 밖의 보조 선택 셀.
  // N2 영수번호 선택은 기존 Patch129 구조를 그대로 유지합니다.
  xml = setStringCellInSheet(xml, 'P1', '언어 선택 / Language');
  xml = setStringCellInSheet(xml, 'P2', '한국어');

  const languageValidation =
    '<dataValidation type="list" allowBlank="0" showErrorMessage="1" ' +
    'showInputMessage="1" sqref="P2">' +
    '<formula1>&quot;한국어,English,ລາວ&quot;</formula1>' +
    '</dataValidation>';

  if (/<dataValidations\b[^>]*>[\s\S]*?<\/dataValidations>/.test(xml)) {
    xml = xml.replace(
      /<dataValidations\b([^>]*)count="(\d+)"([^>]*)>([\s\S]*?)<\/dataValidations>/,
      (_m, before, count, after, body) => {
        if (body.includes('sqref="P2"')) {
          return _m;
        }
        const next = Number(count || 0) + 1;
        return `<dataValidations${before}count="${next}"${after}>${body}${languageValidation}</dataValidations>`;
      },
    );
  } else {
    const block = `<dataValidations count="1">${languageValidation}</dataValidations>`;
    if (xml.includes('<pageMargins ')) {
      xml = xml.replace('<pageMargins ', `${block}<pageMargins `);
    } else {
      xml = xml.replace('</worksheet>', `${block}</worksheet>`);
    }
  }

  files[path] = strToU8(xml);
}

'@
    $ts = $ts.Insert($idx, $helper)
}

$needle = @'
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
'@

if (-not $ts.Contains($needle)) {
    throw "index.ts: Patch129 enableDynamicReceiptSelector 호출을 찾지 못했습니다."
}

if ($ts -notmatch "populateSpotTransportStatement\(\s*files,\s*enrichedShipments") {
    $call = @'

    // Patch132: SEA/AIR 언어 선택 기반 + TH-LA LAND 스팟 직접 명세서 자동입력.
    addStatementLanguageSelector(files, routeKey);
    populateSpotTransportStatement(
      files,
      enrichedShipments,
      routeKey,
      voyage,
    );
'@
    $ts = $ts.Replace($needle, $needle + $call)
}

Set-Content $tsPath $ts -Encoding UTF8

Write-Host "[OK] KR-LA SEA/AIR: 기존 N2 영수번호 선택형 유지" -ForegroundColor Green
Write-Host "[OK] KR-LA SEA/AIR: 한국어 / English / ລາວ 언어 선택 기반 추가" -ForegroundColor Green
Write-Host "[OK] TH-LA LAND: '이름(TLxx-xx)' 시트 직접 데이터 자동입력" -ForegroundColor Green
Write-Host "[OK] TH-LA LAND: 수량/중량/L/W/H 입력, 기존 운임 수식 유지" -ForegroundColor Green
Write-Host ""
Write-Host "다음:" -ForegroundColor Cyan
Write-Host "  npx supabase functions deploy export-shipment-excel"
