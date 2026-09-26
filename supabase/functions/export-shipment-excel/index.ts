import { receiptOrderFormulas, fixedDiscountFormulas, RECEIPT_RULE_VERSION } from './receipt-order.mjs';
import { formatStatementAmounts } from './statement-amount-format.mjs';
import { separateStatementDiscounts, separateCargoRowDiscounts, formatCargoDiscountColumns } from './statement-discounts.mjs';
import { formatDeliveryNumbers } from './delivery-number-format.mjs';
import { zipWorkbook } from './workbook-zip.mjs';
import { documentVatContext, documentVatFormula } from './document-vat.mjs';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { unzipSync, Zip, ZipPassThrough, strFromU8, strToU8 } from 'npm:fflate@0.8.2';

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
      .map((m) => decodeXmlText(m[1]))
      .join('');
  }
  const raw = cellXml.match(/<v>([\s\S]*?)<\/v>/)?.[1] ?? '';
  if (type === 's') {
    const index = Number(raw);
    return Number.isFinite(index) ? strings[index] ?? '' : '';
  }
  return decodeXmlText(raw);
}

function decodeXmlText(value: string): string {
  return value.replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, (entity) => {
    const named: Record<string, string> = {'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"};
    if (named[entity]) return named[entity];
    const code = entity.startsWith('&#x') || entity.startsWith('&#X')
      ? parseInt(entity.slice(3, -1), 16) : Number(entity.slice(2, -1));
    return Number.isInteger(code) && code > 0 && code <= 0x10ffff
      ? String.fromCodePoint(code) : entity;
  });
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

function upgradeReceiptOrder(sheetXml: string, routeKey: string, knownLastRow?: number): string {
  if (!['kr_la_sea','kr_la_air'].includes(routeKey)) return sheetXml;
  let last = knownLastRow;
  if (last == null) {
    const rows = [...sheetXml.matchAll(/<c\b[^>]*r="AB(\d+)"/g)].map(m => Number(m[1])).filter(n => n >= 6);
    if (!rows.length || !/<c\b[^>]*r="AK6"/.test(sheetXml)) return sheetXml;
    last = Math.max(...rows);
  }
  let formulaRow = -1;
  let formulas: Record<string, string> = {};
  const separatedDiscounts = /<c\b[^>]*r="AO\d+"/.test(sheetXml);
  return sheetXml.replace(/<c\b[^>]*r="(N|Y|Z|AB|AC|AK|AL|AM|T|AD)(\d+)"[^>]*>[\s\S]*?<\/c>/g, (cell, column, rowText) => {
    const row = Number(rowText);
    if (row < 6 || row > last || !/<f\b/.test(cell)) return cell;
    // All edited columns in a row share this calculation. Build it once per
    // row to leave enough Edge CPU for validating and compressing the workbook.
    if (row !== formulaRow) {
      formulas = {...receiptOrderFormulas(row, last, routeKey === 'kr_la_air' ? 'LKA' : 'LKS'), ...fixedDiscountFormulas(row)};
      if (separatedDiscounts) {
        const remark = formulas.T;
        formulas.T = `(${remark})&IF(AO${row}=0,"",IF((${remark})="",""," / ")&INDEX('Row data'!$AL:$AL,AO${row}))`;
      }
      formulaRow = row;
    }
    const formula = formulas[column];
    return cell.replace(/<f\b[^>]*?(?:\/>|>[\s\S]*?<\/f>)/, `<f>${escXml(formula)}</f>`);
  });
}

// A formula cell has at most one cached value, after <f> and before extensions.
// Excel commonly stores an empty cache as <v/>; appending after it corrupts cells.
function replaceFormulaCache(body: string, value: string): string {
  const withoutCache = body.replace(/<v\b[^>]*?\/>|<v\b[^>]*>[\s\S]*?<\/v>/g, '');
  return withoutCache.replace(/<\/f>|<f\b[^>]*\/>/, (formulaEnd) => `${formulaEnd}<v>${value}</v>`);
}

function updateCellPreservingFormula(
  rowXml: string,
  rowNumber: number,
  column: string,
  value: unknown,
  kind: 'text' | 'number' | 'date',
  cacheFormula = ['N','O','P'].includes(column),
): string {
  const ref = `${column}${rowNumber}`;
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
  const existing = rowXml.match(cellRe);

  // 원본 Excel의 수식 셀은 절대 지우거나 값 셀로 바꾸지 않습니다.
  if (existing) {
    const body = existing[3] ?? '';
    if (/<f\b/.test(body)) {
      if (!cacheFormula) return rowXml;
      const attrs = `${existing[1]}r="${ref}"${existing[2]}`.replace(/\s+t="[^"]*"/g, '');
      const nextBody = replaceFormulaCache(body, escXml(value ?? ''));
      return rowXml.replace(existing[0], () => `<c${attrs} t="str">${nextBody}</c>`);
    }
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
  return sheetXml.replace(rowXml, () => updated);
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
  // The approved originals contain old hard-coded statement adjustments.
  // Generated statements follow the same live source + adjustment as Row data.
  if (usesCurrencyLabels) {
    const workbook = strFromU8(files['xl/workbook.xml']);
    for (const match of workbook.matchAll(/<sheet\b[^>]*name="([^"]+)"[^>]*>/g)) {
      if (!/^(LKS|LKA)\s*(\d+|XX)$/i.test(match[1])) continue;
      const statementPath = workbookSheetPath(files, match[1]);
      if (!statementPath || !files[statementPath]) continue;
      let statement = strFromU8(files[statementPath]);
      const currencies = [[rates.baseKip,rates.kipAdjustment],[rates.baseThb,rates.thbAdjustment],[rates.baseKrw,rates.krwAdjustment]];
      currencies.forEach(([base,adjustment],index) => {
        const row = index + 2, sourceRow = index + 3;
        for (const [column,formula,value] of [
          ['U',`'Row data'!$C$${sourceRow}`,base],
          ['V',`'Row data'!$D$${sourceRow}`,adjustment],
          ['W',`U${row}+V${row}`,base+adjustment],
        ] as Array<[string,string,number]>) {
          const ref = `${column}${row}`;
          statement = setCachedFormulaValue(setFormulaCellInSheet(statement,ref,formula),ref,value,true);
        }
      });
      files[statementPath] = strToU8(statement);
    }
  }
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

  if (existing) return rowXml.replace(cellRe, () => replacement);

  // OOXML에서는 row 안의 <c> 셀이 열 순서대로 있어야 합니다.
  // 기존 템플릿 행이 A/B/O처럼 일부 셀만 가진 경우,
  // C~N을 row 끝에 단순 append하면 A,B,O,C,D... 순서가 되어
  // Excel이 "읽을 수 없는 내용"으로 판단하고 셀 정보를 복구/삭제합니다.
  const targetIndex = columnIndex(column);
  const cellMatches = [...rowXml.matchAll(
    /<c\b[^>]*r="([A-Z]+)\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
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
  routeKey = '',
): string {
  const headerRow = findHeaderRow(sheetXml, strings);
  if (headerRow < 0) {
    throw new Error('"물품 입고 내역" 헤더 행을 찾지 못했습니다.');
  }

  const firstDataRow = headerRow + 1;
  const formulaRows = ['kr_la_sea','kr_la_air'].includes(routeKey) && /<c\b[^>]*r="AK6"/.test(sheetXml)
    ? [...sheetXml.matchAll(/<c\b[^>]*r="AB(\d+)"/g)].map(m => Number(m[1])).filter(n => n >= 6)
    : [];
  const lastFormulaRow = formulaRows.length ? Math.max(...formulaRows) : 0;
  let nextSharedId = 1 + Math.max(-1,...[...sheetXml.matchAll(/<f\b[^>]*\bsi="(\d+)"/g)].map(m => Number(m[1])));
  const sharedColumns = new Map<string, number>();
  const shareGeneratedFormulas = (rowXml: string) => rowXml.replace(
    /<c\b[^>]*\br="(N|Y|Z|AB|AC|AK|AL|AM)(\d+)"[^>]*>[\s\S]*?<\/c>/g,
    (cell, column, rowText) => {
      const row = Number(rowText);
      if (row < 6 || row > lastFormulaRow) return cell;
      const f = cell.match(/<f\b[^>]*?(?:\/>|>([\s\S]*?)<\/f>)/);
      if (!f) return cell;
      let id = sharedColumns.get(column);
      let replacement: string;
      if (id == null) {
        id = nextSharedId++;
        sharedColumns.set(column,id);
        replacement = `<f t="shared" si="${id}" ref="${column}${row}:${column}${lastFormulaRow}">${f[1]}</f>`;
      } else replacement = `<f t="shared" si="${id}"/>`;
      return cell.replace(f[0],() => replacement);
    },
  );
  // Expand formulas only in the finished row, so the entire expanded cargo
  // worksheet is never retained alongside all of its edited intermediates.
  const finishRow = (rowXml: string) => {
    if (!lastFormulaRow) return rowXml;
    const rowNumber = Number(rowXml.match(/<row\b[^>]*\br="(\d+)"/)?.[1]);
    // These eight formulas are generated solely from relative row references.
    // Excel's native shared formulas retain identical calculations without
    // duplicating tens of MB of formula text in every exported worksheet.
    // Once all shared masters exist, follower rows only need their compact
    // references. Rebuilding the long formulas here wastes Edge CPU.
    if (sharedColumns.size < 8) rowXml = upgradeReceiptOrder(rowXml,routeKey,lastFormulaRow);
    rowXml = separateCargoRowDiscounts(rowXml,rowNumber);
    if (rowNumber >= 6 && rowNumber <= lastFormulaRow) {
      // Excel cannot share formulas containing cross-sheet references. Keep
      // T/AD as ordinary formulas; only the eight local-reference columns share.
      const fixed = fixedDiscountFormulas(rowNumber);
      const remark = fixed.T;
      fixed.T = `(${remark})&IF(AO${rowNumber}=0,"",IF((${remark})="",""," / ")&INDEX('Row data'!$AL:$AL,AO${rowNumber}))`;
      rowXml = rowXml.replace(/<c\b[^>]*\br="(T|AD)\d+"[^>]*>[\s\S]*?<\/c>/g,
        (cell, column) => cell.replace(/<f\b[^>]*?(?:\/>|>[\s\S]*?<\/f>)/, () => `<f>${escXml(fixed[column])}</f>`));
    }
    return shareGeneratedFormulas(rowXml);
  };

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

  // Split identifiers are distinct cargo but belong at their parent's numeric
  // position: S125, S126(01), S126(02), S127. Keep worksheet rows and formulas
  // in place; assign ordered labels AND their data to the existing cargo rows.
  const boxKey = (value: unknown) => String(value ?? '').trim().toUpperCase();
  const shipmentByBox = new Map<string, Record<string, unknown>>();
  for (const shipment of shipments) {
    const box = boxKey(shipment.box_number);
    if (!box) throw new Error('화물번호가 없는 자료가 있습니다. 화물번호를 확인해 주세요.');
    if (shipmentByBox.has(box)) throw new Error(`중복 화물번호가 있습니다: ${box}`);
    shipmentByBox.set(box, shipment);
  }

  const slots: Array<{row: number; box: string}> = [];
  const labels = new Map<string, string>();
  for (const match of sheetXml.matchAll(/<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g)) {
    const row = Number(match[1]);
    if (row < firstDataRow) continue;
    const boxCell = match[0].match(new RegExp(`<c\\b[^>]*r="B${row}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`));
    if (!boxCell) continue;
    const label = cellText(boxCell[0], strings).trim();
    const box = boxKey(label);
    // Totals/notes are not capacity. Fixed cargo IDs have a numeric component;
    // an exact DB match also supports route-specific literal identifiers.
    if (!box || (!shipmentByBox.has(box) && !/^[A-Z]*\d+(?:[^\p{L}\p{N}].*)?$/u.test(box))) continue;
    slots.push({row, box});
    labels.set(box, label);
  }
  if (shipments.length > slots.length) {
    throw new Error(`현재 템플릿의 화물 입력 행이 부족합니다. DB 화물 ${shipments.length}건 / 사용 가능한 행 ${slots.length}개. 화물 행이 충분한 원본 양식을 등록해 주세요.`);
  }
  for (const [box, shipment] of shipmentByBox) labels.set(box, String(shipment.box_number).trim());
  // If only split boxes exist, replace the empty parent placeholder with them.
  // When a real parent cargo also exists, retain it before its split boxes.
  for (const box of shipmentByBox.keys()) {
    const parent = box.match(/^([A-Z]*\d+)\s*\(\s*\d+\s*\)$/u)?.[1];
    if (parent && !shipmentByBox.has(parent)) labels.delete(parent);
  }
  const ordered = [...labels.keys()]
    .sort((a, b) => a.localeCompare(b, 'en', {numeric:true}) || (a < b ? -1 : a > b ? 1 : 0));
  // Retain ordinary unused-number gaps where possible. Make room for split
  // rows by dropping only unused placeholders, starting at the numeric tail.
  let placeholdersToDrop = Math.max(0, ordered.length - slots.length);
  const selected: string[] = [];
  for (let i = ordered.length - 1; i >= 0; i--) {
    const box = ordered[i];
    if (placeholdersToDrop > 0 && !shipmentByBox.has(box)) { placeholdersToDrop--; continue; }
    selected.push(box);
  }
  selected.reverse();
  const assignments = new Map(slots.map((slot, i) => [slot.row, selected[i]]));
  const slotByRow = new Map(slots.map(slot => [slot.row, slot]));
  const clearEditableInputs = (rowXml: string) => rowXml.replace(
    /<c\b[^>]*\br="((?:C|D|E|F|G|H|I|J|K|L|M|N|P|Q)\d+)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
    (cell, ref) => {
      if (/<f\b/.test(cell)) return cell;
      const style = cell.match(/\bs="([^"]+)"/)?.[1];
      return blankCell(ref, style ? ` s="${style}"` : '');
    },
  );
  const matchedBoxes = new Set<string>();
  const mappedColumns = new Map(mapping.filter(([column]) => column !== 'B')
    .map(([column, key, kind]) => [column, {key, kind}]));
  // 한 행을 바꿀 때마다 수 MB짜리 worksheet 전체를 다시 복사하면
  // 418행 기준으로 수 GB 규모의 임시 문자열 작업이 발생해 Edge CPU 한도를 넘습니다.
  // worksheet 전체는 한 번만 순회하고, callback 안에서 해당 행만 갱신합니다.
  const updateRow = (candidateXml: string, rowText: string) => {
      const rowNumber = Number(rowText);
      const slot = slotByRow.get(rowNumber);
      if (!slot) return finishRow(candidateXml);
      const normalizedBox = assignments.get(rowNumber);
      const sourceShipment = normalizedBox ? shipmentByBox.get(normalizedBox) : undefined;
      let rowXml = String(candidateXml);
      if (normalizedBox !== slot.box) {
        rowXml = updateCell(rowXml, rowNumber, 'B', normalizedBox ? labels.get(normalizedBox) : '', 'text');
        // A shifted cargo must not inherit a previous row's name, invoice,
        // dimensions or date when the corresponding DB field is empty.
        rowXml = clearEditableInputs(rowXml);
      }
      if (!sourceShipment) {
        return finishRow(clearEditableInputs(rowXml).replace(
          /<c\b[^>]*\br="([NOP])\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
          (cell, column) => updateCellPreservingFormula(cell,rowNumber,column,'','text'),
        ));
      }
      const manualNote = String(sourceShipment.notes ?? '').trim();
      const autoNote = String(sourceShipment.special_note_auto ?? '').trim();
      const shipment = {
        ...sourceShipment,
        notes: [manualNote, autoNote]
          .filter((v, i, a) => v && a.indexOf(v) === i)
          .join(' / '),
      };

      matchedBoxes.add(normalizedBox!);

      // Update each cell once. Replacing the full formula-heavy row for every
      // input column retains large intermediate strings in the Edge worker.
      const seen = new Set<string>();
      rowXml = rowXml.replace(
        /<c\b[^>]*\br="([A-Z]+)\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
        (cell, column) => {
          const entry = mappedColumns.get(column);
          if (!entry) return cell;
          seen.add(column);
          return updateCellPreservingFormula(cell,rowNumber,column,shipment[entry.key],entry.kind);
        },
      );
      // Sparse originals still need missing inputs inserted in column order.
      for (const [column, {key, kind}] of mappedColumns) {
        if (!seen.has(column)) rowXml = updateCellPreservingFormula(rowXml,rowNumber,column,shipment[key],kind);
      }

      return finishRow(rowXml);
    };
  // Iterate lazily instead of letting replace retain all callback arguments
  // and intermediate replacement strings for a large worksheet.
  const pieces: string[] = [];
  let cursor = 0;
  for (const match of sheetXml.matchAll(/<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g)) {
    pieces.push(sheetXml.slice(cursor,match.index),updateRow(match[0],match[1]));
    cursor = match.index! + match[0].length;
  }
  pieces.push(sheetXml.slice(cursor));
  const output = lastFormulaRow ? formatCargoDiscountColumns(pieces.join('')) : pieces.join('');

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

function insertWorksheetExtensionBlock(
  sheetXml: string,
  block: string,
  marker = '',
): string {
  if (marker && sheetXml.includes(marker)) return sheetXml;

  // ECMA-376 worksheet child order matters.  conditionalFormatting / dataValidations
  // must be placed after sheetData and before the later print/drawing/ext sections.
  const laterTags = [
    'dataValidations', 'hyperlinks', 'printOptions', 'pageMargins', 'pageSetup',
    'headerFooter', 'rowBreaks', 'colBreaks', 'customProperties', 'cellWatches',
    'ignoredErrors', 'smartTags', 'drawing', 'legacyDrawing', 'legacyDrawingHF',
    'picture', 'oleObjects', 'controls', 'webPublishItems', 'tableParts', 'extLst',
  ];
  let at = -1;
  for (const tag of laterTags) {
    const idx = sheetXml.indexOf(`<${tag}`);
    if (idx >= 0 && (at < 0 || idx < at)) at = idx;
  }
  if (at >= 0) return `${sheetXml.substring(0, at)}${block}${sheetXml.substring(at)}`;
  return sheetXml.replace('</worksheet>', `${block}</worksheet>`);
}

function applyDeliveryColorConditionalFormatting(
  files: Record<string, Uint8Array>,
  routeKey: string,
): void {
  if (routeKey !== 'kr_la_sea' && routeKey !== 'kr_la_air') return;
  const stylesPath = 'xl/styles.xml';
  if (!files[stylesPath]) return;

  let styles = strFromU8(files[stylesPath]);
  // Medium-light fills: black text remains readable, but the delivery area
  // is visually clear enough on screen/print.
  // Order: province / province-prepaid / city / city-prepaid.
  const fills = ['FFFFC000', 'FF9DC3E6', 'FFA9D18E', 'FFD6B18A'];

  // Excel templates can have either <dxfs count="0"/> or <dxfs ...>...</dxfs>.
  // Handle both forms and append valid differential fills.  A broken dxfId is what
  // makes Excel repair the workbook or render delivery cells as black.
  let baseDxf = 0;
  const fullDxfs = styles.match(/<dxfs\b([^>]*)count="(\d+)"([^>]*)>([\s\S]*?)<\/dxfs>/);
  const emptyDxfs = styles.match(/<dxfs\b([^>]*)count="(\d+)"([^>]*)\/>/);
  const extraDxfs = fills.map((rgb) =>
    `<dxf><fill><patternFill patternType="solid"><fgColor rgb="${rgb}"/><bgColor rgb="${rgb}"/></patternFill></fill></dxf>`
  ).join('');

  if (fullDxfs) {
    baseDxf = Number(fullDxfs[2] ?? 0);
    styles = styles.replace(
      fullDxfs[0],
      `<dxfs${fullDxfs[1]}count="${baseDxf + fills.length}"${fullDxfs[3]}>${fullDxfs[4]}${extraDxfs}</dxfs>`,
    );
  } else if (emptyDxfs) {
    baseDxf = Number(emptyDxfs[2] ?? 0);
    styles = styles.replace(
      emptyDxfs[0],
      `<dxfs${emptyDxfs[1]}count="${baseDxf + fills.length}"${emptyDxfs[3]}>${extraDxfs}</dxfs>`,
    );
  } else {
    // styles.xml schema order: dxfs comes before tableStyles/colors/extLst.
    const block = `<dxfs count="${fills.length}">${extraDxfs}</dxfs>`;
    const idx = styles.search(/<(tableStyles|colors|extLst)\b/);
    styles = idx >= 0
      ? `${styles.substring(0, idx)}${block}${styles.substring(idx)}`
      : styles.replace('</styleSheet>', `${block}</styleSheet>`);
    baseDxf = 0;
  }
  files[stylesPath] = strToU8(styles);

  const makeRules = (formulaFor: (label: string) => string, priorityBase: number) => [
    { label: '시내배송(선결제)', dxf: baseDxf + 3 },
    { label: '시내배송', dxf: baseDxf + 2 },
    { label: '지방배송(선결제)', dxf: baseDxf + 1 },
    { label: '지방배송', dxf: baseDxf + 0 },
  ].map((r, i) =>
    `<cfRule type="expression" dxfId="${r.dxf}" priority="${priorityBase + i + 1}" stopIfTrue="1"><formula>${escXml(formulaFor(r.label))}</formula></cfRule>`
  ).join('');

  const prefix = routeReceiptPrefix(routeKey).toUpperCase();
  const workbook = strFromU8(files['xl/workbook.xml']);
  const sheetNames = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )].map((m) => m[1]).filter((name) => name.toUpperCase().startsWith(prefix));

  for (const sheetName of sheetNames) {
    const sheetPath = workbookSheetPath(files, sheetName);
    if (!sheetPath || !files[sheetPath]) continue;
    let xml = strFromU8(files[sheetPath]);

    // V2 colored both Remark(left) and Delivery(center).
    // V3 correctly stopped coloring Remark, but it tried to detect the delivery
    // label from F18 itself. In the real template F18 is not the reliable source,
    // so the delivery color disappeared.
    //
    // V4 uses the already-correct Remark text A18 ONLY AS THE CONDITION SOURCE,
    // while applying fill ONLY to the middle Delivery area F:K.
    xml = xml.replace(
      /<!--LK_STATEMENT_DELIVERY_COLOR_V2--><conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,
      '',
    );
    xml = xml.replace(
      /<!--LK_STATEMENT_DELIVERY_COLOR_V3--><conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,
      '',
    );
    xml = xml.replace(
      /<!--LK_STATEMENT_DELIVERY_COLOR_V4--><conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,
      '',
    );
    if (xml.includes('LK_STATEMENT_DELIVERY_COLOR_V5')) {
      files[sheetPath] = strToU8(xml);
      continue;
    }

    const maxPriority = Math.max(0, ...[...xml.matchAll(/<cfRule\b[^>]*priority="(\d+)"/g)].map((m) => Number(m[1] ?? 0)));
    const rules = makeRules(
      (label) => `IFERROR(ISNUMBER(SEARCH("${label}",$A$18)),FALSE)`,
      maxPriority,
    );

    // Remark A:E = NEVER colored.
    // Delivery F:K = colored from the delivery keyword already present in Remark.
    const block = `<!--LK_STATEMENT_DELIVERY_COLOR_V5--><conditionalFormatting sqref="F18:K24">${rules}</conditionalFormatting>`;
    xml = insertWorksheetExtensionBlock(xml, block, 'LK_STATEMENT_DELIVERY_COLOR_V5');
    files[sheetPath] = strToU8(xml);
  }

  const customerPath = workbookSheetPath(files, '고객 리스트');
  if (customerPath && files[customerPath]) {
    let xml = strFromU8(files[customerPath]);
    xml = xml.replace(
      /<!--LK_CUSTOMER_LIST_DELIVERY_COLOR_V2--><conditionalFormatting\b[^>]*>[\s\S]*?<\/conditionalFormatting>/g,
      '',
    );
    if (!xml.includes('LK_CUSTOMER_LIST_DELIVERY_COLOR_V3')) {
      const maxPriority = Math.max(0, ...[...xml.matchAll(/<cfRule\b[^>]*priority="(\d+)"/g)].map((m) => Number(m[1] ?? 0)));
      const rules = makeRules((label) => `$E4="${label}"`, maxPriority);
      const block = `<!--LK_CUSTOMER_LIST_DELIVERY_COLOR_V3--><conditionalFormatting sqref="E4:E150">${rules}</conditionalFormatting>`;
      xml = insertWorksheetExtensionBlock(xml, block, 'LK_CUSTOMER_LIST_DELIVERY_COLOR_V3');
      files[customerPath] = strToU8(xml);
    }
  }
}

function normalizePhone(value: unknown): string {
  return String(value ?? '').replace(/[^0-9]/g, '');
}

function normalizeReceiptName(value: unknown): string {
  return String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function firstReceiptNameToken(value: unknown): string {
  return normalizeReceiptName(String(value ?? '').split('/')[0]);
}

function receiptNameTokenIsUncertain(value: unknown): boolean {
  const first = firstReceiptNameToken(value);
  return first === '' || /[*?#＊？]/u.test(first) ||
    /^(수취인\s*불명|수신인\s*불명|불확실한\s*물품|불확실|미확인|기호포함\s*이름|unknown|unidentified|n\/a|na|none)/iu.test(first);
}

function receiptPhoneIsUncertain(value: unknown): boolean {
  const raw = String(value ?? '');
  return raw.trim() === '' || /[*?＊？]/u.test(raw) || normalizePhone(raw).length < 7;
}

function receiptIsTrulyUnknown(name: unknown, phone: unknown): boolean {
  return String(name ?? '').trim() !== ''
    ? receiptNameTokenIsUncertain(name)
    : receiptPhoneIsUncertain(phone);
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
  return sheetXml.replace(rowXml, () => updated);
}

function upgradeZoneQuantityFormulas(
  files: Record<string, Uint8Array>,
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);

  // PATCH200C: one-pass rewrite. The old implementation rescanned/copied the whole
  // worksheet up to 111 times and could exceed the Edge CPU budget.
  xml = xml.replace(
    /<c\b([^>]*)r="F(\d+)"([^>]*)>([\s\S]*?)<\/c>/g,
    (full, before, rowText, after, body) => {
      const row = Number(rowText);
      if (row < 4 || row > 114 || !/<f\b/.test(String(body))) return full;
      const formula =
        `SUMIF('물품 입고 내역'!$N$6:$N$1005,$A${row},'물품 입고 내역'!$I$6:$I$1005)`;
      const nextBody = String(body).replace(
        /<f\b[^>]*?(?:\/>|>[\s\S]*?<\/f>)/,
        `<f>${formula}</f>`,
      );
      return `<c${before}r="F${row}"${after}>${nextBody}</c>`;
    },
  );

  files[path] = strToU8(xml);
}

function setFormulaCellInRowFast(
  rowXml: string,
  rowNumber: number,
  column: string,
  formula: string,
): string {
  const ref = `${column}${rowNumber}`;
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`,
  );
  const existing = rowXml.match(cellRe);
  const attrs = existing ? `${existing[1] ?? ''}${existing[2] ?? ''}` : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';
  const replacement = `<c r="${ref}"${style}><f>${escXml(formula)}</f></c>`;

  if (existing) return rowXml.replace(cellRe, () => replacement);

  const targetIndex = columnIndex(column);
  const cells = [...rowXml.matchAll(
    /<c\b[^>]*r="([A-Z]+)\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
  )];
  for (const match of cells) {
    if (columnIndex(match[1]) > targetIndex && match.index != null) {
      return `${rowXml.substring(0, match.index)}${replacement}${rowXml.substring(match.index)}`;
    }
  }
  return rowXml.replace('</row>', `${replacement}</row>`);
}

function setFormulaCellPreservingStyle(
  sheetXml: string,
  ref: string,
  formula: string,
): string {
  const rowNumber = Number(ref.match(/\d+$/)?.[0] ?? 0);
  const column = ref.match(/^[A-Z]+/)?.[0] ?? '';
  if (!rowNumber || !column) return sheetXml;
  const rowRe = new RegExp(`<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`);
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;
  const rowXml = rowMatch[0];
  const cellRe = new RegExp(`<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`);
  const existing = rowXml.match(cellRe);
  const attrs = existing ? `${existing[1] ?? ''}${existing[2] ?? ''}` : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';
  const replacement = `<c r="${ref}"${style}><f>${escXml(formula)}</f></c>`;
  let nextRow = rowXml;
  if (existing) {
    nextRow = rowXml.replace(cellRe, () => replacement);
  } else {
    const targetIndex = columnIndex(column);
    const cells = [...rowXml.matchAll(/<c\b[^>]*r="([A-Z]+)\d+"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)];
    let inserted = false;
    for (const m of cells) {
      if (columnIndex(m[1]) > targetIndex && m.index != null) {
        nextRow = `${rowXml.substring(0, m.index)}${replacement}${rowXml.substring(m.index)}`;
        inserted = true;
        break;
      }
    }
    if (!inserted) nextRow = rowXml.replace('</row>', `${replacement}</row>`);
  }
  return sheetXml.replace(rowXml, () => nextRow);
}

function seedCustomerListFromShipments(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  routeKey: string,
  voyage: string,
): void {
  const path = workbookSheetPath(files, '고객 리스트');
  if (!path || !files[path]) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  const prefix = routeReceiptPrefix(routeKey);
  const voyageNumber = String(voyage)
    .replace(/^V/i, '')
    .replace(/항차$/u, '')
    .trim();

  if (routeKey === 'kr_la_sea') {
    xml = setStringCellInSheet(
      xml,
      'A1',
      `Kor-Lao Sea ${voyageNumber}항차 고객 리스트 (ລາຍການລູກຄ້າຂອງທາງເຮືອ)`,
    );
  }

  const groups = new Map<string, Record<string, unknown>[]>();
  for (const shipment of shipments) {
    const receipt = String(shipment.receipt_number ?? '').trim();
    if (!receipt) continue;
    const key = receipt.toUpperCase();
    const list = groups.get(key) ?? [];
    list.push(shipment);
    groups.set(key, list);
  }

  const compactName = (value: unknown) =>
    String(value ?? '').replace(/[\s/,_()\-]+/g, '').toLowerCase();
  const fixed102Names = [
    '박성호','정석진','이동현','정민주','박상욱',
    '박상용','임홍식','진정우','최현석',
  ];

  const rowRe = /<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g;
  xml = xml.replace(rowRe, (rowXml, rowText) => {
    const rowNumber = Number(rowText);
    if (rowNumber < 4 || rowNumber > 150) return rowXml;

    const aRe = new RegExp(
      `<c\\b[^>]*r="A${rowNumber}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`,
    );
    const aMatch = String(rowXml).match(aRe);
    if (!aMatch) return rowXml;

    let receipt = cellText(aMatch[0], strings).trim();
    let nextRow = String(rowXml);

    if (/\bxx\s*$/i.test(receipt) && prefix) {
      receipt = `${prefix} XX`;
      nextRow = updateCell(nextRow, rowNumber, 'A', receipt, 'text');
    }
    if (!receipt) return nextRow;

    const rows = groups.get(receipt.toUpperCase());
    if (!rows?.length) {
      // Even empty/unused normal receipt slots keep their BASE Zone formula.
      if (!/\bxx\s*$/i.test(receipt)) {
        nextRow = setFormulaCellInRowFast(
          nextRow,
          rowNumber,
          'C',
          `IF(B${rowNumber}="","",IF(F${rowNumber}<=4,"A",IF(F${rowNumber}<=9,"B",IF(F${rowNumber}<=19,"C","F"))))`,
        );
      }
      return nextRow;
    }

    const first = rows[0];
    const name = String(first.consignee_name ?? '').trim();
    if (name) nextRow = updateCell(nextRow, rowNumber, 'B', name, 'text');

    const note = [...new Set(
      rows
        .map((x) => String(x.special_note_auto ?? '').trim())
        .filter(Boolean),
    )].join(' / ');
    const normalizedName = compactName(name);
    const isDeliveryF = note.includes('지방배송') || note.includes('시내배송');
    const isNamedF =
      normalizedName.startsWith('김요셉') ||
      normalizedName.startsWith('뷰티판다');
    const isFixed102 = fixed102Names.some(
      (fixed) => normalizedName.startsWith(compactName(fixed)),
    );

    if (/\bxx\s*$/i.test(receipt)) {
      nextRow = updateCell(nextRow, rowNumber, 'C', 'F', 'text');
    } else if (isFixed102) {
      nextRow = updateCell(nextRow, rowNumber, 'C', '102', 'text');
    } else if (isDeliveryF || isNamedF) {
      nextRow = updateCell(nextRow, rowNumber, 'C', 'F', 'text');
    } else {
      nextRow = setFormulaCellInRowFast(
        nextRow,
        rowNumber,
        'C',
        `IF(B${rowNumber}="","",IF(F${rowNumber}<=4,"A",IF(F${rowNumber}<=9,"B",IF(F${rowNumber}<=19,"C","F"))))`,
      );
    }

    let signature = '';
    if (note.includes('지방배송(선결제)')) {
      signature = '지방배송(선결제)';
    } else if (note.includes('시내배송(선결제)')) {
      signature = '시내배송(선결제)';
    } else if (note.includes('지방배송')) {
      signature = '지방배송';
    } else if (note.includes('시내배송')) {
      signature = '시내배송';
    }
    if (signature) {
      // E may be the master of a shared formula group. Keep its formula and
      // group metadata so subsequent customer rows never become orphaned.
      nextRow = updateCellPreservingFormula(nextRow, rowNumber, 'E', signature, 'text', true);
    }

    return nextRow;
  });

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

  const newBody = replaceFormulaCache(body, numeric ? String(Number(value)) : escXml(value));
  const attrs = `${match[1]}r="${ref}"${match[2]}`.replace(/\s+t="[^"]*"/g, '');
  return sheetXml.replace(match[0], () => `<c${attrs}${numeric ? '' : ' t="str"'}>${newBody}</c>`);
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
    'showInputMessage="1" promptTitle="영수증 번호 선택" ' +
    'prompt="여기를 눌러 LKS 번호를 선택하세요." sqref="N2">' +
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

  // LK_PATCH200_FULLCALC: force Excel to recalculate linked totals/formulas on first open.
  const workbookPath = 'xl/workbook.xml';
  if (files[workbookPath]) {
    let workbookXml = strFromU8(files[workbookPath]);
    if (/<calcPr\b/.test(workbookXml)) {
      workbookXml = workbookXml.replace(/<calcPr\b([^>]*)\/?>(?:<\/calcPr>)?/, (m, attrs) => {
        const clean = String(attrs ?? '')
          .replace(/\sfullCalcOnLoad="[^"]*"/g, '')
          .replace(/\sforceFullCalc="[^"]*"/g, '')
          .replace(/\scalcMode="[^"]*"/g, '');
        return `<calcPr${clean} calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>`;
      });
    } else {
      workbookXml = workbookXml.replace('</workbook>', '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>');
    }
    files[workbookPath] = strToU8(workbookXml);
  }
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
        /<c\b[^>]*r="([A-Z]+\d+)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
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
function appendDocumentAutomationBlock(
  files: Record<string, Uint8Array>,
  shipments: Record<string, unknown>[],
  deliveries: Record<string, unknown>[],
  extraCosts: Record<string, unknown>[],
  settlement: Record<string, unknown> | null,
): void {
  const path = workbookSheetPath(files, 'Row data');
  if (!path || !files[path]) return;
  let xml = strFromU8(files[path]);
  const close = xml.lastIndexOf('</sheetData>');
  if (close < 0) return;

  const normalizeName = (v: unknown) => String(v ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
  const phoneMatch = (a: unknown, b: unknown) => {
    const aa = normalizePhone(a); const bb = normalizePhone(b);
    return !!aa && !!bb && (
      aa === bb ||
      (aa.length >= 8 && bb.length >= 8 && aa.slice(-8) === bb.slice(-8)) ||
      (aa.length >= 8 && bb.includes(aa)) ||
      (bb.length >= 8 && aa.includes(bb))
    );
  };
  const groups = new Map<string, Record<string, unknown>[]>();
  for (const s of shipments) {
    const receipt = String(s.receipt_number ?? '').trim();
    if (!receipt) continue;
    const list = groups.get(receipt) ?? []; list.push(s); groups.set(receipt, list);
  }
  const receiptAmounts = new Map<string, number>();
  const receiptDiscountRates = new Map<string, number>();
  const rawReceipts = Array.isArray(settlement?.receipts) ? settlement!.receipts as Record<string, unknown>[] : [];
  for (const r of rawReceipts) {
    const receipt = String(r.receipt_number ?? '').trim();
    const gross = Number(r.gross_usd ?? 0);
    const discount = Number(r.discount_usd ?? 0);
    receiptAmounts.set(receipt, Number(r.net_usd ?? 0));
    receiptDiscountRates.set(
      receipt,
      gross > 0 ? Math.max(0, Math.min(1, discount / gross)) : 0,
    );
  }
  const extraMap = new Map<string, number>();
  const discountedExtraMap = new Map<string, number>();
  for (const e of extraCosts) {
    const receipt = String(e.receipt_number ?? '').trim();
    const amount = Number(e.amount_usd ?? 0);
    extraMap.set(receipt, (extraMap.get(receipt) ?? 0) + amount);
    if (e.discount_applies === true) {
      discountedExtraMap.set(
        receipt,
        (discountedExtraMap.get(receipt) ?? 0) + amount,
      );
    }
  }

  const existingRows = [...xml.matchAll(/<row\b[^>]*r="(\d+)"/g)].map(m => Number(m[1]));
  let row = (existingRows.length ? Math.max(...existingRows) : 0) + 2;
  const out: string[] = [];
  const add = (vals: Array<string | number>) => {
    const cols = ['X','Y','Z','AA','AB','AC','AD','AE'];
    const cells = vals.map((v,i) => typeof v === 'number' ? numericCell(`${cols[i]}${row}`,'',v) : inlineCell(`${cols[i]}${row}`,'',v)).join('');
    out.push(`<row r="${row}">${cells}</row>`); row++;
  };
  add(['DOCUMENT AUTOMATION','Customer','Phone','Remark Auto','Inland / Delivery','Delivery Type','Extra USD','Amount USD']);
  for (const [receipt, rows] of groups) {
    const first = rows[0];
    const name = String(first.consignee_name ?? '').trim();
    const phone = String(first.consignee_phone ?? '').trim();
    const isPrepaid = (value: unknown) => {
      const key = String(value ?? '').toLowerCase().replace(/[\s_-]+/g, '');
      return ['선결제','선결재','선불','prepaid','payinadvance'].some(token => key.includes(token));
    };
    const d = deliveries.find(x => String(x.id) === String(first.automation_delivery_profile_id));
    const prepaid = d ? isPrepaid(d.paid_by) : false;
    const type = d
      ? (String(d.delivery_type ?? '') === 'city'
        ? (prepaid ? 'city_prepaid' : 'city')
        : (prepaid ? 'province_prepaid' : 'province'))
      : '';
    const rawSourceNo = Number(d?.source_no ?? 0);
    const displaySourceNo = Number(d?.original_source_no ?? (rawSourceNo >= 10000 ? rawSourceNo - 10000 : rawSourceNo));
    const delivery = d ? [
      displaySourceNo > 0 ? `No. ${displaySourceNo}` : '',
      d.alternate_name || d.customer_name || name,
      d.phone_display || d.phone || phone,
      d.local_company,
      d.destination_address,
    ].filter(Boolean).join('\n') : '';
    const auto = [...new Set(rows.map(x => String(x.special_note_auto ?? '').trim()).filter(Boolean))].join(' / ');
    const extra = extraMap.get(receipt) ?? 0;
    const discountRate = receiptDiscountRates.get(receipt) ?? 0;
    const extraDiscount =
      (discountedExtraMap.get(receipt) ?? 0) * discountRate;
    add([
      receipt,
      name,
      phone,
      auto,
      delivery,
      type,
      extra,
      (receiptAmounts.get(receipt) ?? 0) + extra - extraDiscount,
    ]);
  }
  xml = `${xml.substring(0, close)}${out.join('')}${xml.substring(close)}`;
  files[path] = strToU8(xml);
}

function populateDeliveryCostInputSheet(
  files: Record<string, Uint8Array>,
  extraCosts: Record<string, unknown>[],
): void {
  const path = workbookSheetPath(files, '기타 비용 추가 입력') || workbookSheetPath(files, '배송비 입력');
  if (!path || !files[path] || extraCosts.length === 0) return;

  const costs: Array<{
    receipt: string;
    name: string;
    amount: number;
    discounted: boolean;
  }> = [];
  for (const item of extraCosts) {
    const receipt = String(item.receipt_number ?? '').trim();
    const amount = Number(item.amount_usd ?? 0);
    if (!receipt || !Number.isFinite(amount) || amount < 0) continue;
    costs.push({
      receipt,
      name: String(item.cost_name ?? '').trim() || '배송비',
      amount,
      discounted: item.discount_applies === true,
    });
  }
  if (costs.length === 0) return;

  let xml = strFromU8(files[path]);
  const strings = sharedStrings(files);
  const receiptRows = new Map<string, number>();
  const overflowRows: number[] = [];
  for (const match of xml.matchAll(
    /<c\b[^>]*r="A(\d+)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g,
  )) {
    const row = Number(match[1]);
    if (row < 5 || row > 405) continue;
    const receipt = cellText(match[0], strings).trim();
    if (row <= 205 && receipt) receiptRows.set(receipt, row);
    if (row >= 206 && !receipt) overflowRows.push(row);
  }

  const usedReceiptRows = new Set<string>();
  let overflowIndex = 0;
  for (const cost of costs) {
    let row: number | undefined;
    if (!usedReceiptRows.has(cost.receipt)) {
      row = receiptRows.get(cost.receipt);
      if (row) usedReceiptRows.add(cost.receipt);
    }
    if (!row) {
      row = overflowRows[overflowIndex++];
      if (!row) {
        throw new Error(
          '기타 비용 추가 입력 시트의 추가 비용 행이 부족합니다. BASE의 입력 범위를 확인해 주세요.',
        );
      }
      xml = setStringCellInSheet(xml, `A${row}`, cost.receipt);
    }
    xml = setStringCellInSheet(xml, `C${row}`, cost.name);
    xml = setNumericCellInSheet(xml, `D${row}`, cost.amount);
    xml = setStringCellInSheet(
      xml,
      `E${row}`,
      cost.discounted ? '적용' : '미적용',
    );
  }
  files[path] = strToU8(xml);
}

function setFormulaCellInSheet(sheetXml: string, ref: string, formula: string): string {
  const rowNumber = Number(ref.match(/\d+$/)?.[0] ?? 0);
  const column = ref.match(/^[A-Z]+/)?.[0] ?? '';
  if (!rowNumber || !column) return sheetXml;
  const rowRe = new RegExp(`<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`);
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;
  const rowXml = rowMatch[0];
  const cellRe = new RegExp(`<c\\b([^>]*)r="${ref}"([^>]*?)(?:\\/>|>([\\s\\S]*?)<\\/c>)`);
  const existing = rowXml.match(cellRe);
  const attrs = existing ? `${existing[1] ?? ''}${existing[2] ?? ''}` : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';
  const replacement = `<c r="${ref}"${style}><f>${escXml(formula)}</f><v></v></c>`;
  // IMPORTANT: replacement contains Excel formulas such as $N$2.
  // JavaScript String.replace(re, "text with $2") treats $2 as regex capture group,
  // which corrupted exported formulas (e.g. $N s="246") and made Excel repair the file.
  // Always use a callback so '$' is written literally.
  if (existing) {
    const updatedRow = rowXml.replace(cellRe, () => replacement);
    return sheetXml.replace(rowXml, updatedRow);
  }

  const seeded = updateCell(rowXml, rowNumber, column, '', 'text');
  const targetRe = new RegExp(
    `<c\\b[^>]*r="${ref}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`,
  );
  const updatedRow = seeded.replace(targetRe, () => replacement);
  return sheetXml.replace(rowXml, updatedRow);
}

function withWrapTextXf(xfXml: string): string {
  const setApplyAlignment = (openTag: string): string => {
    if (/\bapplyAlignment="/.test(openTag)) {
      return openTag.replace(/\bapplyAlignment="[^"]*"/, 'applyAlignment="1"');
    }
    return openTag.replace(/>$/, ' applyAlignment="1">');
  };

  const setWrap = (alignmentTag: string): string => {
    if (/\bwrapText="/.test(alignmentTag)) {
      return alignmentTag.replace(/\bwrapText="[^"]*"/, 'wrapText="1"');
    }
    if (/\/>$/.test(alignmentTag)) {
      return alignmentTag.replace(/\/>$/, ' wrapText="1"/>');
    }
    return alignmentTag.replace(/>$/, ' wrapText="1">');
  };

  if (/^<xf\b[^>]*\/>$/.test(xfXml)) {
    const open = xfXml.replace(/\/>$/, '>');
    const fixedOpen = setApplyAlignment(open);
    return `${fixedOpen}<alignment wrapText="1"/></xf>`;
  }

  let out = xfXml;
  const openMatch = out.match(/^<xf\b[^>]*>/);
  if (openMatch) {
    out = `${setApplyAlignment(openMatch[0])}${out.substring(openMatch[0].length)}`;
  }

  const alignmentSelf = out.match(/<alignment\b[^>]*\/>/);
  if (alignmentSelf) {
    return out.replace(alignmentSelf[0], setWrap(alignmentSelf[0]));
  }

  const alignmentOpen = out.match(/<alignment\b[^>]*>/);
  if (alignmentOpen) {
    return out.replace(alignmentOpen[0], setWrap(alignmentOpen[0]));
  }

  return out.replace('</xf>', '<alignment wrapText="1"/></xf>');
}

function applyStatementWrapText(
  files: Record<string, Uint8Array>,
  routeKey: string,
): void {
  const prefix = routeReceiptPrefix(routeKey);
  if (!prefix) return;

  const stylesPath = 'xl/styles.xml';
  if (!files[stylesPath]) return;

  let styles = strFromU8(files[stylesPath]);
  const cellXfsMatch = styles.match(
    /<cellXfs\b([^>]*)count="(\d+)"([^>]*)>([\s\S]*?)<\/cellXfs>/,
  );
  if (!cellXfsMatch) return;

  const xfList = [...cellXfsMatch[4].matchAll(
    /<xf\b[^>]*?(?:\/>|>[\s\S]*?<\/xf>)/g,
  )].map(m => m[0]);
  if (xfList.length === 0) return;

  const workbook = strFromU8(files['xl/workbook.xml']);
  const prefixUpper = prefix.toUpperCase();
  const sheetNames = [...workbook.matchAll(
    /<sheet\b[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )]
    .map(m => m[1])
    .filter(name => name.toUpperCase().startsWith(prefixUpper));

  const wrapStyleMap = new Map<number, number>();
  const appendedXfs: string[] = [];

  const wrappedStyleFor = (styleIndex: number): number => {
    const safeIndex =
      styleIndex >= 0 && styleIndex < xfList.length ? styleIndex : 0;
    const cached = wrapStyleMap.get(safeIndex);
    if (cached != null) return cached;

    const newIndex = xfList.length + appendedXfs.length;
    appendedXfs.push(withWrapTextXf(xfList[safeIndex]));
    wrapStyleMap.set(safeIndex, newIndex);
    return newIndex;
  };

  for (const sheetName of sheetNames) {
    const path = workbookSheetPath(files, sheetName);
    if (!path || !files[path]) continue;

    let xml = strFromU8(files[path]);

    // Remark A:E and Delivery F:K display area.
    // Preserve existing fills/fonts/borders/alignment; clone only to add wrapText.
    xml = xml.replace(
      /<c\b([^>]*)r="([A-K])(1[89]|2[0-4])"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g,
      (full, before, column, rowText, after, body) => {
        const attrs = `${before ?? ''}${after ?? ''}`;
        const styleMatch = attrs.match(/\bs="(\d+)"/);
        const oldStyle = Number(styleMatch?.[1] ?? 0);
        const newStyle = wrappedStyleFor(oldStyle);

        let newAttrs = attrs;
        if (styleMatch) {
          newAttrs = newAttrs.replace(/\bs="\d+"/, ` s="${newStyle}"`);
        } else {
          newAttrs = `${newAttrs} s="${newStyle}"`;
        }

        const cleanAttrs = newAttrs.trim();
        const attrPrefix = cleanAttrs ? ` ${cleanAttrs}` : '';

        if (body == null) {
          return `<c${attrPrefix} r="${column}${rowText}"/>`;
        }
        return `<c${attrPrefix} r="${column}${rowText}">${body}</c>`;
      },
    );

    files[path] = strToU8(xml);
  }

  if (appendedXfs.length === 0) return;

  const nextBody = `${cellXfsMatch[4]}${appendedXfs.join('')}`;
  styles = styles.replace(
    cellXfsMatch[0],
    `<cellXfs${cellXfsMatch[1]}count="${xfList.length + appendedXfs.length}"${cellXfsMatch[3]}>${nextBody}</cellXfs>`,
  );
  files[stylesPath] = strToU8(styles);
}

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
    '<c\\b[^>]*?r="([A-Z]+\\d+)"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)',
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

  // N2:N3 and L4:N4 are merged areas in the real SEA template.
  // Writing helper formulas into N3/N4 caused Excel to repair/remove records.
  // The visible Remark/Inland target formulas above are sufficient.
  // N5 helper is also intentionally omitted to keep the original template untouched.
  void deliveryTypeFormula;
  files[path] = strToU8(xml);
}

// Link the existing account text box to the statement's own Remark. Using a
// cell link keeps the printed account current when N2 or BASE rules change.
function wireStatementVatFormulas(files: Record<string, Uint8Array>, routeKey: string): void {
  if (!['kr_la_sea','kr_la_air'].includes(routeKey)) return;
  const strings = sharedStrings(files);
  const workbook = strFromU8(files['xl/workbook.xml']);
  for (const match of workbook.matchAll(/<sheet\b[^>]*name="([^"]+)"/g)) {
    const name = decodeXmlText(match[1]);
    if (!/^(LKS|LKA)\s/.test(name) && name !== '명세서 빠르게 확인') continue;
    const path = workbookSheetPath(files,name);
    if (!path || !files[path]) continue;
    let xml = strFromU8(files[path]);
    for (const cell of xml.matchAll(/<c\b[^>]*\br="L(\d+)"[^>]*>[\s\S]*?<\/c>/g)) {
      if (!cellText(cell[0],strings).includes('VAT')) continue;
      const ref = `M${cell[1]}`;
      const old = xml.match(new RegExp(`<c\\b[^>]*\\br="${ref}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0] || '';
      const formula = decodeXmlText(old.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1] || '');
      const remarkRef = formula.match(/\$?A\$?\d+/)?.[0];
      if (!remarkRef) throw new Error(`VAT Remark reference missing: ${name}!${ref}`);
      const remarkCell = xml.match(new RegExp(`<c\\b[^>]*\\br="${remarkRef.replaceAll('$','')}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0] || '';
      const context = documentVatContext(routeKey,cellText(remarkCell,strings));
      xml = setFormulaCellInSheet(xml,ref,documentVatFormula(remarkRef));
      xml = setCachedFormulaValue(xml,ref,context.taxInvoice?context.rate:' ',context.taxInvoice);
    }
    files[path] = strToU8(xml);
  }
}

function wireStatementPaymentAccounts(files: Record<string, Uint8Array>): void {
  const workbook = strFromU8(files['xl/workbook.xml']);
  const names = [...workbook.matchAll(/<sheet\b[^>]*name="([^"]+)"/g)].map(m => decodeXmlText(m[1]));
  const strings = sharedStrings(files);
  const compact = (s: string) => s.replace(/\s/g, '');
  const normal = '571-22-0330221', business = '2070133424601';
  const formula = '"한국 원화 계좌:"&CHAR(10)&"경남은행"&CHAR(10)&IF(ISNUMBER(SEARCH("세금계산서",SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(SUBSTITUTE(A18," ",""),CHAR(9),""),CHAR(10),""),CHAR(13),""),CHAR(160),""))),"2070133424601"&CHAR(10)&"박성호(엘케이무역)","571-22-0330221"&CHAR(10)&"박성호")';
  for (const name of names) {
    if (!/^(LKS|LKA)\s/.test(name) && name !== '명세서 빠르게 확인') continue;
    const path = workbookSheetPath(files, name);
    if (!path || !files[path]) continue;
    let xml = strFromU8(files[path]);
    const drawingId = xml.match(/<drawing\b[^>]*r:id="([^"]+)"/)?.[1];
    const relPath = path.replace(/([^/]+)$/, '_rels/$1.rels');
    if (!drawingId || !files[relPath]) continue;
    const rel = [...strFromU8(files[relPath]).matchAll(/<Relationship\b[^>]*\/>/g)]
      .map(m => m[0]).find(tag => tag.match(/\bId="([^"]+)"/)?.[1] === drawingId);
    const target = rel?.match(/\bTarget="([^"]+)"/)?.[1];
    if (!target) continue;
    const drawingPath = target.startsWith('/') ? target.slice(1) : 'xl/' + target.replace(/^\.\.\//, '');
    if (!files[drawingPath]) continue;
    const remarkCell = xml.match(/<c\b[^>]*\br="A18"[^>]*>[\s\S]*?<\/c>/)?.[0] || '';
    const tax = compact(cellText(remarkCell, strings)).includes('세금계산서');
    const account = tax ? business : normal, holder = tax ? '박성호(엘케이무역)' : '박성호';
    const textlink = escXml(`'${name.replaceAll("'", "''")}'!$W$14`);
    let linked = false;
    const drawing = strFromU8(files[drawingPath]).replace(/<xdr:sp\b[^>]*>[\s\S]*?<\/xdr:sp>/g, shape => {
      if (!shape.includes(normal) && !shape.includes(business)) return shape;
      linked = true;
      shape = shape.replace(/<xdr:sp\b[^>]*>/, tag => /\btextlink="/.test(tag)
        ? tag.replace(/\btextlink="[^"]*"/, () => `textlink="${textlink}"`)
        : tag.replace(/>$/, () => ` textlink="${textlink}">`));
      return shape.replace(/(<a:t>)(571-22-0330221|2070133424601)(<\/a:t>)/g, (_, a, _v, b) => a + account + b)
        .replace(/(<a:t>)박성호(?:\(엘케이무역\))?(<\/a:t>)/g, (_, a, b) => a + holder + b);
    });
    if (!linked) continue;
    xml = setFormulaCellInSheet(xml, 'W14', formula);
    xml = setCachedFormulaValue(xml, 'W14', `한국 원화 계좌:\n경남은행\n${account}\n${holder}`, false);
    files[path] = strToU8(xml);
    files[drawingPath] = strToU8(drawing);
  }
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

    const { data: baseTemplate, error: baseTemplateError } = await admin
      .from('shipment_excel_base_templates')
      .select('route_key,route_label,file_name,storage_path,prefer_for_export')
      .eq('route_key', routeKey).eq('active', true).maybeSingle();
    if (baseTemplateError) throw baseTemplateError;
    const useBase = baseTemplate && (!voyageTemplate || baseTemplate.prefer_for_export);
    const template = useBase ? {...baseTemplate,shipment_year:shipmentYear,voyage} : voyageTemplate;
    const templateSource = useBase ? 'base' : 'voyage';
    if (!template) return json(404,{error:'해당 운송 경로의 기본 Excel 폼과 항차별 변경 폼이 모두 없습니다.'});

    let templateBlob: Blob;
    if (String(template.storage_path).startsWith('database://')) {
      const sourceHash = String(template.storage_path).slice(11);
      if (!/^[0-9a-f]{64}$/.test(sourceHash)) throw new Error('잘못된 기준 원본 식별자');
      const {data:source,error:sourceError} = await admin.from('shipment_excel_source_files')
        .select('content_base64,byte_size').eq('sha256',sourceHash).single();
      if(sourceError || !source) throw sourceError ?? new Error('기준 원본을 찾을 수 없습니다.');
      const bytes=Uint8Array.from(atob(source.content_base64),c=>c.charCodeAt(0));
      const actualHash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))]
        .map(v=>v.toString(16).padStart(2,'0')).join('');
      if(bytes.length!==source.byte_size||actualHash!==sourceHash)throw new Error('기준 원본 무결성 확인 실패');
      templateBlob=new Blob([bytes]);
    } else {
      const {data,error}=await admin.storage.from('shipment-excel-templates').download(template.storage_path);
      if(error||!data)throw error??new Error('원본 템플릿 다운로드 실패');
      templateBlob=data;
    }

    const shipmentRouteLabel =
      requestedRouteLabel ||
      String(routeDefinition?.display_name ?? '').trim() ||
      String(template.route_label ?? '').trim();
    const { data: shipments, error: shipmentError } = await admin
      .from('shipments')
      .select(
        'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,recipient_unknown,notes,special_note_auto,received_at,created_at',
      )
      .eq('route', shipmentRouteLabel)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .is('deleted_at', null)
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

    // Receipt numbers are assigned only by the common database automation.
    // Export never performs an independent allocation or writes shipment rows.
    const enrichedShipments = exportShipmentRows;
    if (enrichedShipments.some(row => !String(row.receipt_number ?? '').trim())) {
      throw new Error('명세서 번호 정리가 필요합니다. 항차 자료를 새로고침한 뒤 다시 다운로드하세요.');
    }

    const customerSet = [...new Map(enrichedShipments.map(row => [
      JSON.stringify([row.consignee_name || '', row.consignee_phone || '']),
      {name: row.consignee_name || '', phone: row.consignee_phone || ''},
    ])).values()];
    const {data: deliveryMatches, error: deliveryMatchError} = await admin.rpc(
      'lk_excel_delivery_matches', {p_route_key: routeKey, p_customers: customerSet},
    );
    if (deliveryMatchError) throw deliveryMatchError;
    const deliveryMap = new Map((deliveryMatches ?? []).map((m: Record<string, unknown>) => [JSON.stringify([m.name,m.phone]),m.id]));
    for (const row of enrichedShipments) row.automation_delivery_profile_id = deliveryMap.get(JSON.stringify([row.consignee_name || '',row.consignee_phone || ''])) ?? null;

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
        .select('id,voyage,receipt_number,cost_name,amount_usd,discount_applies,delivery_type')
        .eq('route', shipmentRouteLabel)
        .eq('shipment_year', shipmentYear)
        .order('receipt_number', { ascending: true })
        .order('id', { ascending: true });

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

    const { data: localDeliveryProfiles, error: localDeliveryError } = await admin
      .from('local_delivery_profiles')
      .select('source_no,original_source_no,customer_name,alternate_name,company_name,phone,phone_display,delivery_type,local_company,destination_address,paid_by,notes,preferred')
      .eq('route_key', routeKey)
      .eq('active', true)
      .order('preferred', { ascending: false })
      .order('source_no', { ascending: true });
    if (localDeliveryError) throw localDeliveryError;
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
    const templateFileName = String(template.file_name ?? '').toLowerCase();
    const outputExtension = templateFileName.endsWith('.xlsm')
      ? 'xlsm'
      : 'xlsx';
    const outputFileName =
      `${prefix}_${shipmentYear}_${voyageToken}_SHIPMENTS.${outputExtension}`;

    const original = new Uint8Array(await templateBlob.arrayBuffer());
    console.log('[EXCEL200C] unzip start', original.byteLength);
    // calcChain은 아래에서 어차피 제거됩니다. 압축 해제 단계부터 제외하면
    // 큰 BASE 파일에서 불필요한 inflate/메모리 사용을 피할 수 있습니다.
    const files = unzipSync(original, {
      filter: (entry) => entry.name !== 'xl/calcChain.xml',
    });
    console.log('[EXCEL200C] unzip done');

    const targetPath = workbookSheetPath(files, '물품 입고 내역');
    const strings = sharedStrings(files);

    if (targetPath && files[targetPath]) {
      files[targetPath] = strToU8(
        updateCargoSheet(
          strFromU8(files[targetPath]),
          strings,
          enrichedShipments,
          routeKey,
        ),
      );
    } else if (routeKey !== 'th_la_land') {
      return json(422, {
        error:
          '현재 1차 Export는 \"물품 입고 내역\" 시트가 있는 실제 Excel부터 지원합니다. 원본 템플릿은 안전하게 저장되어 있습니다.',
      });
    }
    // Release row-local temporary strings before processing linked sheets.
    await new Promise<void>((resolve) => setTimeout(resolve, 0));
    console.log('[EXCEL] cargo updated', Deno.memoryUsage().heapUsed);
    // 실사용 Excel 연결: 고객 리스트와 기존 영수증 sheet의 cached value를 함께 갱신합니다.
    seedCustomerListFromShipments(files, enrichedShipments, routeKey, voyage);
    upgradeZoneQuantityFormulas(files);
    // 한 장의 기존 명세서에서 N2 영수번호를 선택해 전체 내용을 바꾸는 동적 명세서 기반.
    enableDynamicReceiptSelector(
      files,
      enrichedShipments,
      routeKey,
      shipmentYear,
      voyage,
    );
    wireStatementAutomationFormulas(files, routeKey);
    wireStatementVatFormulas(files, routeKey);
    wireStatementPaymentAccounts(files);
    applyStatementWrapText(files, routeKey);
    applyDeliveryColorConditionalFormatting(files, routeKey);
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
    // The App and website store receipt costs in the same DB table. When the
    // approved BASE contains the input sheet, mirror those values into it so
    // downloaded Excel statements use the same delivery-cost source.
    populateDeliveryCostInputSheet(files, voyageExtraCosts);
    console.log('[EXCEL] linked sheets updated', Deno.memoryUsage().heapUsed);
    formatStatementAmounts(files, routeKey);
    separateStatementDiscounts(files, routeKey, false, true);
    console.log('[EXCEL] discounts separated', Deno.memoryUsage().heapUsed);
    formatDeliveryNumbers(files, routeKey);
    appendDocumentAutomationBlock(
      files,
      enrichedShipments,
      (localDeliveryProfiles ?? []) as Record<string, unknown>[],
      voyageExtraCosts,
      settlementForExcel as Record<string, unknown> | null,
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

    // Native DEFLATE retains normal XLSM size without spending Edge CPU on a
    // JavaScript compressor. VBA and all other parts remain byte-identical.
    console.log('[EXCEL200C] zip start');
    const encoded = await zipWorkbook(files, { Zip, ZipPassThrough });
    console.log('[EXCEL200C] zip done', encoded.byteLength);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const exportPath =
      `${routeKey}/${shipmentYear}/${voyageToken}/${stamp}_${outputFileName}`;

    const { error: uploadError } = await admin.storage
      .from('shipment-excel-exports')
      .upload(exportPath, encoded, {
        upsert: false,
        contentType: outputExtension === 'xlsm'
          ? 'application/vnd.ms-excel.sheet.macroEnabled.12'
          : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    if (uploadError) throw uploadError;

    return json(200, {
      ok: true,
      file_name: outputFileName,
      automation_version: RECEIPT_RULE_VERSION,
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
