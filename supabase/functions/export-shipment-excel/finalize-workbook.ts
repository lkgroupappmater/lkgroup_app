import {strFromU8} from 'npm:fflate@0.8.2';
import {applyUnknownPrefixZones} from './unknown-zone.mjs';
import {applyFreightMinimum,FREIGHT_MINIMUM_VERSION} from './freight-minimum.mjs';
import {validateWorkbookFormulas} from './workbook-integrity.mjs';
import {upgradeStatementMacros} from './statement-macros.mjs';

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


export function finalizeWorkbook(files:Record<string,Uint8Array>){
 applyUnknownPrefixZones(files,{sheetPath:workbookSheetPath,strings:sharedStrings(files),cellText});
 const repair=applyFreightMinimum(files);
 const integrity={...validateWorkbookFormulas(files),freight_minimum_version:FREIGHT_MINIMUM_VERSION,freight_minimum_changed:repair.changed_count};
 upgradeStatementMacros(files);
 return integrity;
}
