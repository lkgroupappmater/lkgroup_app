// Formula-only repair. Keep original prices, blank/zero guards, discounts and
// shared-formula anchors; D is parcel quantity in the existing L/M freight rows.
export const FREIGHT_MINIMUM_VERSION = 'per-cargo-minimum-v1';
const enc = new TextEncoder(), dec = new TextDecoder();
const decode = s => s.replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&');
const encode = s => s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
const minimum = "(?:[0-9]+(?:\\.[0-9]+)?|'Row data'!\\$[A-Z]+\\$[0-9]+)";
export function minimumPerCargoFormula(formula, ref) {
  const cell = /^([LM])([1-9][0-9]*)$/.exec(ref);
  if (!cell) return formula;
  const r = cell[2], weight = cell[1] === 'L' ? 'F' : 'K';
  const amount = `(?:C${r}\\*${weight}${r}|${weight}${r}\\*C${r})`;
  // Exact known worksheet expressions only. Existing custom/overridden formulas
  // are not guessed, and already-multiplied minima cannot match a second time.
  const modern = new RegExp(`^IF\\(${weight}${r}="","",MAX\\((${minimum}),(${amount})\\)\\)$`);
  const m = modern.exec(formula);
  if (m) return `IF(${weight}${r}="","",MAX(${m[1]}*D${r},${m[2]}))`;
  const legacy = new RegExp(`^((?:IFERROR\\()?\\(IF\\(0=${amount},0,IF\\()(${minimum})(>=${amount},)\\2(,${amount}\\)\\)\\)(?:," "\\))?)$`);
  const l = legacy.exec(formula);
  return l ? `${l[1]}${l[2]}*D${r}${l[3]}${l[2]}*D${r}${l[4]}` : formula;
}
export function applyFreightMinimum(files) {
  const changed = [];
  for (const [path, bytes] of Object.entries(files)) {
    if (!/^xl\/worksheets\/[^/]+\.xml$/.test(path)) continue;
    const source = dec.decode(bytes), groups = new Set();
    // Only L/M can contain these freight formulas. Do not decode the much
    // larger identity/delivery formulas in every other worksheet cell.
    let xml = source.replace(/<c\b[^>]*\br="([LM][1-9][0-9]*)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g, (cell,ref) => {
      const f = /<f\b[^>]*>([^<]+)<\/f>/.exec(cell);
      if (!f) return cell;
      const oldFormula = decode(f[1]), formula = minimumPerCargoFormula(oldFormula, ref);
      if (formula === oldFormula) return cell;
      const si = f[0].match(/\bsi="([^"]+)"/)?.[1];
      if (si !== undefined) groups.add(si);
      changed.push({path, cell:ref, before:oldFormula, after:formula});
      return cell.replace(f[0], f[0].replace(f[1], encode(formula))).replace(/<v\b[^>]*>[\s\S]*?<\/v>/,'');
    });
    if (xml === source) continue;
    // Invalidate caches of the same shared group, without expanding or moving it.
    if (groups.size) xml = xml.replace(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g, cell => {
      const f=cell.match(/<f\b[^>]*(?:\/>|>)/)?.[0], si=f?.match(/\bsi="([^"]+)"/)?.[1];
      return groups.has(si) ? cell.replace(/<v\b[^>]*>[\s\S]*?<\/v>/,'') : cell;
    });
    files[path] = enc.encode(xml);
  }
  if (changed.length && files['xl/workbook.xml']) {
    let xml = dec.decode(files['xl/workbook.xml']);
    const calc = '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>';
    xml = /<calcPr\b/.test(xml) ? xml.replace(/<calcPr\b[^>]*\/>/, tag => {
      for (const [key,value] of [['calcMode','auto'],['fullCalcOnLoad','1'],['forceFullCalc','1']]) {
        const re=new RegExp(`\\b${key}="[^"]*"`);
        tag=re.test(tag)?tag.replace(re,`${key}="${value}"`):tag.replace('/>',` ${key}="${value}"/>`);
      } return tag;
    }) : xml.replace('</workbook>',calc+'</workbook>');
    files['xl/workbook.xml'] = enc.encode(xml);
  }
  return {version:FREIGHT_MINIMUM_VERSION, changed_count:changed.length, changed};
}
