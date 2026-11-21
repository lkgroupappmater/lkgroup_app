// Keep the existing finalization order while sharing its CPU work between the
// authenticated identity stage and final storage stage. No worksheet is omitted.
import {applyUnknownPrefixZones} from './unknown-zone.mjs';
import {applyFreightMinimum} from './freight-minimum.mjs';
import {beginTemplateStyleGuard,STYLE_CONTEXT_ENTRY} from './template-style-guard.mjs';
import {discardCalculationChain} from './workbook-package.mjs';
const dec=new TextDecoder(),enc=new TextEncoder(),text=data=>dec.decode(data);
export const FINALIZATION_CONTEXT_ENTRY='_lk_internal_finalization_context.json';
function sharedStrings(files                            )           {
  const data = files['xl/sharedStrings.xml'];
  if (!data) return [];
  const xml = text(data);
  const out           = [];
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
  files                            ,
  targetName        ,
)                {
  const workbook = text(files['xl/workbook.xml']);
  const rels = text(files['xl/_rels/workbook.xml.rels']);

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

function cellText(cellXml        , strings          )         {
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

function decodeXmlText(value        )         {
  return value.replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, (entity) => {
    const named                         = {'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"};
    if (named[entity]) return named[entity];
    const code = entity.startsWith('&#x') || entity.startsWith('&#X')
      ? parseInt(entity.slice(3, -1), 16) : Number(entity.slice(2, -1));
    return Number.isInteger(code) && code > 0 && code <= 0x10ffff
      ? String.fromCodePoint(code) : entity;
  });
}


export function prepareWorkbookFinalization(files){
 if(files[FINALIZATION_CONTEXT_ENTRY])throw Error('Reserved Excel finalization context already exists');
 const captureStage=files[STYLE_CONTEXT_ENTRY]?'source':'finalizer';
 const calculationChain=discardCalculationChain(files);
 if(captureStage==='finalizer')beginTemplateStyleGuard(files);
 applyUnknownPrefixZones(files,{sheetPath:workbookSheetPath,strings:sharedStrings(files),cellText});
 const repair=applyFreightMinimum(files);
 const context={version:1,captureStage,calculationChain,freightMinimumChanged:repair.changed_count};
 files[FINALIZATION_CONTEXT_ENTRY]=enc.encode(JSON.stringify(context));
 return context;
}
export function consumeWorkbookFinalization(files){
 // Compatibility for older, already-running identity requests during deployment.
 if(!files[FINALIZATION_CONTEXT_ENTRY])prepareWorkbookFinalization(files);
 const context=JSON.parse(text(files[FINALIZATION_CONTEXT_ENTRY]));
 if(context.version!==1||!['source','finalizer'].includes(context.captureStage)||!Number.isInteger(context.freightMinimumChanged)||context.freightMinimumChanged<0||
    !['parts','relationships','content_types'].every(k=>Number.isInteger(context.calculationChain?.[k])&&context.calculationChain[k]>=0))throw Error('Invalid Excel finalization context');
 delete files[FINALIZATION_CONTEXT_ENTRY];
 return context;
}
