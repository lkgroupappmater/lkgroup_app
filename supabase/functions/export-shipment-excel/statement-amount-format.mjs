// Presentation-only patch for the official KR -> LA sea/air statement forms.
// Keep the XLSM package, VBA, drawings, source values and existing rounding intact.
export function formatStatementAmounts(files, routeKey) {
  if (!['kr_la_sea', 'kr_la_air'].includes(routeKey)) return;
  const decode = bytes => new TextDecoder().decode(bytes);
  const encode = text => new TextEncoder().encode(text);
  const escape = text => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const money = (symbol, digits) => {
    const unit = symbol === '฿' ? '[$฿-409]' : `"${symbol}"`;
    return `${unit}* #,##0${digits ? '.0' : ''};[Red]${unit}* -#,##0${digits ? '.0' : ''};${unit}* 0${digits ? '.0' : ''};@`;
  };
  let styles = decode(files['xl/styles.xml']);
  const formats = styles.match(/<numFmts\b[^>]*>([\s\S]*?)<\/numFmts>/);
  let formatBody = formats?.[1] || '';
  let nextId = Math.max(163, ...[...formatBody.matchAll(/numFmtId="(\d+)"/g)].map(m => Number(m[1]))) + 1;
  const formatId = code => {
    const escaped = escape(code);
    const existing = [...formatBody.matchAll(/<numFmt\b[^>]*\/>/g)].find(m => m[0].includes(`formatCode="${escaped}"`));
    if (existing) return Number(existing[0].match(/numFmtId="(\d+)"/)[1]);
    const id = nextId++;
    formatBody += `<numFmt numFmtId="${id}" formatCode="${escaped}"/>`;
    return id;
  };
  const ids = {percent: formatId('0.##%;[Red]-0.##%;0%;"0%"'),
    usd: formatId(money('$', 1)), kip: formatId(money('₭', 0)),
    thb: formatId(money('฿', 0)), krw: formatId(money('₩', 0))};
  const xfBlock = styles.match(/<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/);
  if (!xfBlock) throw Error('Statement cell styles are missing.');
  const xfs = [...xfBlock[1].matchAll(/<xf\b[^>]*?(?:\/>|>[\s\S]*?<\/xf>)/g)].map(m => m[0]);
  if (xfs.length !== Number(xfBlock[0].match(/\bcount="(\d+)"/)?.[1])) {
    throw Error('Cannot safely resolve statement styles.');
  }
  const cache = new Map();
  const setAttr = (tag, name, value) => new RegExp(`\\b${name}="[^"]*"`).test(tag)
    ? tag.replace(new RegExp(`\\b${name}="[^"]*"`), `${name}="${value}"`)
    : tag.replace(/\s*\/?>(?=$)/, close => ` ${name}="${value}"${close}`);
  const styleFor = (oldId, kind) => {
    const key = `${oldId}:${kind}`;
    if (cache.has(key)) return cache.get(key);
    let xf = xfs[oldId];
    if (!xf) throw Error(`Unknown statement style ${oldId}`);
    if (xf.endsWith('/>')) xf = xf.slice(0, -2) + '></xf>';
    xf = xf.replace(/^<xf\b[^>]*>/, tag => setAttr(setAttr(setAttr(tag, 'numFmtId', ids[kind]), 'applyNumberFormat', 1), 'applyAlignment', 1));
    if (/<alignment\b/.test(xf)) xf = xf.replace(/<alignment\b[^>]*\/?\>/, tag => setAttr(setAttr(tag, 'horizontal', 'right'), 'indent', 0));
    else xf = xf.replace('</xf>', '<alignment horizontal="right" indent="0"/></xf>');
    let id = xfs.indexOf(xf);
    if (id < 0) { id = xfs.length; xfs.push(xf); }
    cache.set(key, id); return id;
  };
  const workbook = decode(files['xl/workbook.xml']);
  const relationships = decode(files['xl/_rels/workbook.xml.rels']);
  const prefix = routeKey === 'kr_la_sea' ? 'LKS' : 'LKA';
  for (const sheet of workbook.matchAll(/<sheet\b[^>]*\/?\>/g)) {
    const name = sheet[0].match(/\bname="([^"]*)"/)?.[1];
    if (!name?.startsWith(prefix)) continue;
    const rid = sheet[0].match(/\br:id="([^"]*)"/)?.[1];
    const rel = [...relationships.matchAll(/<Relationship\b[^>]*\/?\>/g)].find(m => m[0].match(/\bId="([^"]*)"/)?.[1] === rid);
    let path = rel?.[0].match(/\bTarget="([^"]*)"/)?.[1]?.replace(/^\//, '');
    if (!path) continue;
    if (!path.startsWith('xl/')) path = `xl/${path}`;
    let xml = decode(files[path]);
    const cell = ref => xml.match(new RegExp(`<c\\b[^>]*\\br="${ref}"[^>]*>[\\s\\S]*?<\\/c>`))?.[0];
    const formula = ref => cell(ref)?.match(/<f\b[^>]*>([\s\S]*?)<\/f>/)?.[1];
    const source = formula('M19'), deduction = formula('N19');
    if (source && deduction?.includes('M19')) {
      const old = cell('N19');
      xml = xml.replace(old, () => old.replace(/(<f\b[^>]*>)[\s\S]*?(<\/f>)/, (_, a, b) => a + deduction.replace(/\bM19\b/g, () => `(${source})`) + b));
      const rateCell = cell('M19');
      xml = xml.replace(rateCell, () => rateCell.replace(/(<f\b[^>]*>)[\s\S]*?(<\/f>)/,
        (_, a, b) => a + 'IFERROR(N19/MAX(0,N17-$W$11),0)' + b).replace(/<v>[^<]*<\/v>/, '<v>0</v>'));
    }
    xml = xml.replace(/<c\b[^>]*\br="(M(?:18|19|20)|N(?:17|18|19|20|21|22|23|24))"[^>]*>/g, (tag, ref) => {
      const kind = ref.startsWith('M') ? 'percent' : ({N22: 'kip', N23: 'thb', N24: 'krw'}[ref] || 'usd');
      return setAttr(tag, 's', styleFor(Number(tag.match(/\bs="(\d+)"/)?.[1] || 0), kind));
    });
    files[path] = encode(xml);
  }
  const numFmts = `<numFmts count="${[...formatBody.matchAll(/<numFmt\b/g)].length}">${formatBody}</numFmts>`;
  styles = formats ? styles.replace(formats[0], () => numFmts) : styles.replace(/(<styleSheet\b[^>]*>)/, (_, open) => open + numFmts);
  styles = styles.replace(xfBlock[0], () => `<cellXfs count="${xfs.length}">${xfs.join('')}</cellXfs>`);
  files['xl/styles.xml'] = encode(styles);
}
