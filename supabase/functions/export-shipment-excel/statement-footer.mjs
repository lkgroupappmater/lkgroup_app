import {translateFormula} from './workbook-integrity.mjs';

const unescape = text => text.replaceAll('&lt;', '<').replaceAll('&gt;', '>')
  .replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&');

// Excel's row-fit macro moves the whole footer. Resolve the existing bounded
// special-discount formula, not a fixed N19 coordinate or a cached R6 value.
// Only the official formula shape qualifies; custom/ambiguous formulas fail closed.
export function statementDiscountFooter(xml) {
  const cells = new Map(), masters = new Map();
  for (const [cell] of xml.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)) {
    const ref = cell.match(/\br="([A-Z]+\d+)"/)?.[1];
    if (!ref) continue;
    const f = cell.match(/<f\b([^>]*?)(?:\/>|>([\s\S]*?)<\/f>)/);
    const formula = f?.[2] ? unescape(f[2]) : null;
    const shared = f?.[1].match(/\bsi="(\d+)"/)?.[1];
    cells.set(ref, {formula, shared});
    if (shared != null && formula) masters.set(shared, {ref, formula});
  }
  const formulaAt = ref => {
    const cell = cells.get(ref);
    if (cell?.formula) return cell.formula;
    const master = masters.get(cell?.shared);
    return master ? translateFormula(master.formula, master.ref, ref) : null;
  };
  const candidates = [];
  for (const ref of cells.keys()) {
    if (!/^N\d+$/.test(ref)) continue;
    const row = Number(ref.slice(1));
    if (row < 9) continue;
    const deduction = formulaAt(ref), source = formulaAt(`M${row}`);
    if (!deduction) continue;
    const expanded = source ? deduction.replace(new RegExp(`(?<![A-Z0-9_!])\\$?M\\$?${row}(?![0-9])`, 'g'), () => `(${source})`) : deduction;
    const end = expanded.match(/'물품 입고 내역'!\$?AE\$?6:\$?AE\$?(\d+)/)?.[1];
    const compact = expanded.replace(/\s|\$/g, '');
    if (!end || !compact.startsWith('IFERROR(MIN(MAX(0,') || !compact.includes('W11') ||
        !new RegExp(`N${row - 2}(?![0-9])`).test(compact) ||
        !new RegExp(`N${row - 1}(?![0-9])`).test(compact)) continue;
    candidates.push({row, end, source, deduction, expanded});
  }
  return candidates.length === 1 ? candidates[0] : null;
}
