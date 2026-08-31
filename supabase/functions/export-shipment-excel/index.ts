import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'npm:fflate@0.8.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function escXml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function colOf(ref: string): string {
  return (ref.match(/^[A-Z]+/)?.[0] ?? '');
}

function rowOf(ref: string): number {
  return Number(ref.match(/\d+$/)?.[0] ?? 0);
}


function columnIndex(column: string): number {
  let value = 0;
  for (const ch of column.toUpperCase()) {
    const code = ch.charCodeAt(0);
    if (code < 65 || code > 90) continue;
    value = value * 26 + (code - 64);
  }
  return value;
}

function sharedStrings(files: Record<string, Uint8Array>): string[] {
  const data = files['xl/sharedStrings.xml'];
  if (!data) return [];
  const xml = strFromU8(data);
  const out: string[] = [];
  for (const match of xml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
    const body = match[1];
    const text = [...body.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)]
      .map((m) => m[1]
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&'))
      .join('');
    out.push(text);
  }
  return out;
}

function workbookSheetPath(
  files: Record<string, Uint8Array>,
  targetName: string,
): string | null {
  const workbook = strFromU8(files['xl/workbook.xml']);
  const rels = strFromU8(files['xl/_rels/workbook.xml.rels']);

  const sheetMatch = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]*)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )].find((m) => m[1] === targetName);

  if (!sheetMatch) return null;
  const relationId = sheetMatch[2];

  const relPattern = new RegExp(
    `<Relationship\\b[^>]*Id="${relationId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"[^>]*Target="([^"]+)"[^>]*/?>`,
  );
  const relMatch = rels.match(relPattern);
  if (!relMatch) return null;

  let target = relMatch[1].replace(/^\/+/, '');
  if (!target.startsWith('xl/')) target = `xl/${target}`;
  return target;
}

function cellText(cellXml: string, strings: string[]): string {
  const type = cellXml.match(/\bt="([^"]+)"/)?.[1] ?? '';
  if (type === 'inlineStr') {
    return [...cellXml.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)]
      .map((m) => m[1])
      .join('');
  }
  const raw = cellXml.match(/<v>([\s\S]*?)<\/v>/)?.[1] ?? '';
  if (type === 's') {
    const index = Number(raw);
    return Number.isFinite(index) ? strings[index] ?? '' : '';
  }
  return raw;
}

