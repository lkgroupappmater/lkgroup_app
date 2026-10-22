import {workbookIndex} from './workbook-copy.mjs';

export const FREIGHT_IMPORT_VERSION = 'base-freight-v1';
const decode = b => new TextDecoder().decode(b || new Uint8Array());
const unescape = s => String(s).replace(/&#(x[0-9a-f]+|\d+);/gi, (_, n) => String.fromCodePoint(n[0].toLowerCase() === 'x' ? parseInt(n.slice(1), 16) : Number(n))).replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');
const text = s => [...s.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m => unescape(m[1])).join('');
const key = s => String(s).replace(/\s/g, '').toLowerCase();
const normalized = n => Number(n.toPrecision(12));

export function readCells(xml, strings = []) {
  const cells = new Map();
  for (const m of xml.matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
    const ref = m[1].match(/\br="([A-Z]+\d+)"/)?.[1]; if (!ref) continue;
    const type = m[1].match(/\bt="([^"]+)"/)?.[1], body = m[2] || '';
    const cached = body.match(/<v\b[^>]*>([\s\S]*?)<\/v>/)?.[1] ?? '';
    cells.set(ref, {ref, value: type === 's' ? strings[Number(cached)] : type === 'inlineStr' ? text(body) : unescape(cached), type, formula: body.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1] === undefined ? null : unescape(body.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)[1])});
  }
  return cells;
}

function number(cell, label) {
  if (!cell || cell.type === 'e' || String(cell.value).trim() === '' || !Number.isFinite(Number(cell.value))) throw Error(`${label}: 숫자 또는 저장된 수식 계산값이 없습니다. Excel에서 다시 계산·저장한 파일을 올려 주세요.`);
  const value = normalized(Number(cell.value));
  if (value < 0) throw Error(`${label}: 음수 운임은 적용할 수 없습니다.`);
  return value;
}

