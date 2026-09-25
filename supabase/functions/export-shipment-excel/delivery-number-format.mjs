// The approved sea/air delivery lists use 11pt serial numbers, never percentages.
// Repair cell presentation only; retain source values, formulas and shared styles.
export function formatDeliveryNumbers(files, routeKey) {
  if (!['kr_la_sea', 'kr_la_air'].includes(routeKey)) return;
  const decode = data => new TextDecoder().decode(data);
  const encode = text => new TextEncoder().encode(text);
  const attr = (tag, name) => tag.match(new RegExp(`(?:^|\\s)${name}="([^"]*)"`))?.[1];
  const setAttr = (tag, name, value) => {
    const pattern = new RegExp(`(\\s${name}=")[^"]*(")`);
    return pattern.test(tag) ? tag.replace(pattern, (_, a, b) => a + value + b)
      : tag.replace(/\s*\/?>(?=$)/, close => ` ${name}="${value}"${close}`);
  };
  const textOf = xml => [...xml.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map(m => m[1]).join('');
  const strings = [...decode(files['xl/sharedStrings.xml'] || new Uint8Array()).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)].map(m => textOf(m[1]));
  const workbook = decode(files['xl/workbook.xml']);
  const rels = [...decode(files['xl/_rels/workbook.xml.rels']).matchAll(/<Relationship\b[^>]*\/?\>/g)];
  const targets = [];
  for (const sheet of workbook.matchAll(/<sheet\b[^>]*\/?\>/g)) {
    if (!['지방배송', '시내배송'].includes((attr(sheet[0], 'name') || '').replace(/\s/g, ''))) continue;
    const relation = rels.find(r => attr(r[0], 'Id') === attr(sheet[0], 'r:id'));
    let path = relation && attr(relation[0], 'Target');
    if (!path) continue;
    path = path.replace(/^\//, '');
    if (!path.startsWith('xl/')) path = 'xl/' + path;
    if (files[path]) targets.push(path);
  }
  if (!targets.length) return;
  let styles = decode(files['xl/styles.xml']);
  const fontBlock = styles.match(/<fonts\b[^>]*>([\s\S]*?)<\/fonts>/);
  const xfBlock = styles.match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/);
  const fonts = [...(fontBlock?.[1] || '').matchAll(/<font\b[^>]*?(?:\/>|>[\s\S]*?<\/font>)/g)].map(m => m[0]);
  const xfs = [...(xfBlock?.[1] || '').matchAll(/<xf\b[^>]*?(?:\/>|>[\s\S]*?<\/xf>)/g)].map(m => m[0]);
  if (!fontBlock || !xfBlock || !fonts.length || !xfs.length ||
      fonts.length !== Number(attr(fontBlock[0], 'count')) || xfs.length !== Number(attr(xfBlock[0], 'count'))) {
    throw Error('Cannot safely resolve delivery number styles.');
  }
  const fontCache = new Map(), styleCache = new Map();
  const fontFor = id => {
    if (fontCache.has(id)) return fontCache.get(id);
    let font = fonts[id];
    if (!font) throw Error(`Unknown delivery number font ${id}`);
    const size = font.match(/<sz\b[^>]*\/>/);
    if (Number(size && attr(size[0], 'val')) === 11) return id;
    if (font.endsWith('/>')) font = font.slice(0, -2) + '></font>';
    font = size ? font.replace(size[0], () => setAttr(size[0], 'val', 11))
      : font.replace('</font>', '<sz val="11"/></font>');
    let next = fonts.indexOf(font);
    if (next < 0) { next = fonts.length; fonts.push(font); }
    fontCache.set(id, next);
    return next;
  };
  const styleFor = (id, isHeader) => {
    const key = `${id}:${isHeader}`;
    if (styleCache.has(key)) return styleCache.get(key);
    let xf = xfs[id];
    if (!xf) throw Error(`Unknown delivery number style ${id}`);
    const font = fontFor(Number(attr(xf, 'fontId') || 0));
    xf = xf.replace(/^<xf\b[^>]*>/, tag => {
      for (const [name, value] of Object.entries({numFmtId: isHeader ? 0 : 1, fontId: font, applyFont: 1, applyNumberFormat: 1})) tag = setAttr(tag, name, value);
      return tag;
    });
    let next = xfs.indexOf(xf);
    if (next < 0) { next = xfs.length; xfs.push(xf); }
    styleCache.set(key, next);
    return next;
  };
  for (const path of targets) {
    let xml = decode(files[path]);
    const headers = new Map();
    // Resolve columns from their visible No. header, not route-specific style IDs.
    for (const match of xml.matchAll(/<c\b[^>]*?(?:\/>|>[\s\S]*?<\/c>)/g)) {
      const cell = match[0], ref = attr(cell, 'r')?.match(/^([A-Z]+)(\d+)$/);
      if (!ref || Number(ref[2]) > 2) continue;
      const label = attr(cell, 't') === 's' ? strings[Number(cell.match(/<v>([^<]*)<\/v>/)?.[1])]
        : textOf(cell);
      if (/^no\.?$/i.test((label || '').trim())) headers.set(ref[1], Number(ref[2]));
    }
    if (!headers.size) continue;
    xml = xml.replace(/<c\b[^>]*>/g, tag => {
      const ref = attr(tag, 'r')?.match(/^([A-Z]+)(\d+)$/);
      if (!ref || !headers.has(ref[1]) || Number(ref[2]) < headers.get(ref[1])) return tag;
      return setAttr(tag, 's', styleFor(Number(attr(tag, 's') || 0), Number(ref[2]) === headers.get(ref[1])));
    });
    files[path] = encode(xml);
  }
  // Append clones; never repurpose indices used by discount/currency/other cells.
  styles = styles.replace(fontBlock[0], () => fontBlock[0].replace(/^<fonts\b[^>]*>/, tag => setAttr(tag, 'count', fonts.length)).replace(fontBlock[1], () => fonts.join('')));
  styles = styles.replace(xfBlock[0], () => xfBlock[0].replace(/^<cellXfs\b[^>]*>/, tag => setAttr(tag, 'count', xfs.length)).replace(xfBlock[1], () => xfs.join('')));
  files['xl/styles.xml'] = encode(styles);
}