function findHeaderRow(sheetXml: string, strings: string[]): number {
  for (const rowMatch of sheetXml.matchAll(/<row\b[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = Number(rowMatch[1]);
    if (row > 20) break;
    const values: string[] = [];
    for (const cellMatch of rowMatch[2].matchAll(/<c\b[^>]*r="([A-Z]+\d+)"[^>]*>[\s\S]*?<\/c>/g)) {
      values.push(cellText(cellMatch[0], strings).trim());
    }
    const joined = values.join('|').toLowerCase();
    const hasBoxHeader =
      joined.includes('box no') ||
      joined.includes('박스') ||
      values.some((value) => {
        const normalized = value.trim().toLowerCase().replaceAll(' ', '');
        return normalized === 'no.' || normalized === 'no' || normalized === '번호';
      });
    const hasCargoColumns =
      joined.includes('송장') &&
      (joined.includes('수신') || joined.includes('수령') || joined.includes('전화번호'));

    if (hasBoxHeader && hasCargoColumns) return row;
  }
  return -1;
}

function numericCell(ref: string, style: string, value: unknown): string {
  const n = Number(value);
  if (!Number.isFinite(n)) return blankCell(ref, style);
  return `<c r="${ref}"${style}><v>${n}</v></c>`;
}

function inlineCell(ref: string, style: string, value: unknown): string {
  const text = String(value ?? '');
  if (!text) return blankCell(ref, style);
  return `<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${escXml(text)}</t></is></c>`;
}

function blankCell(ref: string, style: string): string {
  return `<c r="${ref}"${style}></c>`;
}

function updateCellPreservingFormula(
  rowXml: string,
  rowNumber: number,
  column: string,
  value: unknown,
  kind: 'text' | 'number' | 'date',
): string {
  const ref = `${column}${rowNumber}`;
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
  const existing = rowXml.match(cellRe);

  // 원본 Excel의 수식 셀은 절대 지우거나 값 셀로 바꾸지 않습니다.
  if (existing) {
    const body = existing[3] ?? '';
    if (/<f\b/.test(body)) return rowXml;
  }

  // DB 값이 비어 있으면 원본 템플릿의 기본값/수식/구획값을 그대로 유지합니다.
  // 예: KR-LA AIR O열의 102, SEA O열의 고객리스트 연동 수식.
  const empty =
    value == null ||
    String(value).trim() === '' ||
    (kind === 'number' && !Number.isFinite(Number(value)));
  if (empty) return rowXml;

  return updateCell(rowXml, rowNumber, column, value, kind);
}

function setNumericCellInSheet(
  sheetXml: string,
  ref: string,
  value: number,
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
  const updated = updateCell(rowXml, rowNumber, column, value, 'number');
  return sheetXml.replace(rowXml, updated);
}

function updateExchangeRates(
  files: Record<string, Uint8Array>,
  rates: {
    baseKip: number;
    baseThb: number;
    baseKrw: number;
    kipAdjustment: number;
    thbAdjustment: number;
    krwAdjustment: number;
  },
): void {
  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);

  const labels: Array<{ row: number; text: string }> = [];
  for (const rowMatch of xml.matchAll(
    /<row\b[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g,
  )) {
    const row = Number(rowMatch[1]);
    if (row > 8) break;
    const values: string[] = [];
    for (const cellMatch of rowMatch[2].matchAll(
      /<c\b[^>]*r="([A-Z]+\d+)"[^>]*>[\s\S]*?<\/c>/g,
    )) {
      values.push(cellText(cellMatch[0], strings).trim());
    }
    labels.push({ row, text: values.join('|') });
  }

  const usesCurrencyLabels = labels.some((v) => v.text.includes('USD-KIP'));
  if (usesCurrencyLabels) {
    xml = setNumericCellInSheet(xml, 'C3', rates.baseKip);
    xml = setNumericCellInSheet(xml, 'D3', rates.kipAdjustment);
    xml = setNumericCellInSheet(xml, 'C4', rates.baseThb);
    xml = setNumericCellInSheet(xml, 'D4', rates.thbAdjustment);
    xml = setNumericCellInSheet(xml, 'C5', rates.baseKrw);
    xml = setNumericCellInSheet(xml, 'D5', rates.krwAdjustment);
  } else {
    xml = setNumericCellInSheet(xml, 'B3', rates.baseKip);
    xml = setNumericCellInSheet(xml, 'C3', rates.kipAdjustment);
    xml = setNumericCellInSheet(xml, 'B4', rates.baseThb);
    xml = setNumericCellInSheet(xml, 'C4', rates.thbAdjustment);
    xml = setNumericCellInSheet(xml, 'B5', rates.baseKrw);
    xml = setNumericCellInSheet(xml, 'C5', rates.krwAdjustment);
  }

  files[path] = strToU8(xml);
}

function excelDateSerial(value: unknown): number | null {
  const text = String(value ?? '').trim();
  if (!text) return null;
  const date = new Date(`${text.substring(0, 10)}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return null;
  return date.getTime() / 86400000 + 25569;
}

function updateCell(
  rowXml: string,
  rowNumber: number,
  column: string,
  value: unknown,
  kind: 'text' | 'number' | 'date',
): string {
  const ref = `${column}${rowNumber}`;
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
  const existing = rowXml.match(cellRe);
  const attrs = existing
    ? `${existing[1] ?? ''}${existing[2] ?? ''}`
    : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';

  let replacement: string;
  if (kind === 'number') {
    replacement = numericCell(ref, style, value);
  } else if (kind === 'date') {
    const serial = excelDateSerial(value);
    replacement = serial == null
      ? blankCell(ref, style)
      : numericCell(ref, style, serial);
  } else {
    replacement = inlineCell(ref, style, value);
  }

  if (existing) return rowXml.replace(cellRe, replacement);

  // OOXML에서는 row 안의 <c> 셀이 열 순서대로 있어야 합니다.
  // 기존 템플릿 행이 A/B/O처럼 일부 셀만 가진 경우,
  // C~N을 row 끝에 단순 append하면 A,B,O,C,D... 순서가 되어
  // Excel이 "읽을 수 없는 내용"으로 판단하고 셀 정보를 복구/삭제합니다.
  const targetIndex = columnIndex(column);
  const cellMatches = [...rowXml.matchAll(
    /<c\b[^>]*r="([A-Z]+)\d+"[^>]*(?:\/>|>[\s\S]*?<\/c>)/g,
  )];

  for (const match of cellMatches) {
    const existingColumn = match[1];
    if (columnIndex(existingColumn) > targetIndex && match.index != null) {
      const at = match.index;
      return `${rowXml.substring(0, at)}${replacement}${rowXml.substring(at)}`;
    }
  }

  const close = rowXml.lastIndexOf('</row>');
  return close >= 0
    ? `${rowXml.substring(0, close)}${replacement}${rowXml.substring(close)}`
    : rowXml;
}

function updateCargoSheet(
  sheetXml: string,
  strings: string[],
  shipments: Record<string, unknown>[],
): string {
  const headerRow = findHeaderRow(sheetXml, strings);
  if (headerRow < 0) {
    throw new Error('"물품 입고 내역" 헤더 행을 찾지 못했습니다.');
  }

  const firstDataRow = headerRow + 1;
  const rows = [...sheetXml.matchAll(
    /<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g,
  )];
  const candidateRows = rows
    .map((m) => ({ number: Number(m[1]), xml: m[0] }))
    .filter((r) => r.number >= firstDataRow);

  if (shipments.length > candidateRows.length) {
    throw new Error(
      `현재 템플릿 화물 행 ${candidateRows.length}개보다 DB 화물 ${shipments.length}개가 많습니다. ` +
      '행 자동 확장은 다음 단계에서 해당 노선 명세서 구조와 함께 적용해야 합니다.',
    );
  }

  const mapping: Array<[string, string, 'text' | 'number' | 'date']> = [
    ['B', 'box_number', 'text'],
    ['C', 'invoice_number', 'text'],
    ['D', 'sender_name', 'text'],
    ['E', 'consignee_name', 'text'],
    ['F', 'consignee_phone', 'text'],
    ['G', 'contents', 'text'],
    ['H', 'package_type', 'text'],
    ['I', 'quantity', 'number'],
    ['J', 'weight_kg', 'number'],
    ['K', 'length_cm', 'number'],
    ['L', 'width_cm', 'number'],
    ['M', 'height_cm', 'number'],
    ['N', 'receipt_number', 'text'],
    ['O', 'unloading_zone', 'text'],
    ['P', 'notes', 'text'],
    ['Q', 'received_at', 'date'],
  ];

  // 박스번호는 현장 입고 순서 기준으로 템플릿에 고정된 슬롯입니다.
  // DB 데이터가 없는 번호도 "아직 사용하지 않은 번호"로 남겨야 하므로
  // shipments를 위에서부터 압축해 쓰지 않고 B열의 고정 박스번호와 정확히 매칭합니다.
  const shipmentByBox = new Map<string, Record<string, unknown>>();
  for (const shipment of shipments) {
    const box = String(shipment.box_number ?? '').trim().toUpperCase();
    if (box) shipmentByBox.set(box, shipment);
  }

  let output = sheetXml;
  const matchedBoxes = new Set<string>();

  for (const candidate of candidateRows) {
    const bRe = new RegExp(
      `<c\\b[^>]*r="B${candidate.number}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`,
    );
    const bMatch = candidate.xml.match(bRe);
    if (!bMatch) continue;

    const fixedBox = cellText(bMatch[0], strings).trim();
    if (!fixedBox) continue;

    const shipment = shipmentByBox.get(fixedBox.toUpperCase());
    if (!shipment) continue;

    matchedBoxes.add(fixedBox.toUpperCase());
    let rowXml = candidate.xml;

    // B열은 템플릿 고정 번호이므로 절대 덮어쓰지 않습니다.
    for (const [column, key, kind] of mapping) {
      if (column === 'B') continue;
      rowXml = updateCellPreservingFormula(
        rowXml,
        candidate.number,
        column,
        shipment[key],
        kind,
      );
    }

    output = output.replace(candidate.xml, rowXml);
  }

  const missing = [...shipmentByBox.keys()].filter((box) => !matchedBoxes.has(box));
  if (missing.length > 0) {
    throw new Error(
      `Excel 템플릿에 없는 박스번호가 있습니다: ${missing.slice(0, 10).join(', ')}`,
    );
  }

  return output;
}

function routeReceiptPrefix(routeKey: string): string {
  const map: Record<string, string> = {
    kr_la_sea: 'LKS',
    kr_la_air: 'LKA',
    la_kr_air_exp: 'LKB',
    la_th_land: 'LKLT',
    th_la_land: 'LKTL',
    la_vn_land: 'LKLV',
    vn_la_land: 'LKVL',
    la_ch_land: 'LC',
    ch_la_land: 'LKCL',
    la_kh_land: 'LKLCBL',
  };
  return map[routeKey] ?? '';
}

function normalizePhone(value: unknown): string {
  return String(value ?? '').replace(/\s+/g, '').replace(/-/g, '');
}

function assignReceiptNumbers(
  shipments: Record<string, unknown>[],
  routeKey: string,
  runtimeReceiptPrefix = '',
): Record<string, unknown>[] {
  const prefix = runtimeReceiptPrefix.trim() || routeReceiptPrefix(routeKey);
  if (!prefix) return shipments;

  // 이름 + 전화번호가 같으면 같은 영수번호를 사용합니다.
  const groupToReceipt = new Map<string, string>();
  let next = 1;

  // 기존 영수번호가 있으면 우선 그대로 유지하고 다음 번호 계산.
  for (const shipment of shipments) {
    const existing = String(shipment.receipt_number ?? '').trim();
    const hasIdentity =
      String(shipment.consignee_name ?? '').trim() !== '' &&
      normalizePhone(shipment.consignee_phone) !== '';
    const recoverableXx = hasIdentity && /\bXX\s*$/i.test(existing);
    if (existing && !recoverableXx) {
      const m = existing.match(/(\d+)\s*$/);
      if (m) next = Math.max(next, Number(m[1]) + 1);
      const key = `${String(shipment.consignee_name ?? '').trim().toLowerCase()}|${normalizePhone(shipment.consignee_phone)}`;
      if (key !== '|') groupToReceipt.set(key, existing);
    }
  }

  return shipments.map((shipment) => {
    const existing = String(shipment.receipt_number ?? '').trim();
    const name = String(shipment.consignee_name ?? '').trim();
    const phone = normalizePhone(shipment.consignee_phone);
    const recoverableXx = name !== '' && phone !== '' && /\bXX\s*$/i.test(existing);
    if (existing && !recoverableXx) return shipment;

    const key = `${name.toLowerCase()}|${phone}`;
    if (key === '|') return shipment;

    let receipt = groupToReceipt.get(key);
    if (!receipt) {
      if (routeKey === 'kr_la_sea' || routeKey === 'kr_la_air') {
        receipt = `${prefix} ${String(next).padStart(2, '0')}`;
      } else {
        receipt = `${prefix}${String(next).padStart(2, '0')}`;
      }
      groupToReceipt.set(key, receipt);
      next += 1;
    }

    return { ...shipment, receipt_number: receipt };
  });
}

function setStringCellInSheet(sheetXml: string, ref: string, value: string): string {
  const rowNumber = Number(ref.match(/\d+$/)?.[0] ?? 0);
  const column = ref.match(/^[A-Z]+/)?.[0] ?? '';
  if (!rowNumber || !column) return sheetXml;
  const rowRe = new RegExp(
    `<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`,
  );
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;
  const rowXml = rowMatch[0];
  const updated = updateCell(rowXml, rowNumber, column, value, 'text');
  return sheetXml.replace(rowXml, updated);
}

function upgradeZoneQuantityFormulas(
  files: Record<string, Uint8Array>,
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // 기존 구획 판정용 F열은 G:DL에 조회된 "화물번호 개수"만 셌습니다.
  // 따라서 1개 화물번호에 수량 100개가 들어와도 1개로 판단했습니다.
  //
  // 새 방식:
  // 같은 영수번호의 '물품 입고 내역' I열(수량)을 합산합니다.
  // - S001 / 수량 1 + S002 / 수량 1 = 2개
  // - S001 / 수량 100 = 100개
  // 두 입력 방식 모두 동일하게 처리됩니다.
  //
  // 기존 Zone 기준표(C117:D120 등)는 그대로 유지합니다.
  for (let row = 4; row <= 114; row++) {
    const ref = `F${row}`;
    const cellRe = new RegExp(
      `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>`,
    );
    const match = xml.match(cellRe);
    if (!match) continue;

    const body = match[3] ?? '';
    if (!/<f\\b/.test(body)) continue;

    const formula =
      `SUMIF('물품 입고 내역'!$N$6:$N$1005,$A${row},'물품 입고 내역'!$I$6:$I$1005)`;

    const newBody = body.replace(
      /<f\b[^>]*>[\s\S]*?<\/f>/,
      `<f>${formula}</f>`,
    );

    xml = xml.replace(
      match[0],
      `<c${match[1]}r="${ref}"${match[2]}>${newBody}</c>`,
    );
  }

  files[path] = strToU8(xml);
}
function seedCustomerListFromShipments(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // A열에 이미 영수번호가 준비되어 있는 템플릿 구조를 그대로 사용합니다.
  // 해당 영수번호 행의 B열(이름)을 직접 넣어 수식 재계산 전에도 즉시 보이게 하고,
  // C열 구획은 기존 수식/값을 보존합니다.
  const byReceipt = new Map<string, Record<string, unknown>>();
  for (const shipment of shipments) {
    const receipt = String(shipment.receipt_number ?? '').trim();
    if (receipt && !byReceipt.has(receipt)) byReceipt.set(receipt, shipment);
  }

  for (const rowMatch of xml.matchAll(
    /<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g,
  )) {
    const rowNumber = Number(rowMatch[1]);
    if (rowNumber < 4) continue;
    const rowXml = rowMatch[0];
    const aRe = new RegExp(`<c\\b[^>]*r="A${rowNumber}"[^>]*>[\\s\\S]*?<\\/c>`);
    const aMatch = rowXml.match(aRe);
    if (!aMatch) continue;
    const receipt = cellText(aMatch[0], sharedStrings(files)).trim();
    if (!receipt) continue;
    const shipment = byReceipt.get(receipt);
    if (!shipment) continue;
    const name = String(shipment.consignee_name ?? '').trim();
    if (name) xml = setStringCellInSheet(xml, `B${rowNumber}`, name);
  }

  files[path] = strToU8(xml);
}

function setCachedFormulaValue(
  sheetXml: string,
  ref: string,
  value: string | number,
  numeric: boolean,
): string {
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>`,
  );
  const match = sheetXml.match(cellRe);
  if (!match) return sheetXml;
  const body = match[3] ?? '';
  if (!/<f\b/.test(body)) return sheetXml;

  const newBody = /<v>[\s\S]*?<\/v>/.test(body)
    ? body.replace(/<v>[\s\S]*?<\/v>/, `<v>${numeric ? Number(value) : escXml(value)}</v>`)
    : `${body}<v>${numeric ? Number(value) : escXml(value)}</v>`;
  return sheetXml.replace(match[0], `<c${match[1]}r="${ref}"${match[2]}>${newBody}</c>`);
}

function refreshReceiptSheetCaches(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
): void {
  // Excel/모바일 미리보기에서 재계산 전에도 핵심 값이 보이도록
  // 기존 수식은 유지하고 cached value만 갱신합니다.
  const groups = new Map<string, Record<string, unknown>[]>();
  for (const shipment of shipments) {
    const receipt = String(shipment.receipt_number ?? '').trim();
    if (!receipt) continue;
    const list = groups.get(receipt) ?? [];
    list.push(shipment);
    groups.set(receipt, list);
  }

  for (const [receipt, rows] of groups) {
    const path = workbookSheetPath(files, receipt);
    if (!path || !files[path]) continue;
    let xml = strFromU8(files[path]);

    const first = rows[0];
    // 고객명 표시 셀 계열은 템플릿마다 수식 위치가 달라질 수 있으므로
    // 물품 행의 VLOOKUP/INDEX 공식 cached values만 보강합니다.
    for (let i = 0; i < rows.length; i++) {
      const r = 6 + i;
      const shipment = rows[i];
      if (i === 0) {
        xml = setCachedFormulaValue(xml, 'L4', String(first.consignee_phone ?? ''), false);
      }
      xml = setCachedFormulaValue(xml, `B${r}`, String(shipment.box_number ?? ''), false);
      xml = setCachedFormulaValue(xml, `D${r}`, Number(shipment.weight_kg ?? 0), true);
      xml = setCachedFormulaValue(xml, `E${r}`, Number(shipment.length_cm ?? 0), true);
      xml = setCachedFormulaValue(xml, `F${r}`, Number(shipment.width_cm ?? 0), true);
      xml = setCachedFormulaValue(xml, `G${r}`, Number(shipment.height_cm ?? 0), true);
    }
    files[path] = strToU8(xml);
  }
}


function enableDynamicReceiptSelector(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  routeKey: string,
  shipmentYear: number,
  voyage: string,
): void {
  const prefix = routeReceiptPrefix(routeKey);

  // 현재 템플릿의 실제 영수증 시트 중 "XX" 임시 시트는 제외하고
  // 첫 번째 영수증 시트를 단일 선택형 명세서로 사용합니다.
  const workbook = strFromU8(files['xl/workbook.xml']);
  const candidateNames = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )]
    .map((m) => m[1])
    .filter((name) => {
      const upper = name.toUpperCase();
      if (upper.includes('XX')) return false;
      if (!prefix) return /^\S+\s*\d+$/.test(name);
      return upper.startsWith(prefix.toUpperCase()) && /\d+\s*$/.test(name);
    });

  const sheetName = candidateNames[0];
  if (!sheetName) return;

  const path = workbookSheetPath(files, sheetName);
  if (!path || !files[path]) return;

  const receipts = [...new Set(
    shipments
      .map((row) => String(row.receipt_number ?? '').trim())
      .filter((value) => value.length > 0),
  )];

  if (receipts.length === 0) return;

  let xml = strFromU8(files[path]);

  // N2는 기존에 "현재 시트 이름"을 영수번호로 사용하던 셀입니다.
  // 이를 선택 가능한 영수번호 입력셀로 바꾸면,
  // 기존 명세서의 고객명/전화/화물/운임 수식은 전부 N2를 기준으로 이미 연결되어 있어
  // 시트를 복제하지 않고도 한 장에서 영수번호만 바꿔 전체 명세서를 볼 수 있습니다.
  xml = setStringCellInSheet(xml, 'N2', receipts[0]);

  // 기존 데이터 유효성 검사가 있으면 N2 selector만 추가하며,
  // 없으면 OOXML 순서상 pageMargins 바로 앞에 dataValidations를 삽입합니다.
  const selector =
    '<dataValidation type="list" allowBlank="1" showErrorMessage="1" ' +
    'showInputMessage="1" sqref="N2">' +
    '<formula1>INDIRECT(&quot;&apos;고객 리스트&apos;!$A$4:$A$150&quot;)</formula1>' +
    '</dataValidation>';

  if (/<dataValidations\b[^>]*>[\s\S]*?<\/dataValidations>/.test(xml)) {
    xml = xml.replace(
      /<dataValidations\b([^>]*)count="(\d+)"([^>]*)>([\s\S]*?)<\/dataValidations>/,
      (_m, before, count, after, body) => {
        const next = Number(count || 0) + 1;
        return `<dataValidations${before}count="${next}"${after}>${body}${selector}</dataValidations>`;
      },
    );
  } else {
    const block = `<dataValidations count="1">${selector}</dataValidations>`;
    if (xml.includes('<pageMargins ')) {
      xml = xml.replace('<pageMargins ', `${block}<pageMargins `);
    } else {
      xml = xml.replace('</worksheet>', `${block}</worksheet>`);
    }
  }

  // 제목의 xxth는 실제 항차로만 교체. 디자인은 그대로 유지.
  const titleMatch = xml.match(
    /<c\b([^>]*)r="C1"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/,
  );
  if (titleMatch) {
    const voyageNumber = String(voyage).replace(/^V/i, '').replace(/항차$/u, '');
    xml = setStringCellInSheet(
      xml,
      'C1',
      `Kor-Lao Sea ${voyageNumber}th 거래 명세서`,
    );
  }

  files[path] = strToU8(xml);
}
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
  // PATCH132F_LANGUAGE_DISABLED: Excel sheet XML 복구 팝업 원인 분리용.
  return;
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
function applySettlementToExistingRowData(
  files: Record<string, Uint8Array>,
  snapshot: Record<string, unknown> | null,
  routeLabel: string,
  shipmentYear: number,
  voyage: string,
): void {
  if (!snapshot) return;

  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  const voyageLabel = voyage.endsWith('항차') ? voyage : `${voyage}항차`;

  // Row data 위치는 노선별로 다릅니다.
  // 단일 단가형: 환율표 아래에서 곧바로 Total/Amount 영역이 시작될 수 있고,
  // 구간별 단가형: 환율표 -> Kg 구간 단가표 -> Total/Amount 영역 순서입니다.
  // 따라서 B14/C15... 같은 고정 행을 절대 사용하지 않고
  // 원본 Excel의 실제 라벨 위치를 찾아 중앙 FreightService snapshot을 기록합니다.
  const findLabelRow = (label: string): number | null => {
    for (const rowMatch of xml.matchAll(
      /<row\b[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g,
    )) {
      const rowNumber = Number(rowMatch[1]);
      for (const cellMatch of rowMatch[2].matchAll(
        /<c\b[^>]*r="([A-Z]+\d+)"[^>]*(?:\/>|>[\s\S]*?<\/c>)/g,
      )) {
        const ref = cellMatch[1];
        if (colOf(ref) !== 'B') continue;
        if (cellText(cellMatch[0], strings).trim() === label) {
          return rowNumber;
        }
      }
    }
    return null;
  };

  const totalRow = findLabelRow('Total');
  const amountRow = findLabelRow('Amount');
  const discountRow = findLabelRow('총 할인 금액');

  if (totalRow == null || amountRow == null) {
    // 템플릿 원본에 업무용 요약 영역이 없으면 임의 위치에 쓰지 않습니다.
    return;
  }

  // 기존 LK 템플릿은 항차 제목이 Total 바로 윗행에 배치되어 있습니다.
  // SEA/AIR의 B14, TH-LA LAND의 B23처럼 구조가 달라도 자동 대응합니다.
  const voyageTitleRow = totalRow - 1;
  if (voyageTitleRow > 0) {
    xml = setStringCellInSheet(
      xml,
      `B${voyageTitleRow}`,
      `${routeLabel} ${shipmentYear}년 ${voyageLabel}`,
    );
  }

  xml = setNumericCellInSheet(
    xml,
    `C${totalRow}`,
    Number(snapshot.total_quantity ?? 0),
  );
  xml = setNumericCellInSheet(
    xml,
    `C${amountRow}`,
    Number(snapshot.net_usd ?? 0),
  );

  if (discountRow != null) {
    xml = setNumericCellInSheet(
      xml,
      `C${discountRow}`,
      Number(snapshot.discount_usd ?? 0),
    );
  }

  files[path] = strToU8(xml);
}
function appendRowDataSettlementBlock(
  files: Record<string, Uint8Array>,
  snapshot: Record<string, unknown> | null,
  routeKey: string,
  shipmentYear: number,
  voyage: string,
): void {
  if (!snapshot) return;

  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const sheetDataClose = xml.lastIndexOf('</sheetData>');
  if (sheetDataClose < 0) return;

  const rowNumbers = [...xml.matchAll(/<row\b[^>]*r="(\d+)"/g)]
    .map((m) => Number(m[1]))
    .filter((n) => Number.isFinite(n));
  let row = (rowNumbers.length ? Math.max(...rowNumbers) : 0) + 2;

  const rows: string[] = [];
  const addRow = (values: Array<string | number | null>) => {
    const cells = values.map((value, index) => {
      const col = String.fromCharCode(65 + index);
      const ref = `${col}${row}`;
      if (value == null || value === '') return blankCell(ref, '');
      return typeof value === 'number'
        ? numericCell(ref, '', value)
        : inlineCell(ref, '', value);
    }).join('');
    rows.push(`<row r="${row}">${cells}</row>`);
    row += 1;
  };

  const receiptsRaw = snapshot.receipts;
  const receipts = Array.isArray(receiptsRaw)
    ? receiptsRaw as Record<string, unknown>[]
    : [];

  const discountRaw = snapshot.discount_by_group;
  const discountByGroup =
    discountRaw && typeof discountRaw === 'object' && !Array.isArray(discountRaw)
      ? discountRaw as Record<string, unknown>
      : {};

  addRow(['SYSTEM SETTLEMENT / 시스템 정산']);
  addRow([
    `${shipmentYear} ${voyage.endsWith('항차') ? voyage : `${voyage}항차`}`,
    routeKey,
  ]);
  addRow([
    'Receipt',
    'Customer',
    'Qty',
    'Gross USD',
    'Discount USD',
    'Amount USD',
  ]);

  for (const receipt of receipts) {
    addRow([
      String(receipt.receipt_number ?? ''),
      String(receipt.customer_name ?? ''),
      Number(receipt.total_quantity ?? 0),
      Number(receipt.gross_usd ?? 0),
      Number(receipt.discount_usd ?? 0),
      Number(receipt.net_usd ?? 0),
    ]);
  }

  row += 1;
  addRow(['Discount Group', 'Discount Amount USD']);
  for (const [group, amount] of Object.entries(discountByGroup)) {
    addRow([group, Number(amount ?? 0)]);
  }

  row += 1;
  addRow(['Total', Number(snapshot.total_quantity ?? 0)]);
  addRow(['Gross', Number(snapshot.gross_usd ?? 0)]);
  addRow(['Discount', Number(snapshot.discount_usd ?? 0)]);
  addRow(['Amount', Number(snapshot.net_usd ?? 0)]);
  addRow([
    'Calculated at',
    String(snapshot.calculated_at ?? ''),
  ]);

  xml =
    `${xml.substring(0, sheetDataClose)}${rows.join('')}${xml.substring(sheetDataClose)}`;

  // dimension은 Excel 필수 요소는 아니지만 실제 사용영역을 넓혀 둡니다.
  const finalRow = row - 1;
  if (/<dimension\b[^>]*ref="[^"]+"[^>]*\/>/.test(xml)) {
    xml = xml.replace(
      /<dimension\b([^>]*)ref="([^"]+)"([^>]*)\/>/,
      (_m, before, ref, after) => {
        const start = String(ref).split(':')[0] || 'A1';
        return `<dimension${before}ref="${start}:F${finalRow}"${after}/>`;
      },
    );
  }

  files[path] = strToU8(xml);
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: 'Supabase server environment is not configured.' });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return json(401, { error: '로그인이 필요합니다.' });

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !authData.user) return json(401, { error: '로그인 정보를 확인할 수 없습니다.' });

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', authData.user.id)
    .maybeSingle();
  if (profileError) return json(500, { error: profileError.message });
  if (!profile || !['admin', 'staff', 'partner'].includes(profile.role)) {
    return json(403, { error: '관리자·직원·협력/파트너사 권한이 필요합니다.' });
  }

  try {
    const body = await req.json();
    const routeKey = String(body.route_key ?? '').trim();
    const requestedRouteLabel = String(body.route_label ?? '').trim();
    const shipmentYear = Number(body.shipment_year);
    const voyage = String(body.voyage ?? '').trim();

    const { data: routeDefinition, error: routeDefinitionError } = await admin
      .from('route_definitions')
      .select('display_name,file_prefix,receipt_prefix,base_route_key')
      .eq('route_key', routeKey)
      .maybeSingle();
    if (routeDefinitionError) throw routeDefinitionError;

if (!routeKey || !Number.isInteger(shipmentYear) || !voyage) {
      return json(400, { error: '운송 경로/연도/항차 값이 올바르지 않습니다.' });
    }

    const { data: voyageTemplate, error: voyageTemplateError } = await admin
      .from('shipment_excel_templates')
      .select('route_key,route_label,shipment_year,voyage,file_name,storage_path')
      .eq('route_key', routeKey)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .maybeSingle();

    if (voyageTemplateError) throw voyageTemplateError;

    let template = voyageTemplate;
    let templateSource = 'voyage';

    if (!template) {
      const { data: baseTemplate, error: baseTemplateError } = await admin
        .from('shipment_excel_base_templates')
        .select('route_key,route_label,file_name,storage_path')
        .eq('route_key', routeKey)
        .eq('active', true)
        .maybeSingle();
      if (baseTemplateError) throw baseTemplateError;
      if (!baseTemplate) {
        return json(404, {
          error: '해당 운송 경로의 기본 Excel 폼과 항차별 변경 폼이 모두 없습니다.',
        });
      }
      template = {
        ...baseTemplate,
        shipment_year: shipmentYear,
        voyage,
      };
      templateSource = 'base';
    }

    const { data: templateBlob, error: downloadError } = await admin.storage
      .from('shipment-excel-templates')
      .download(template.storage_path);
    if (downloadError || !templateBlob) {
      throw downloadError ?? new Error('원본 템플릿 다운로드 실패');
    }

    const requestShipmentRows = Array.isArray(body.shipment_rows)
      ? body.shipment_rows
          .filter((row) => row != null && typeof row === 'object' && !Array.isArray(row))
          .map((row) => row as Record<string, unknown>)
      : [];
    const shipmentRouteLabel =
      requestedRouteLabel ||
      String(routeDefinition?.display_name ?? '').trim() ||
      String(template.route_label ?? '').trim();
    const { data: shipments, error: shipmentError } = await admin
      .from('shipments')
      .select(
        'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,received_at,created_at',
      )
      .eq('route', shipmentRouteLabel)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .is('deletion_requested_at', null)
      .order('box_number', { ascending: true })
      .order('id', { ascending: true });

    if (shipmentError) throw shipmentError;

    // Patch161: 실제 Excel 화물행은 DB의 현재 shipments를 source of truth로 사용합니다.
    // 특히 잠금 재업로드 변경요청이 pending/rejected인 경우 request payload의
    // incoming Excel 값을 출력에 섞지 않습니다.
    // 중앙 FreightService 정산값은 아래 voyage_settlement_snapshots에서 별도로 사용합니다.
    const exportShipmentRows =
      (shipments ?? []) as Record<string, unknown>[];

    const enrichedShipments = assignReceiptNumbers(
      exportShipmentRows,
      routeKey,
      String(routeDefinition?.receipt_prefix ?? ''),
    ).map((shipment) => {
      if (
        routeKey === 'kr_la_air' &&
        String(shipment.unloading_zone ?? '').trim() === ''
      ) {
        return { ...shipment, unloading_zone: '102' };
      }
      return shipment;
    });

    // 새로 자동 부여된 영수번호는 DB에도 저장하여 다음 조회/다운로드와 앱 화면이 동일하게 유지됩니다.
    for (const shipment of enrichedShipments) {
      const id = Number(shipment.id);
      const receipt = String(shipment.receipt_number ?? '').trim();
      const original = (shipments ?? []).find((row) => Number(row.id) === id);
      const originalReceipt = String(original?.receipt_number ?? '').trim();
      const originalWasRecoverableXx =
        /\bXX\s*$/i.test(originalReceipt) &&
        String(shipment.consignee_name ?? '').trim() !== '' &&
        normalizePhone(shipment.consignee_phone) !== '' &&
        !/\bXX\s*$/i.test(receipt);
      if (id && receipt && (!originalReceipt || originalWasRecoverableXx)) {
        const { error: receiptUpdateError } = await admin
          .from('shipments')
          .update({ receipt_number: receipt })
          .eq('id', id);
        if (receiptUpdateError) throw receiptUpdateError;
      }
    }

    const { data: exchangeRateRows, error: exchangeRateError } = await admin
      .from('exchange_rate_settings')
      .select('base_kip,base_thb,base_krw,kip_adjustment,thb_adjustment,krw_adjustment')
      .eq('id', 1)
      .limit(1);
    if (exchangeRateError) throw exchangeRateError;

    const exchangeRate = exchangeRateRows?.[0] ?? null;

    // Flutter의 중앙 FreightService가 직전에 저장한 영수번호별 정산 snapshot.
    // Excel에서는 별도 운임 공식을 다시 계산하지 않고 이 값을 그대로 기록합니다.
    const { data: settlementSnapshot, error: settlementSnapshotError } =
      await admin
        .from('voyage_settlement_snapshots')
        .select(
          'total_quantity,gross_usd,discount_usd,net_usd,discount_by_group,receipts,calculated_at',
        )
        .eq('route_key', routeKey)
        .eq('shipment_year', shipmentYear)
        .eq('voyage', voyage)
        .maybeSingle();

    if (settlementSnapshotError) throw settlementSnapshotError;

    // Patch161: 영수번호별 기타 비용을 실제 Excel 정산금액에도 반영합니다.
    // 운임 자체는 FreightService snapshot을 그대로 사용하고,
    // 기타비용은 운임 계산 후 별도 가산합니다.
    const { data: receiptExtraCosts, error: receiptExtraCostsError } =
      await admin
        .from('receipt_extra_costs')
        .select('voyage,receipt_number,cost_name,amount_usd')
        .eq('route', shipmentRouteLabel)
        .eq('shipment_year', shipmentYear);

    if (receiptExtraCostsError) throw receiptExtraCostsError;

    const voyageDigits = voyage.replace(/[^0-9]/g, '');
    const voyageExtraCosts = (receiptExtraCosts ?? []).filter((row) => {
      // 현재 테이블 select에 voyage를 포함하도록 아래 쿼리에서 보강됩니다.
      const rowVoyage = String((row as Record<string, unknown>).voyage ?? '');
      return rowVoyage.replace(/[^0-9]/g, '') === voyageDigits;
    }) as Record<string, unknown>[];

    const extraByReceipt = new Map<string, number>();
    let extraCostTotalUsd = 0;
    for (const item of voyageExtraCosts) {
      const receipt = String(item.receipt_number ?? '').trim();
      const amount = Number(item.amount_usd ?? 0);
      if (!receipt || !Number.isFinite(amount)) continue;
      extraByReceipt.set(receipt, (extraByReceipt.get(receipt) ?? 0) + amount);
      extraCostTotalUsd += amount;
    }

    const settlementForExcel =
      settlementSnapshot && typeof settlementSnapshot === 'object'
        ? (() => {
            const copy = {
              ...(settlementSnapshot as Record<string, unknown>),
            };
            const rawReceipts = Array.isArray(copy.receipts)
              ? copy.receipts as Record<string, unknown>[]
              : [];
            copy.receipts = rawReceipts.map((receipt) => {
              const receiptNo = String(receipt.receipt_number ?? '').trim();
              const extra = extraByReceipt.get(receiptNo) ?? 0;
              return {
                ...receipt,
                extra_cost_usd: extra,
                net_usd: Number(receipt.net_usd ?? 0) + extra,
              };
            });
            copy.extra_cost_usd = extraCostTotalUsd;
            copy.net_usd = Number(copy.net_usd ?? 0) + extraCostTotalUsd;
            return copy;
          })()
        : settlementSnapshot;

    const filePrefixes: Record<string, string> = {
      kr_la_sea: 'KR_LA_SEA',
      kr_la_air: 'KR_LA_AIR',
      la_kr_air_exp: 'LA_KR_AIR_EXP',
      la_th_land: 'LA_TH_LAND',
      th_la_land: 'TH_LA_LAND',
      la_vn_land: 'LA_VN_LAND',
      vn_la_land: 'VN_LA_LAND',
      la_ch_land: 'LA_CH_LAND',
      ch_la_land: 'CH_LA_LAND',
      la_kh_land: 'LA_KH_LAND',
      kh_la_land: 'KH_LA_LAND',
    };
    const prefix =
      String(routeDefinition?.file_prefix ?? '').trim() ||
      filePrefixes[routeKey] ||
      routeKey.toUpperCase();
    const voyageToken = voyage.toUpperCase().startsWith('V')
      ? voyage.toUpperCase()
      : `V${voyage}`;
    const outputFileName =
      `${prefix}_${shipmentYear}_${voyageToken}_SHIPMENTS.xlsx`;

    const original = new Uint8Array(await templateBlob.arrayBuffer());
    const files = unzipSync(original);

    const targetPath = workbookSheetPath(files, '물품 입고 내역');
    const strings = sharedStrings(files);

    if (targetPath && files[targetPath]) {
      const sheetXml = strFromU8(files[targetPath]);
      files[targetPath] = strToU8(
        updateCargoSheet(
          sheetXml,
          strings,
          enrichedShipments,
        ),
      );
    } else if (routeKey !== 'th_la_land') {
      return json(422, {
        error:
          '현재 1차 Export는 \"물품 입고 내역\" 시트가 있는 실제 Excel부터 지원합니다. 원본 템플릿은 안전하게 저장되어 있습니다.',
      });
    }
    // 실사용 Excel 연결: 고객 리스트와 기존 영수증 sheet의 cached value를 함께 갱신합니다.
    seedCustomerListFromShipments(files, enrichedShipments);
    upgradeZoneQuantityFormulas(files);
    // 한 장의 기존 명세서에서 N2 영수번호를 선택해 전체 내용을 바꾸는 동적 명세서 기반.
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
    // Patch132: SEA/AIR 언어 선택 기반 + TH-LA LAND 스팟 직접 명세서 자동입력.
    addStatementLanguageSelector(files, routeKey);
    populateSpotTransportStatement(
      files,
      enrichedShipments,
      routeKey,
      voyage,
    );
    // Patch127d: 기존 명세서 수식 셀 cached value 직접 수정은 Excel XML 손상 가능성이 있어 비활성화.
    // 명세서 동적 연결은 다음 단계에서 안전한 방식으로 처리합니다.

    // 템플릿의 xx항차 제목을 실제 선택한 항차로 바꿉니다.
    // TH-LA LAND 같은 스팟형은 물품 입고 내역 시트가 없으므로 건너뜁니다.
    if (targetPath && files[targetPath]) {
      let cargoTitleXml = strFromU8(files[targetPath]);
      const voyageLabel = voyage.endsWith('항차') ? voyage : voyage + '항차';
      cargoTitleXml = setStringCellInSheet(
        cargoTitleXml,
        'B1',
        `${shipmentYear}년 ${voyageLabel} ${shipmentRouteLabel} 물품 입고 내역 (Cargo list)`,
      );
      files[targetPath] = strToU8(cargoTitleXml);
    }

    if (exchangeRate) {
      updateExchangeRates(files, {
        baseKip: Number(exchangeRate.base_kip ?? 0),
        baseThb: Number(exchangeRate.base_thb ?? 0),
        baseKrw: Number(exchangeRate.base_krw ?? 0),
        kipAdjustment: Number(exchangeRate.kip_adjustment ?? 2000),
        thbAdjustment: Number(exchangeRate.thb_adjustment ?? 1.5),
        krwAdjustment: Number(exchangeRate.krw_adjustment ?? 40),
      });
    }

    // 기존 Row data의 실제 Total / Amount / 총 할인 금액도 같은 snapshot으로 직접 갱신합니다.
    applySettlementToExistingRowData(
      files,
      settlementForExcel as Record<string, unknown> | null,
      shipmentRouteLabel,
      shipmentYear,
      voyage,
    );
    // Patch133: Row data 하단 SYSTEM SETTLEMENT 중복 블록은 더 이상 추가하지 않습니다.
// 수식 셀 자체는 보존하고, 오래된 calcChain만 정상적으로 제거합니다.
    // calcChain을 파일만 지우고 관계/ContentType을 남기면 Excel이 복구 경고를 낼 수 있습니다.
    delete files['xl/calcChain.xml'];

    const relsPath = 'xl/_rels/workbook.xml.rels';
    if (files[relsPath]) {
      let relsXml = strFromU8(files[relsPath]);
      relsXml = relsXml.replace(
        /<Relationship\b[^>]*Type="http:\/\/schemas\.openxmlformats\.org\/officeDocument\/2006\/relationships\/calcChain"[^>]*\/>/g,
        '',
      );
      files[relsPath] = strToU8(relsXml);
    }

    const contentTypesPath = '[Content_Types].xml';
    if (files[contentTypesPath]) {
      let contentTypesXml = strFromU8(files[contentTypesPath]);
      contentTypesXml = contentTypesXml.replace(
        /<Override\b[^>]*PartName="\/xl\/calcChain\.xml"[^>]*\/>/g,
        '',
      );
      files[contentTypesPath] = strToU8(contentTypesXml);
    }

    // Excel에서 기존 VLOOKUP/INDEX/MATCH 수식을 다시 계산하도록 지정합니다.
    let workbookXml = strFromU8(files['xl/workbook.xml']);
    if (/<calcPr\b/.test(workbookXml)) {
      workbookXml = workbookXml.replace(
        /<calcPr\b[^>]*\/>/,
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>',
      );
    } else {
      workbookXml = workbookXml.replace(
        '</workbook>',
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>',
      );
    }
    files['xl/workbook.xml'] = strToU8(workbookXml);

    const encoded = zipSync(files, { level: 6 });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const exportPath =
      `${routeKey}/${shipmentYear}/${voyageToken}/${stamp}_${outputFileName}`;

    const { error: uploadError } = await admin.storage
      .from('shipment-excel-exports')
      .upload(exportPath, encoded, {
        upsert: false,
        contentType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    if (uploadError) throw uploadError;

    return json(200, {
      ok: true,
      file_name: outputFileName,
      storage_path: exportPath,
      shipment_count: shipments?.length ?? 0,
      mode: 'archive-preserving-cargo-list-v2',
      template_source: templateSource,
    });
  } catch (error) {
    let message = 'Unknown export error';
    if (error instanceof Error) {
      message = error.message;
    } else if (error && typeof error === 'object') {
      const value = error as Record<string, unknown>;
      message = String(
        value.message ??
        value.error_description ??
        value.details ??
        value.hint ??
        JSON.stringify(value),
      );
    } else {
      message = String(error);
    }

    console.error('export-shipment-excel failed:', error);
    return json(500, { error: message });
  }
});
















