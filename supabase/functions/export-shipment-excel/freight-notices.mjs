// The validity month belongs to the download. The freight notice belongs to the
// selected route (or to the specific uploaded voyage's own 1 kg tariff).
import {deliverySheetIndex} from './shared-delivery-layout.mjs';
import {preserveCellText, richTextValue} from './cell-text-format.mjs';

const decoder = new TextDecoder();
const encoder = new TextEncoder();
const read = bytes => decoder.decode(bytes);
const xml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const cellPattern = /<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g;
const attr = (tag, key) => tag.match(new RegExp('\\s' + key + '="([^"]*)"'))?.[1];
const monthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const englishDate = /(\bvalid\s+(?:(?:through|until)\s+(?:the\s+)?)?end\s+of\s+)(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s*\/\s*\d{4}/gi;
const koreanDate = /(기한\s*[:：]\s*)\d{4}(년\s*)\d{1,2}(월\s*말)/g;
const minimumText = /(최소\s*운임(?:은|는)?\s*[:：]?\s*(?:US\s*\$|USD\s*\$?|\$)\s*)(\d+(?:\.\d+)?)(?=\s*\/\s*kg\b)/i;
const printedNote = /^\s*[*＊※•]/u;

export function freightNoticePeriod(instant = new Date()) {
  const parts = new Intl.DateTimeFormat('en', {timeZone:'Asia/Vientiane', year:'numeric', month:'2-digit'}).formatToParts(instant);
  return parts.find(p => p.type === 'year').value + '-' + parts.find(p => p.type === 'month').value;
}

function updateDeadline(text, period) {
  const [year, month] = period.split('-');
  return text.replace(englishDate, (_, lead) => lead + monthNames[Number(month) - 1] + '/' + year)
    .replace(koreanDate, (_, lead, yearUnit, monthUnit) => lead + year + yearUnit + month + monthUnit);
}

function existingCell(cell, strings) {
  const open = cell.slice(0, cell.indexOf('>') + 1);
  const type = attr(open, 't');
  const value = cell.match(/<v\b[^>]*>([\s\S]*?)<\/v>/)?.[1] ?? '';
  const body = type === 's' ? strings[Number(value)] ?? '' : cell.match(/<is\b[^>]*>([\s\S]*?)<\/is>/)?.[1];
  return {open, ref:attr(open, 'r'), body, text:body === undefined ? richTextValue('<t>' + value + '</t>') : richTextValue(body)};
}

function typedCell(open, type, contents) {
  const tag = /\st="[^"]*"/.test(open) ? open.replace(/\st="[^"]*"/, ' t="' + type + '"') : open.slice(0,-1) + ' t="' + type + '">';
  return tag + contents + '</c>';
}

function writeText(cell, value) {
  if (cell.body && /<r\b/.test(cell.body)) {
    return preserveCellText(typedCell(cell.open, 'inlineStr', '<is>' + cell.body + '</is>'), value);
  }
  return typedCell(cell.open, 'inlineStr', '<is><t xml:space="preserve">' + xml(value) + '</t></is>');
}

function oneKgCell(rowXml, strings) {
  // Both A:C and B:D layouts are in use. Match the header pair and threshold
  // rather than the human-readable "~1kg" caption or a fixed coordinate.
  let weightCol, rateCol, selected;
  for (const [row] of rowXml.matchAll(/<row\b[^>]*?(?:\/>|>[\s\S]*?<\/row>)/g)) {
    const cells = [...row.matchAll(cellPattern)].map(([c]) => existingCell(c, strings));
    const column = c => c.ref?.replace(/\d+$/, '');
    if (!weightCol) {
      const label = c => c.text.replace(/\s/g,'').toLowerCase();
      const weight = cells.find(c => ['최소값','최소중량','minweight','minimumweight','minweightkg'].includes(label(c)));
      const rate = cells.find(c => ['적용운임','운임','단가','rate','rateperkg','usd/kg'].includes(label(c)));
      if (weight && rate) { weightCol = column(weight); rateCol = column(rate); }
      continue;
    }
    const weight = cells.find(c => column(c) === weightCol)?.text.trim();
    if (!weight || !Number.isFinite(Number(weight)) || Number(weight) > 1) break;
    const rate = cells.find(c => column(c) === rateCol);
    if (Number(weight) >= 0 && rate) selected = {ref:rate.ref, amount:Number(rate.text)};
  }
  return selected;
}

