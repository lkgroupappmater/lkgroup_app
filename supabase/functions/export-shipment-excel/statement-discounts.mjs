// Targeted formula repair. All other XLSM parts, styles and VBA stay unchanged.
const decode = bytes => new TextDecoder().decode(bytes);
const encode = text => new TextEncoder().encode(text);
const unescape = text => text.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const cellPattern = ref => new RegExp(`<c\\b[^>]*\\br="${ref}"[^>]*?(?:\\/>|>[\\s\\S]*?<\\/c>)`);
const formulaAt = (xml, ref) => {
  const cell = xml.match(cellPattern(ref))?.[0];
  const f = cell?.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1];
  return f == null ? null : unescape(f);
};
function putFormula(xml, ref, formula, styleRef = ref) {
  const pattern = cellPattern(ref), existing = xml.match(pattern)?.[0];
  const source = xml.match(cellPattern(styleRef))?.[0];
  const style = (existing || source)?.match(/\bs="(\d+)"/)?.[1];
  const next = `<c r="${ref}"${style ? ` s="${style}"` : ''}><f>${escape(formula)}</f><v>0</v></c>`;
  if (existing) return xml.replace(pattern, () => next);
  const row = ref.match(/\d+$/)[0];
  const rowPattern = new RegExp(`(<row\\b[^>]*\\br="${row}"[^>]*>)([\\s\\S]*?)(<\\/row>)`);
  if (!rowPattern.test(xml)) throw Error(`Missing discount source row ${row}`);
  return xml.replace(rowPattern, (_, open, body, close) => open + body + next + close);
}
function sheetPaths(files) {
  const rels = [...decode(files['xl/_rels/workbook.xml.rels']).matchAll(/<Relationship\b[^>]*\/>/g)];
  return [...decode(files['xl/workbook.xml']).matchAll(/<sheet\b[^>]*\/?\>/g)].map(([tag]) => {
    const name = unescape(tag.match(/\bname="([^"]*)"/)?.[1] || '');
    const rid = tag.match(/\br:id="([^"]*)"/)?.[1];
    const rel = rels.find(([v]) => v.match(/\bId="([^"]*)"/)?.[1] === rid)?.[0];
    let path = rel?.match(/\bTarget="([^"]*)"/)?.[1]?.replace(/^\//, '');
    if (path && !path.startsWith('xl/')) path = 'xl/' + path;
    return {name, path};
  });
}
const special = `'Row data'!$AG$3:$AG$256="특별할인"`;
const ordinary = `'Row data'!$AG$3:$AG$256<>"특별할인"`;
export function separateCargoRowDiscounts(rowXml, rowNumber, onChange) {
    const r = Number(rowNumber); if (r < 6) return rowXml;
    const cells = new Map([...rowXml.matchAll(/<c\b[^>]*\br="([A-Z]+\d+)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)].map(m => [m[1],m[0]]));
    const f = formulaAt(cells.get(`AJ${r}`) || '', `AJ${r}`); if (!f || f.includes(ordinary)) return rowXml;
    const pending = new Map();
    const set = (ref, formula, styleRef) => {
      const source = cells.get(ref) || cells.get(styleRef) || '';
      const style = source.match(/\bs="(\d+)"/)?.[1];
      pending.set(ref, `<c r="${ref}"${style ? ` s="${style}"` : ''}><f>${escape(formula)}</f><v>0</v></c>`);
      onChange?.({ref,formula});
    };
    const addFilter = condition => f.replaceAll('LOOKUP(2,1/(', `LOOKUP(2,1/((${condition})*`);
    set(`AO${r}`, addFilter(special), `AJ${r}`);
    set(`AJ${r}`, addFilter(ordinary));
    set(`AP${r}`, `IF(AO${r}=0,0,INDEX('Row data'!$AM:$AM,AO${r}))`, `AD${r}`);
    set(`AE${r}`, `IF(AJ${r}=0,0,INDEX('Row data'!$AN:$AN,AJ${r}))+IF(AO${r}=0,0,INDEX('Row data'!$AN:$AN,AO${r}))`);
    const remark = formulaAt(cells.get(`T${r}`) || '', `T${r}`);
    if (remark) set(`T${r}`, `(${remark})&IF(AO${r}=0,"",IF((${remark})="",""," / ")&INDEX('Row data'!$AL:$AL,AO${r}))`);
    rowXml = rowXml.replace(/<c\b[^>]*\br="([A-Z]+\d+)"[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g, (cell,ref) => {
      const replacement = pending.get(ref);
      pending.delete(ref);
      return replacement || cell;
    });
    return rowXml.replace('</row>', () => [...pending.values()].join('') + '</row>');
  }

export function formatCargoDiscountColumns(xml) {
    // Only the two required calculation columns are added, hidden from the form.
    if (!/<col\b[^>]*\bmin="41"[^>]*\bmax="42"/.test(xml)) {
      xml = xml.replace(/<col\b[^>]*\bmin="41"[^>]*\bmax="16384"[^>]*\/>/,
        tag => '<col min="41" max="42" width="12" hidden="1" customWidth="1"/>' + tag.replace('min="41"', 'min="43"'));
    }
    xml = xml.replace(/(<dimension\b[^>]*ref="[A-Z]+\d+:)[A-Z]+(\d+")/, '$1AP$2');
  return xml;
}

export function separateStatementDiscounts(files, routeKey, collectChanges = true, cargoAlreadySeparated = false) {
  if (!['kr_la_sea', 'kr_la_air'].includes(routeKey)) return [];
  const sheets = sheetPaths(files), cargo = sheets.find(s => s.name === '물품 입고 내역');
  if (!cargo?.path || !files[cargo.path]) return [];
  const changes = [];
  if (!cargoAlreadySeparated) {
    let xml = decode(files[cargo.path]);
    const original = formulaAt(xml, 'AJ6');
    if (!original?.includes("'Row data'!$AH$3:$AH$256")) throw Error('Unsupported discount source layout');
    let cargoChanged = false;
    const pieces = [];
    let cursor = 0;
    for (const match of xml.matchAll(/<row\b[^>]*\br="(\d+)"[^>]*>[\s\S]*?<\/row>/g)) {
      const row = separateCargoRowDiscounts(match[0],match[1], change => {
        cargoChanged = true;
        if (collectChanges) changes.push({sheet:cargo.name,...change});
      });
      pieces.push(xml.slice(cursor,match.index),row);
      cursor = match.index + match[0].length;
    }
    pieces.push(xml.slice(cursor));
    if (cargoChanged) files[cargo.path] = encode(formatCargoDiscountColumns(pieces.join('')));
  }
  for (const {name, path} of sheets) {
    if (!/^(LKS|LKA)\s/.test(name) && name !== '명세서 빠르게 확인') continue;
    let sheet = decode(files[path]);
    const end = formulaAt(sheet, 'N19')?.match(/'물품 입고 내역'!\$AE\$6:\$AE\$(\d+)/)?.[1];
    if (!end) throw Error(`Unsupported special discount formula: ${name}`);
    const rate = `IFERROR(INDEX('물품 입고 내역'!$AP$6:$AP$${end},MATCH($N$2,'물품 입고 내역'!$N$6:$N$${end},0)),0)`;
    const amount = `IFERROR(INDEX('물품 입고 내역'!$AE$6:$AE$${end},MATCH($N$2,'물품 입고 내역'!$N$6:$N$${end},0)),0)`;
    const f = `IFERROR(MIN(MAX(0,MAX(0,N17-$W$11)*(${rate})+(${amount})),MAX(0,N17-$W$11-N18)),0)`;
    if (formulaAt(sheet, 'N19') !== f) {
      sheet = putFormula(sheet, 'N19', f);
      if (collectChanges) changes.push({sheet:name,ref:'N19',formula:f});
      files[path] = encode(sheet);
    }
  }
  return changes;
}
