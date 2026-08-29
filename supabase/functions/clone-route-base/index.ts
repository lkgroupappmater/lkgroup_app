import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'npm:fflate@0.8.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function escXml(value: unknown): string {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function columnIndex(column: string): number {
  let value = 0;
  for (const ch of column.toUpperCase()) {
    const code = ch.charCodeAt(0);
    if (code >= 65 && code <= 90) value = value * 26 + code - 64;
  }
  return value;
}

function inlineCell(ref: string, style: string, value: string): string {
  return `<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${escXml(value)}</t></is></c>`;
}

function numericCell(ref: string, style: string, value: number): string {
  return `<c r="${ref}"${style}><v>${value}</v></c>`;
}

function formulaCell(ref: string, style: string, formula: string): string {
  return `<c r="${ref}"${style}><f>${escXml(formula)}</f><v></v></c>`;
}

function updateCell(
  rowXml: string,
  rowNumber: number,
  column: string,
  value: string,
): string {
  const ref = `${column}${rowNumber}`;
  const cellRe = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>|<c\\b([^>]*)r="${ref}"([^>]*)\\/>`,
  );
  const existing = rowXml.match(cellRe);
  const attrs = existing
    ? `${existing[1] ?? existing[4] ?? ''}${existing[2] ?? existing[5] ?? ''}`
    : '';
  const styleMatch = attrs.match(/\bs="([^"]+)"/);
  const style = styleMatch ? ` s="${styleMatch[1]}"` : '';

  const trimmed = value.trim();
  let replacement: string;
  if (trimmed.startsWith('=')) {
    replacement = formulaCell(ref, style, trimmed.substring(1));
  } else if (trimmed !== '' && Number.isFinite(Number(trimmed))) {
    replacement = numericCell(ref, style, Number(trimmed));
  } else {
    replacement = inlineCell(ref, style, value);
  }

  if (existing) return rowXml.replace(cellRe, replacement);

  const targetIndex = columnIndex(column);
  for (const match of rowXml.matchAll(
    /<c\b[^>]*r="([A-Z]+)\d+"[^>]*(?:\/>|>[\s\S]*?<\/c>)/g,
  )) {
    if (columnIndex(match[1]) > targetIndex && match.index != null) {
      return `${rowXml.substring(0, match.index)}${replacement}${rowXml.substring(match.index)}`;
    }
  }
  const close = rowXml.lastIndexOf('</row>');
  return close >= 0
    ? `${rowXml.substring(0, close)}${replacement}${rowXml.substring(close)}`
    : rowXml;
}

function setCellInSheet(
  sheetXml: string,
  ref: string,
  value: string,
): string {
  const m = ref.toUpperCase().match(/^([A-Z]+)(\d+)$/);
  if (!m) return sheetXml;
  const column = m[1];
  const rowNumber = Number(m[2]);
  const rowRe = new RegExp(
    `<row\\b[^>]*r="${rowNumber}"[^>]*>[\\s\\S]*?<\\/row>`,
  );
  const rowMatch = sheetXml.match(rowRe);
  if (!rowMatch) return sheetXml;
  return sheetXml.replace(
    rowMatch[0],
    updateCell(rowMatch[0], rowNumber, column, value),
  );
}

function workbookSheets(
  files: Record<string, Uint8Array>,
): Map<string, string> {
  const result = new Map<string, string>();
  const workbook = strFromU8(files['xl/workbook.xml']);
  const rels = strFromU8(files['xl/_rels/workbook.xml.rels']);

  const relMap = new Map<string, string>();
  for (const m of rels.matchAll(
    /<Relationship\b[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"[^>]*\/?>/g,
  )) {
    let target = m[2].replace(/^\/+/, '');
    if (!target.startsWith('xl/')) target = `xl/${target}`;
    relMap.set(m[1], target);
  }

  for (const m of workbook.matchAll(
    /<sheet\b[^>]*name="([^"]*)"[^>]*r:id="([^"]+)"[^>]*\/?>/g,
  )) {
    const path = relMap.get(m[2]);
    if (path) result.set(m[1], path);
  }
  return result;
}

function sharedStrings(files: Record<string, Uint8Array>): string[] {
  const data = files['xl/sharedStrings.xml'];
  if (!data) return [];
  const xml = strFromU8(data);
  const out: string[] = [];
  for (const match of xml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
    out.push(
      [...match[1].matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)]
        .map((m) => m[1])
        .join(''),
    );
  }
  return out;
}

function cellText(
  sheetXml: string,
  ref: string,
  strings: string[],
): string {
  const re = new RegExp(
    `<c\\b([^>]*)r="${ref}"([^>]*)>([\\s\\S]*?)<\\/c>`,
  );
  const m = sheetXml.match(re);
  if (!m) return '';
  const attrs = `${m[1]}${m[2]}`;
  const body = m[3] ?? '';
  const inline = [...body.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)]
    .map((v) => v[1])
    .join('');
  if (inline) return inline;
  const raw = body.match(/<v>([\s\S]*?)<\/v>/)?.[1] ?? '';
  if (/\bt="s"/.test(attrs)) {
    const index = Number(raw);
    return Number.isFinite(index) ? strings[index] ?? '' : '';
  }
  return raw;
}

function safePathPart(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: 'Supabase server environment is not configured.' });
  }

  const jwt = (req.headers.get('Authorization') ?? '')
    .replace(/^Bearer\s+/i, '');
  if (!jwt) return json(401, { error: '로그인이 필요합니다.' });

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !authData.user) {
    return json(401, { error: '로그인 정보를 확인할 수 없습니다.' });
  }

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', authData.user.id)
    .maybeSingle();
  if (profileError) return json(500, { error: profileError.message });
  if (!profile || profile.role !== 'admin') {
    return json(403, { error: '총괄 관리자 전용 기능입니다.' });
  }

  try {
    const body = await req.json();
    const routeKey = String(body.route_key ?? '').trim();
    if (!routeKey) return json(400, { error: 'route_key가 필요합니다.' });

    const { data: target, error: targetError } = await admin
      .from('route_definitions')
      .select(
        'route_key,display_name,status,base_route_key,file_prefix,company_name,phone,address,template_overrides',
      )
      .eq('route_key', routeKey)
      .maybeSingle();
    if (targetError) throw targetError;
    if (!target) throw new Error('운송 경로 정의를 찾을 수 없습니다.');

    const sourceRouteKey =
      target.status === 'draft'
        ? String(target.base_route_key ?? '').trim()
        : routeKey;
    if (!sourceRouteKey) {
      throw new Error('기반 BASE 운송 경로가 없습니다.');
    }

    const { data: sourceDefinition } = await admin
      .from('route_definitions')
      .select('route_key,display_name,file_prefix,company_name,phone,address')
      .eq('route_key', sourceRouteKey)
      .maybeSingle();

    const { data: sourceBase, error: sourceBaseError } = await admin
      .from('shipment_excel_base_templates')
      .select('route_key,route_label,file_name,storage_path,active')
      .eq('route_key', sourceRouteKey)
      .eq('active', true)
      .maybeSingle();
    if (sourceBaseError) throw sourceBaseError;
    if (!sourceBase) {
      throw new Error('선택한 기반 운송 경로의 BASE Excel을 찾을 수 없습니다.');
    }

    const { data: blob, error: downloadError } = await admin.storage
      .from('shipment-excel-templates')
      .download(sourceBase.storage_path);
    if (downloadError || !blob) {
      throw downloadError ?? new Error('기반 BASE Excel 다운로드 실패');
    }

    const original = new Uint8Array(await blob.arrayBuffer());
    const files = unzipSync(original);
    const sheets = workbookSheets(files);
    const strings = sharedStrings(files);

    // 1) 명세서형 시트의 C1 제목을 신규/편집 운송 경로 타이틀로 자동 반영.
    for (const [, path] of sheets) {
      if (!files[path]) continue;
      let xml = strFromU8(files[path]);
      const c1 = cellText(xml, 'C1', strings);
      if (c1.includes('거래 명세서')) {
        xml = setCellInSheet(
          xml,
          'C1',
          `${String(target.display_name).trim()} 거래 명세서`,
        );
        files[path] = strToU8(xml);
      }
    }

    // 2) 원본 내부에 기존 metadata 문자열이 있으면 새 metadata로 치환.
    const replacements: Array<[string, string]> = [
      [String(sourceDefinition?.display_name ?? ''), String(target.display_name ?? '')],
      [String(sourceDefinition?.company_name ?? ''), String(target.company_name ?? '')],
      [String(sourceDefinition?.phone ?? ''), String(target.phone ?? '')],
      [String(sourceDefinition?.address ?? ''), String(target.address ?? '')],
      [String(sourceDefinition?.file_prefix ?? ''), String(target.file_prefix ?? '')],
    ].filter(([from, to]) => from.trim() !== '' && to.trim() !== '' && from !== to);

    if (replacements.length > 0) {
      for (const path of Object.keys(files)) {
        if (!path.endsWith('.xml') && !path.endsWith('.rels')) continue;
        let xml: string;
        try {
          xml = strFromU8(files[path]);
        } catch {
          continue;
        }
        let changed = false;
        for (const [from, to] of replacements) {
          if (xml.includes(from)) {
            xml = xml.split(from).join(escXml(to));
            changed = true;
          }
        }
        if (changed) files[path] = strToU8(xml);
      }
    }

    // 3) 총괄 관리자가 지정한 정확한 sheet/cell override 반영.
    const overrides = Array.isArray(target.template_overrides)
      ? target.template_overrides
      : [];
    for (const raw of overrides) {
      const sheetName = String(raw?.sheet_name ?? '').trim();
      const cellRef = String(raw?.cell_ref ?? '').trim().toUpperCase();
      const value = String(raw?.value ?? '');
      if (!sheetName || !/^[A-Z]+\d+$/.test(cellRef)) continue;
      const path = sheets.get(sheetName);
      if (!path || !files[path]) {
        throw new Error(`BASE Excel 시트를 찾을 수 없습니다: ${sheetName}`);
      }
      const xml = strFromU8(files[path]);
      files[path] = strToU8(setCellInSheet(xml, cellRef, value));
    }

    delete files['xl/calcChain.xml'];
    if (files['xl/_rels/workbook.xml.rels']) {
      let rels = strFromU8(files['xl/_rels/workbook.xml.rels']);
      rels = rels.replace(
        /<Relationship\b[^>]*Type="http:\/\/schemas\.openxmlformats\.org\/officeDocument\/2006\/relationships\/calcChain"[^>]*\/>/g,
        '',
      );
      files['xl/_rels/workbook.xml.rels'] = strToU8(rels);
    }
    if (files['[Content_Types].xml']) {
      let types = strFromU8(files['[Content_Types].xml']);
      types = types.replace(
        /<Override\b[^>]*PartName="\/xl\/calcChain\.xml"[^>]*\/>/g,
        '',
      );
      files['[Content_Types].xml'] = strToU8(types);
    }

    let workbook = strFromU8(files['xl/workbook.xml']);
    if (/<calcPr\b/.test(workbook)) {
      workbook = workbook.replace(
        /<calcPr\b[^>]*\/>/,
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>',
      );
    } else {
      workbook = workbook.replace(
        '</workbook>',
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>',
      );
    }
    files['xl/workbook.xml'] = strToU8(workbook);

    const encoded = zipSync(files, { level: 6 });
    const year =
      String(sourceBase.file_name ?? '').match(/20\d{2}/)?.[0] ??
      String(new Date().getFullYear());
    const filePrefix =
      safePathPart(String(target.file_prefix ?? '').trim()) ||
      safePathPart(routeKey).toUpperCase();
    const fileName = `${filePrefix}_${year}_V00_SHIPMENTS.xlsx`;
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const storagePath =
      `base/${safePathPart(routeKey)}/${stamp}_${fileName}`;

    const { error: uploadError } = await admin.storage
      .from('shipment-excel-templates')
      .upload(storagePath, encoded, {
        upsert: false,
        contentType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    if (uploadError) throw uploadError;

    const { data: existing, error: existingError } = await admin
      .from('shipment_excel_base_templates')
      .select('route_key')
      .eq('route_key', routeKey)
      .maybeSingle();
    if (existingError) throw existingError;

    if (existing) {
      const { error: updateError } = await admin
        .from('shipment_excel_base_templates')
        .update({
          route_label: String(target.display_name),
          file_name: fileName,
          storage_path: storagePath,
          active: true,
        })
        .eq('route_key', routeKey);
      if (updateError) throw updateError;
    } else {
      const { error: insertError } = await admin
        .from('shipment_excel_base_templates')
        .insert({
          route_key: routeKey,
          route_label: String(target.display_name),
          file_name: fileName,
          storage_path: storagePath,
          active: true,
        });
      if (insertError) throw insertError;
    }

    return json(200, {
      ok: true,
      route_key: routeKey,
      route_label: target.display_name,
      source_route_key: sourceRouteKey,
      file_name: fileName,
      storage_path: storagePath,
      override_count: overrides.length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('clone-route-base failed:', error);
    return json(500, { error: message });
  }
});