export function freightFromSheets(sheets) {
  const row = sheets.find(s => key(s.name) === 'rowdata');
  if (!row) throw Error('BASE Row data 시트를 찾을 수 없습니다.');
  let forms = sheets.filter(s => /^(LK[A-Z]*\s*(?:XX|\d+)|이름\(|.*명세서|product\s*data|물품 입고 내역)/i.test(s.name))
    .filter(s => [...s.cells.values()].some(c => /^[LM]\d+$/.test(c.ref) && /C\d+\*[FK]\d+|[FK]\d+\*C\d+/.test(c.formula || '')));
  const masters = forms.filter(s => /^(LK[A-Z]*\s*XX|이름\()/i.test(s.name));
  if (masters.length) forms = masters;
  let tiers = null, rateSource = null;
  // Locate the labelled table, rather than assuming B7:D19 on every route.
  for (const cell of row.cells.values()) {
    if (!['최소값', '최소중량', 'minweight', 'minimumweight', 'minweightkg'].includes(key(cell.value))) continue;
    const r = Number(cell.ref.match(/\d+/)[0]);
    const header = [...row.cells.values()].filter(c => Number(c.ref.match(/\d+/)[0]) === r);
    const rate = header.find(c => ['적용운임', '운임', '단가', 'rate', 'rateperkg', 'usd/kg'].includes(key(c.value)));
    if (!rate) continue;
    if (tiers) throw Error('BASE 운임 구간표가 두 개 이상입니다. 적용할 운임표를 확인해 주세요.');
    tiers = []; const col = cell.ref.replace(/\d+/g, ''), rateCol = rate.ref.replace(/\d+/g, '');
    for (let rr = r + 1; rr < r + 102; rr++) {
      const threshold = row.cells.get(col + rr), amount = row.cells.get(rateCol + rr);
      if (!threshold || String(threshold.value).trim() === '') {
        if (amount && String(amount.value).trim() !== '') throw Error(`Row data!${col + rr}: 운임 구간 최소값이 비어 있습니다.`);
        break;
      }
      const min_weight_kg = number(threshold, `Row data!${col + rr}`), rate_per_kg = number(amount, `Row data!${rateCol + rr}`);
      if (rate_per_kg <= 0 || (tiers.length ? min_weight_kg <= tiers.at(-1).min_weight_kg : min_weight_kg !== 0)) throw Error('운임 구간은 0kg부터 중복 없이 오름차순이어야 하며 단가는 0보다 커야 합니다.');
      tiers.push({min_weight_kg, rate_per_kg});
    }
    if (!tiers.length || tiers.length > 100) throw Error('BASE 운임 구간표를 확인해 주세요.');
    rateSource = `Row data!${col + (r + 1)}:${rateCol + (r + tiers.length)}`;
  }
  const resolve = (value, sheet) => {
    if (/^\d+(?:\.\d+)?$/.test(value)) return Number(value);
    const ref = /^(?:'([^']+)'|([^!]+))!\$?([A-Z]+)\$?(\d+)$/.exec(value);
    if (ref) return number(sheets.find(s => s.name === (ref[1] || ref[2]))?.cells.get(ref[3] + ref[4]), value);
    if (/^\$?[A-Z]+\$?\d+$/.test(value)) return number(sheet.cells.get(value.replaceAll('$', '')), value);
    throw Error('운임 수식 참조를 확인할 수 없습니다.');
  };
  const minima = new Set(), factors = new Set(), flatRates = new Set();
  for (const sheet of forms) for (const cell of sheet.cells.values()) {
    if (!tiers && /^C(?:[6-9]|1[0-5])$/.test(cell.ref) && cell.formula === null && cell.value !== '' && Number.isFinite(Number(cell.value)) && Number(cell.value)>0) flatRates.add(number(cell, `${sheet.name}!${cell.ref}`));
    const f = cell.formula?.replace(/\s+(?=[^']*(?:'[^']*'[^']*)*$)/g, '');
    if (!f) continue;
    const [, col, r] = /^([A-Z]+)(\d+)$/.exec(cell.ref);
    if (['L', 'M'].includes(col)) {
      const weight = col === 'L' ? 'F' : 'K';
      // Read the minimum actually referenced by the cargo formula, never footer prose.
      const value = f.match(new RegExp(`MAX\\(((?:'[^']+'|[A-Za-z][\\w ]*)!\\$?[A-Z]+\\$?\\d+|\\d+(?:\\.\\d+)?)(?:\\*D${r})?,(?:C${r}\\*${weight}${r}|${weight}${r}\\*C${r})\\)`))?.[1]
        || f.match(new RegExp(`IF\\(((?:'[^']+'|[A-Za-z][\\w ]*)!\\$?[A-Z]+\\$?\\d+|\\d+(?:\\.\\d+)?)(?:\\*D${r})?>=(?:C${r}\\*${weight}${r}|${weight}${r}\\*C${r}),`))?.[1];
      if (value) minima.add(normalized(resolve(value, sheet)));
    }
    if (col === 'J') {
      const volumeFormula = f.replace(/^IFERROR\((.*),"\s*"\)$/, '$1').replace(new RegExp(`^IF\\(G${r}="","",(.*)\\)$`),'$1');
      const m = new RegExp(`^\\(?G${r}\\*H${r}\\*I${r}\\)?\\*(\\d+(?:\\.\\d+)?(?:[eE]-?\\d+)?)$`).exec(volumeFormula);
      if (m) factors.add(normalized(Number(m[1])));
    }
    if (!tiers && col === 'C' && Number(r) >= 6 && Number(r) <= 15 && /^(?:\d+(?:\.\d+)?|(?:'[^']+'|[A-Za-z][\w ]*)!\$?[A-Z]+\$?\d+)$/.test(f)) flatRates.add(normalized(resolve(f, sheet)));
    if (!tiers && col === 'C') {
      const guarded = new RegExp(`^IF\\(""=D${r},"",IF\\(0<D${r},(\\d+(?:\\.\\d+)?)\\)\\)$`).exec(f.replace(/\s/g,''));
      if (guarded) flatRates.add(normalized(Number(guarded[1])));
      const blankGuarded = new RegExp(`^IF\\(D${r}="","",(\\d+(?:\\.\\d+)?)\\)$`).exec(f.replace(/\s/g,''));
      if (blankGuarded) flatRates.add(normalized(Number(blankGuarded[1])));
    }
  }
  if (!tiers && flatRates.size === 1) {tiers = [{min_weight_kg: 0, rate_per_kg: [...flatRates][0]}]; rateSource = 'statement C rate formula';}
  if (!tiers && flatRates.size > 1) throw Error(`BASE 명세서 C열 단가가 서로 다릅니다 (${[...flatRates].join(', ')} USD/kg). 공통 단가를 확인해 주세요. 기존 DB 운임은 유지됩니다.`);
  if (!tiers) throw Error('BASE 운임표/단가 수식을 인식하지 못했습니다. 기존 DB 운임은 유지됩니다.');
  if (minima.size !== 1 || factors.size !== 1) throw Error('BASE 최소 운임 또는 용적 계수를 명세서 수식에서 일관되게 확인할 수 없습니다.');
  const minimum_charge = [...minima][0], volumetric_factor = factors.size ? [...factors][0] : null;
  if (minimum_charge <= 0 || (volumetric_factor !== null && (volumetric_factor <= 0 || volumetric_factor >= 1))) throw Error('최소 운임 또는 용적 계수를 확인해 주세요.');
  return {version: FREIGHT_IMPORT_VERSION, tiers, minimum_charge, volumetric_factor, source: rateSource};
}

export function extractWorkbookFreight(bytes, unzip) {
  const files = unzip(bytes, {filter: e => ['xl/workbook.xml', 'xl/_rels/workbook.xml.rels', 'xl/sharedStrings.xml'].includes(e.name)});
  const strings = [...decode(files['xl/sharedStrings.xml']).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m => text(m[1]));
  const index = workbookIndex(files).filter(s => s.path && (key(s.name) === 'rowdata' || /^(LK[A-Z]*\s*(?:XX|\d+)|이름\(|.*명세서|product\s*data|물품 입고 내역)/i.test(s.name)));
  const wanted = new Set(index.map(s => s.path));
  const data = unzip(bytes, {filter: e => wanted.has(e.name)});
  return freightFromSheets(index.map(s => ({name: s.name, cells: readCells(decode(data[s.path]), strings)})));
}
