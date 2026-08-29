import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { unzipSync, zipSync, strFromU8, strToU8 } from 'npm:fflate@0.8.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

function colOf(ref: string): string {
  return (ref.match(/^[A-Z]+/)?.[0] ?? '');
}

function rowOf(ref: string): number {
  return Number(ref.match(/\d+$/)?.[0] ?? 0);
}

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
      .map((m) => m[1])
      .join('');
  }
  const raw = cellXml.match(/<v>([\s\S]*?)<\/v>/)?.[1] ?? '';
  if (type === 's') {
    const index = Number(raw);
    return Number.isFinite(index) ? strings[index] ?? '' : '';
  }
  return raw;
}

function findHeaderRow(sheetXml: string, strings: string[]): number {
  for (const rowMatch of sheetXml.matchAll(/<row\b[^>]*r="(\d+)"[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = Number(rowMatch[1]);
    if (row > 20) break;
    const values: string[] = [];
    for (const cellMatch of rowMatch[2].matchAll(/<c\b[^>]*r="([A-Z]+\d+)"[^>]*>[\s\S]*?<\/c>/g)) {
      values.push(cellText(cellMatch[0], strings).trim());
    }
    const joined = values.join('|').toLowerCase();
    if (
      (joined.includes('box no') || joined.includes('박스')) &&
      (joined.includes('송장') || joined.includes('수령') || joined.includes('수신'))
    ) return row;
  }
  return -1;
}

function numericCell(ref: string, style: string, value: unknown): string {
  const n = Number(value);
  if (!Number.isFinite(n)) return blankCell(ref, style);
  return `<c r="${ref}"${style}><v>${n}</v></c>`;
}

function inlineCell(ref: string, style: string, value: unknown): string {
  const text = String(value ?? '');
  if (!text) return blankCell(ref, style);
  return `<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${escXml(text)}</t></is></c>`;
}

function blankCell(ref: string, style: string): string {
  return `<c r="${ref}"${style}></c>`;
}

function excelDateSerial(value: unknown): number | null {
  const text = String(value ?? '').trim();
  if (!text) return null;
  const date = new Date(`${text.substring(0, 10)}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) return null;
  return date.getTime() / 86400000 + 25569;
}

function updateCell(
  rowXml: string,
  rowNumber: number,
  column: string,
  value: unknown,
  kind: 'text' | 'number' | 'date',
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

  let replacement: string;
  if (kind === 'number') {
    replacement = numericCell(ref, style, value);
  } else if (kind === 'date') {
    const serial = excelDateSerial(value);
    replacement = serial == null
      ? blankCell(ref, style)
      : numericCell(ref, style, serial);
  } else {
    replacement = inlineCell(ref, style, value);
  }

  if (existing) return rowXml.replace(cellRe, replacement);

  const close = rowXml.lastIndexOf('</row>');
  return close >= 0
    ? `${rowXml.substring(0, close)}${replacement}${rowXml.substring(close)}`
    : rowXml;
}

function updateCargoSheet(
  sheetXml: string,
  strings: string[],
  shipments: Record<string, unknown>[],
): string {
  const headerRow = findHeaderRow(sheetXml, strings);
  if (headerRow < 0) {
    throw new Error('"물품 입고 내역" 헤더 행을 찾지 못했습니다.');
  }

  const firstDataRow = headerRow + 1;
  const rows = [...sheetXml.matchAll(
    /<row\b[^>]*r="(\d+)"[^>]*>[\s\S]*?<\/row>/g,
  )];
  const candidateRows = rows
    .map((m) => ({ number: Number(m[1]), xml: m[0] }))
    .filter((r) => r.number >= firstDataRow);

  if (shipments.length > candidateRows.length) {
    throw new Error(
      `현재 템플릿 화물 행 ${candidateRows.length}개보다 DB 화물 ${shipments.length}개가 많습니다. ` +
      '행 자동 확장은 다음 단계에서 해당 노선 명세서 구조와 함께 적용해야 합니다.',
    );
  }

  const mapping: Array<[string, string, 'text' | 'number' | 'date']> = [
    ['B', 'box_number', 'text'],
    ['C', 'invoice_number', 'text'],
    ['D', 'sender_name', 'text'],
    ['E', 'consignee_name', 'text'],
    ['F', 'consignee_phone', 'text'],
    ['G', 'contents', 'text'],
    ['H', 'package_type', 'text'],
    ['I', 'quantity', 'number'],
    ['J', 'weight_kg', 'number'],
    ['K', 'length_cm', 'number'],
    ['L', 'width_cm', 'number'],
    ['M', 'height_cm', 'number'],
    ['N', 'receipt_number', 'text'],
    ['O', 'unloading_zone', 'text'],
    ['P', 'notes', 'text'],
    ['Q', 'received_at', 'date'],
  ];

  let output = sheetXml;
  for (let i = 0; i < candidateRows.length; i++) {
    const candidate = candidateRows[i];
    const shipment = i < shipments.length ? shipments[i] : {};
    let rowXml = candidate.xml;

    for (const [column, key, kind] of mapping) {
      rowXml = updateCell(
        rowXml,
        candidate.number,
        column,
        shipment[key] ?? '',
        kind,
      );
    }

    output = output.replace(candidate.xml, rowXml);
  }
  return output;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: 'Supabase server environment is not configured.' });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '');
  if (!jwt) return json(401, { error: '로그인이 필요합니다.' });

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !authData.user) return json(401, { error: '로그인 정보를 확인할 수 없습니다.' });

  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', authData.user.id)
    .maybeSingle();
  if (profileError) return json(500, { error: profileError.message });
  if (!profile || !['admin', 'staff'].includes(profile.role)) {
    return json(403, { error: '관리자·직원 권한이 필요합니다.' });
  }

  try {
    const body = await req.json();
    const routeKey = String(body.route_key ?? '').trim();
    const shipmentYear = Number(body.shipment_year);
    const voyage = String(body.voyage ?? '').trim();

    if (!routeKey || !Number.isInteger(shipmentYear) || !voyage) {
      return json(400, { error: '운송 경로/연도/항차 값이 올바르지 않습니다.' });
    }

    const { data: template, error: templateError } = await admin
      .from('shipment_excel_templates')
      .select('route_key,route_label,shipment_year,voyage,file_name,storage_path')
      .eq('route_key', routeKey)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .maybeSingle();

    if (templateError) throw templateError;
    if (!template) {
      return json(404, { error: '해당 항차의 업로드 원본 Excel 템플릿이 없습니다.' });
    }

    const { data: templateBlob, error: downloadError } = await admin.storage
      .from('shipment-excel-templates')
      .download(template.storage_path);
    if (downloadError || !templateBlob) {
      throw downloadError ?? new Error('원본 템플릿 다운로드 실패');
    }

    const { data: shipments, error: shipmentError } = await admin
      .from('shipments')
      .select(
        'id,box_number,invoice_number,sender_name,consignee_name,consignee_phone,contents,package_type,quantity,weight_kg,length_cm,width_cm,height_cm,receipt_number,unloading_zone,notes,received_at,created_at',
      )
      .eq('route', template.route_label)
      .eq('shipment_year', shipmentYear)
      .eq('voyage', voyage)
      .order('box_number', { ascending: true })
      .order('id', { ascending: true });

    if (shipmentError) throw shipmentError;

    const original = new Uint8Array(await templateBlob.arrayBuffer());
    const files = unzipSync(original);
    const targetPath = workbookSheetPath(files, '물품 입고 내역');
    if (!targetPath || !files[targetPath]) {
      return json(422, {
        error:
          '현재 1차 Export는 "물품 입고 내역" 시트가 있는 실제 Excel부터 지원합니다. 원본 템플릿은 안전하게 저장되어 있습니다.',
      });
    }

    const strings = sharedStrings(files);
    const sheetXml = strFromU8(files[targetPath]);
    files[targetPath] = strToU8(
      updateCargoSheet(
        sheetXml,
        strings,
        (shipments ?? []) as Record<string, unknown>[],
      ),
    );

    // Excel에서 수식을 다시 계산하도록 calc mode만 지정합니다.
    let workbookXml = strFromU8(files['xl/workbook.xml']);
    if (/<calcPr\b/.test(workbookXml)) {
      workbookXml = workbookXml.replace(
        /<calcPr\b([^>]*)\/>/,
        '<calcPr$1 calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/>',
      );
    } else {
      workbookXml = workbookXml.replace(
        '</workbook>',
        '<calcPr calcMode="auto" fullCalcOnLoad="1" forceFullCalc="1"/></workbook>',
      );
    }
    files['xl/workbook.xml'] = strToU8(workbookXml);

    const encoded = zipSync(files, { level: 6 });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const exportPath =
      `${routeKey}/${shipmentYear}/V${voyage}/${stamp}_${template.file_name}`;

    const { error: uploadError } = await admin.storage
      .from('shipment-excel-exports')
      .upload(exportPath, encoded, {
        upsert: false,
        contentType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    if (uploadError) throw uploadError;

    return json(200, {
      ok: true,
      file_name: template.file_name,
      storage_path: exportPath,
      shipment_count: shipments?.length ?? 0,
      mode: 'archive-preserving-cargo-list-v1',
    });
  } catch (error) {
    return json(500, {
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
