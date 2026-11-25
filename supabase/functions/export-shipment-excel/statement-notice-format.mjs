import {deliverySheetIndex} from './shared-delivery-layout.mjs';
import {linkedMinimumFormula} from './freight-notices.mjs';
import {richTextValue} from './cell-text-format.mjs';

const decoder = new TextDecoder();
const encoder = new TextEncoder();
const read = bytes => decoder.decode(bytes);
const attr = (tag, name) => tag.match(new RegExp('\\s' + name + '="([^"]*)"'))?.[1];

function sheetNotices(xml, strings) {
  const ranges = new Map();
  for (const [tag] of xml.matchAll(/<mergeCell\b[^>]*>/g)) {
    const range = attr(tag, 'ref');
    const match = range?.match(/^([A-Z]+)(\d+):([A-Z]+)\2$/);
    if (!match || Number(match[2]) < 7) continue;
    const row = Number(match[2]);
    if (!ranges.has(row)) ranges.set(row, new Map());
    ranges.get(row).set(match[1] + match[2], range);
  }
  const notices = [];
  for (const [row] of xml.matchAll(/<row\b[^>]*?(?:\/>|>[\s\S]*?<\/row>)/g)) {
    const tag = row.slice(0, row.indexOf('>') + 1);
    const merged = ranges.get(Number(attr(tag, 'r')));
    if (!merged) continue;
    for (const [cell] of row.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)) {
      const open = cell.slice(0, cell.indexOf('>') + 1);
      const ref = attr(open, 'r');
      if (!merged.has(ref)) continue;
      const formulaBody = cell.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1];
      const formula = formulaBody && richTextValue('<t>' + formulaBody + '</t>');
      if (/<f\b/.test(cell) && !(formula && linkedMinimumFormula.test(formula))) continue;
      const value = cell.match(/<v>([\s\S]*?)<\/v>/)?.[1];
      const type = attr(open, 't');
      const label = type === 's' ? strings[Number(value)] : type === 'inlineStr' ? richTextValue(cell) : type === 'str' ? richTextValue('<t>' + (value ?? '') + '</t>') : '';
      if (!/^\s*[*＊※•]/u.test(label || '')) continue;
      notices.push({ref, range: merged.get(ref), label, ...(formula ? {formula} : {}), style: Number(attr(open, 's') || 0),
        height: attr(tag, 'ht'), rowStyle: attr(tag, 's'), customHeight: attr(tag, 'customHeight'), hidden: attr(tag, 'hidden')});
    }
  }
  return notices;
}

function noticeSheets(files) {
  const strings = [...read(files['xl/sharedStrings.xml']).matchAll(/<si\b[^>]*?(?:\/>|>[\s\S]*?<\/si>)/g)].map(([si]) => richTextValue(si));
  const out = [];
  for (const sheet of deliverySheetIndex(files)) {
    if (!/^(?:L[A-Z]+\s*\S|이름\()|명세서|가견적/i.test(sheet.name) || !files[sheet.path]) continue;
    const xml = read(files[sheet.path]);
    const notices = sheetNotices(xml, strings);
    if (notices.length) out.push({path: sheet.path, notices});
  }
  return out;
}

export function captureStatementNotices(files) {
  return noticeSheets(files);
}

// Excel retains the original cell styles on the blank members of a merged row.
// Repair only a lost/default anchor with unanimous centred peer formatting.
// Keep the anchor's borders, fill, number format and protection.
export function repairStatementNotices(files, tables) {
  let changed = 0;
  const xfs = tables.cellXfs.slice();
  const fontSize = xf => Number(attr(tables.fonts[Number(attr(xf, 'fontId') || 0)]?.match(/<sz\b[^>]*>/)?.[0] || '', 'val'));
  for (const {path, notices} of noticeSheets(files)) {
    let sheetChanged = false;
    let xml = read(files[path]);
    for (const notice of notices) {
      if (!/^\s*[*＊]\s*(?:모든 비용은|입[.·]출고지를|물품 도착 및 출고 후|물품 출고 후)/u.test(notice.label)) continue;
      const old = xfs[notice.style];
      if (!old) throw Error('Unknown Excel notice style: ' + notice.ref);
      const oldAlign = old.match(/<alignment\b[^>]*?(?:\/>|>[\s\S]*?<\/alignment>)/)?.[0];
      if (!/^A\d+:N\d+$/.test(notice.range) || !(fontSize(old) > 0 && fontSize(old) <= 12) ||
          !['general', 'left'].includes(attr(oldAlign || '', 'horizontal') || 'general')) continue;
      const row = notice.ref.slice(1);
      const peers = [];
      const rowXml = xml.match(new RegExp('<row\\b[^>]*\\br="' + row + '"[^>]*>[\\s\\S]*?</row>'))?.[0] || '';
      for (const [tag] of rowXml.matchAll(/<c\b[^>]*>/g)) {
        if (!new RegExp('^[B-N]' + row + '$').test(attr(tag, 'r') || '')) continue;
        const xf = xfs[Number(attr(tag, 's') || 0)] || '';
        const alignment = xf.match(/<alignment\b[^>]*?(?:\/>|>[\s\S]*?<\/alignment>)/)?.[0];
        if (!(fontSize(xf) > 12) || attr(alignment || '', 'horizontal') !== 'center') { peers.push(null); break; }
        peers.push([attr(xf, 'fontId'), alignment]);
      }
      if (peers.length !== 13 || !peers[0] || !peers.every(p => p && p[0] === peers[0][0] && p[1] === peers[0][1])) continue;
      const [fontId, alignment] = peers[0];
      let next = old.endsWith('/>') && !old.includes('</xf>') ? old.slice(0, -2) + '></xf>' : old;
      next = next.replace(/^<xf\b[^>]*>/, tag => {
        for (const [k,v] of [['fontId',fontId],['applyFont','1'],['applyAlignment','1']]) {
          tag = attr(tag,k) === undefined ? tag.replace(/>$/, ' ' + k + '="' + v + '">') : tag.replace(new RegExp('\\s' + k + '="[^"]*"'), ' ' + k + '="' + v + '"');
        }
        return tag;
      });
      next = oldAlign ? next.replace(oldAlign, () => alignment) : next.replace(/<protection\b|<extLst\b|<\/xf>/, t => alignment + t);
      let id = xfs.indexOf(next);
      if (id === -1) id = xfs.push(next) - 1;
      xml = xml.replace(new RegExp('<c\\b[^>]*\\br="' + notice.ref + '"[^>]*>'), tag =>
        attr(tag,'s') === undefined ? tag.replace(/>$/, ' s="' + id + '">') : tag.replace(/\ss="\d+"/, ' s="' + id + '"'));
      sheetChanged = true;
      changed++;
    }
    if (sheetChanged) files[path] = encoder.encode(xml);
  }
  if (xfs.length > tables.cellXfs.length) {
    const styles = read(files['xl/styles.xml']).replace(/<cellXfs\b[^>]*>[\s\S]*?<\/cellXfs>/, block =>
      block.replace(/\bcount="\d+"/, 'count="' + xfs.length + '"').replace('</cellXfs>', () => xfs.slice(tables.cellXfs.length).join('') + '</cellXfs>'));
    files['xl/styles.xml'] = encoder.encode(styles);
  }
  return changed;
}
