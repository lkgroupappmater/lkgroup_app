import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRoleKey) {
    return json(500, { error: 'Supabase server environment is not configured.' });
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const now = new Date().toISOString();

    const { data: routes, error: routeError } = await admin
      .from('route_definitions')
      .select('route_key,display_name,purge_after')
      .eq('status', 'deleted')
      .lte('purge_after', now);

    if (routeError) throw routeError;
    if (!routes || routes.length === 0) {
      return json(200, { ok: true, purged: 0 });
    }

    const purged: string[] = [];
    const errors: Record<string, string> = {};

    for (const route of routes) {
      const key = String(route.route_key);

      try {
        // BASE / 항차 템플릿의 실제 Storage 파일을 먼저 제거한다.
        const storagePaths = new Set<string>();

        const { data: baseTemplates, error: baseError } = await admin
          .from('shipment_excel_base_templates')
          .select('storage_path')
          .eq('route_key', key);
        if (baseError) throw baseError;
        for (const row of baseTemplates ?? []) {
          const path = String(row.storage_path ?? '').trim();
          if (path) storagePaths.add(path);
        }

        const { data: voyageTemplates, error: voyageError } = await admin
          .from('shipment_excel_templates')
          .select('storage_path')
          .eq('route_key', key);
        if (voyageError) throw voyageError;
        for (const row of voyageTemplates ?? []) {
          const path = String(row.storage_path ?? '').trim();
          if (path) storagePaths.add(path);
        }

        if (storagePaths.size > 0) {
          const { error: removeError } = await admin.storage
            .from('shipment-excel-templates')
            .remove([...storagePaths]);
          if (removeError) throw removeError;
        }

        // route 설정과 직접 연계된 데이터만 삭제한다.
        // 기존 화물/거래 기록 자체는 이 정책의 삭제 대상이 아니다.
        const tables = [
          'shipment_excel_templates',
          'shipment_excel_base_templates',
          'freight_rate_tiers',
          'route_definition_audit',
        ];

        for (const table of tables) {
          const { error } = await admin
            .from(table)
            .delete()
            .eq('route_key', key);
          if (error) throw error;
        }

        const { error: routeDeleteError } = await admin
          .from('route_definitions')
          .delete()
          .eq('route_key', key)
          .eq('status', 'deleted')
          .lte('purge_after', now);

        if (routeDeleteError) throw routeDeleteError;
        purged.push(key);
      } catch (error) {
        errors[key] =
          error instanceof Error ? error.message : String(error);
      }
    }

    return json(200, {
      ok: Object.keys(errors).length === 0,
      purged: purged.length,
      route_keys: purged,
      errors,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('purge-deleted-routes failed:', error);
    return json(500, { error: message });
  }
});