function flatFormRate(sheet, strings) {
  // Only the established flat-rate C6 inputs. Do not use a customer's
  // discounted item, a footer amount, or a minimum-per-parcel threshold.
  const cell = sheet.match(/<c\b[^>]*\br="C6"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/)?.[0];
  if (!cell) return null;
  const formula = cell.match(/<f\b[^>]*>([^<]+)<\/f>/)?.[1];
  if (!formula) return Number(existingCell(cell, strings).text) || null;
  const text = richTextValue('<t>' + formula + '</t>').replace(/\s/g, '');
  const value = text.match(/^IF\(D6="","",(\d+(?:\.\d+)?)\)$/)?.[1]
    ?? text.match(/^IF\(""=D6,"",IF\(0<D6,(\d+(?:\.\d+)?)\)\)$/)?.[1]
    ?? text.match(/^(\d+(?:\.\d+)?)$/)?.[1];
  return value ? Number(value) : null;
}

// The only formula that this exporter owns in the footer. Both literals come
// from the existing notice; the reference is always an internal numeric cell.
export const linkedMinimumFormula = /^"((?:[^"]|"")*)"&'Row data'!\$[A-Z]+\$[1-9]\d*&"((?:[^"]|"")*)"$/;
const xlString = s => '"' + s.replaceAll('"', '""') + '"';

export function refreshFreightNotices(files, {period, routeRate, useWorkbookRate = false}) {
  const strings = [...read(files['xl/sharedStrings.xml']).matchAll(/<si\b[^>]*?(?:\/>|>([\s\S]*?)<\/si>)/g)].map(m => m[1] || '');
  const sheets = deliverySheetIndex(files);
  const data = sheets.find(s => s.name.trim().toLowerCase() === 'row data');
  const tier = data && oneKgCell(read(files[data.path]), strings);
  let deadlineCells = 0, minimumCells = 0, changed = 0, noticeRate = null;
  for (const {name, path} of sheets) {
    if (!files[path] || name.startsWith('_LK_')) continue;
    const source = read(files[path]);
    // A voyage's copied form can be renamed after the recipient.
    if (!/^(?:L[A-Z]+\s*\S|이름\()|명세서|가견적/i.test(name) &&
        !/<mergeCell\b[^>]*\bref="A(\d+):N\1"/.test(source)) continue;
    const local = tier?.amount || flatFormRate(source, strings);
    const rate = Number(useWorkbookRate ? local || routeRate : routeRate || local);
    // If an administrator set a distinct current DB price, a BASE download
    // prints that price without dismantling a workbook's supplier formulas.
    const link = tier && (useWorkbookRate || Math.abs(rate - tier.amount) < 1e-9) && data.name === 'Row data';
    const next = source.replace(cellPattern, original => {
      const start = original.slice(0,original.indexOf('>')+1);
      if (!/\br="A\d+"/.test(start) || !/\bt="(?:s|inlineStr|str)"/.test(start)) return original;
      const formulaXml = original.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1];
      const linked = formulaXml && linkedMinimumFormula.exec(richTextValue('<t>'+formulaXml+'</t>'));
      if (/<f\b/.test(original) && !linked) return original;
      const cell = existingCell(original, strings);
      // Excel readers may clear the cached string. Restore it only from the
      // two literal operands of our own internal reference.
      const old = linked ? linked[1].replaceAll('""','"') + '0' + linked[2].replaceAll('""','"') : cell.text;
      if (/valid\s+(?:(?:through|until)\s+(?:the\s+)?)?end\s+of|기한\s*[:：]/i.test(old)) {
        const value = updateDeadline(old, period);
        deadlineCells++;
        if (value !== old) { changed++; return writeText(cell, value); }
      }
      const match = printedNote.test(old) && minimumText.exec(old);
      if (!match) return original;
      if (!(rate > 0 && Number.isFinite(rate))) throw Error('1kg 구간 적용 운임을 확인할 수 없습니다.');
      noticeRate = Number(rate.toPrecision(12));
      const index = match.index + match[1].length;
      const before = old.slice(0, index), after = old.slice(index + match[2].length);
      const value = before + noticeRate + after;
      minimumCells++;
      let output = original;
      if (link && !/<r\b/.test(cell.body || '')) {
        const ref = tier.ref.replace(/^([A-Z]+)(\d+)$/, (_, c, r) => '$'+c+'$'+r);
        const formula = xlString(before) + "&'Row data'!" + ref + '&' + xlString(after);
        output = typedCell(cell.open, 'str', '<f>' + xml(formula) + '</f><v>' + xml(value) + '</v>');
      } else if (old !== value || formulaXml) {
        output = writeText(cell, value);
      }
      if (output !== original) changed++;
      return output;
    });
    if (next !== source) files[path] = encoder.encode(next);
  }
  return {period, deadline_cells:deadlineCells, minimum_cells:minimumCells, one_kg_rate:noticeRate, changed};
}
