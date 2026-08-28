import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json(405, { error: 'Method not allowed' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const exchangeApiKey = Deno.env.get('EXCHANGE_RATE_API_KEY');

  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: 'Supabase server environment is not configured.' });
  }

  if (!exchangeApiKey) {
    return json(500, { error: 'EXCHANGE_RATE_API_KEY is not configured.' });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const fetchedAt = new Date().toISOString();

  try {
    const response = await fetch(
      `https://v6.exchangerate-api.com/v6/${encodeURIComponent(exchangeApiKey)}/latest/USD`,
      {
        method: 'GET',
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(10000),
      },
    );

    if (!response.ok) {
      throw new Error(`ExchangeRate-API HTTP ${response.status}`);
    }

    const payload = await response.json();
    if (payload?.result !== 'success') {
      throw new Error(`ExchangeRate-API error: ${payload?.['error-type'] ?? 'unknown'}`);
    }

    const rates = payload?.conversion_rates ?? {};
    const lak = Number(rates.LAK);
    const thb = Number(rates.THB);
    const krw = Number(rates.KRW);

    if (!Number.isFinite(lak) || lak <= 0 ||
        !Number.isFinite(thb) || thb <= 0 ||
        !Number.isFinite(krw) || krw <= 0) {
      throw new Error('ExchangeRate-API returned an invalid LAK/THB/KRW rate.');
    }

    const sourceUnix = Number(payload?.time_last_update_unix);
    const sourceUpdatedAt = Number.isFinite(sourceUnix) && sourceUnix > 0
      ? new Date(sourceUnix * 1000).toISOString()
      : null;

    const { error } = await admin
      .from('exchange_rate_settings')
      .upsert({
        id: 1,
        base_kip: lak,
        base_thb: thb,
        base_krw: krw,
        rate_source: 'ExchangeRate-API',
        auto_sync_enabled: true,
        last_fetch_at: fetchedAt,
        source_updated_at: sourceUpdatedAt,
        fetch_status: 'success',
        last_fetch_error: null,
        updated_by: null,
        updated_at: fetchedAt,
      }, { onConflict: 'id' });

    if (error) throw error;

    return json(200, {
      ok: true,
      base: 'USD',
      rates: { LAK: lak, THB: thb, KRW: krw },
      source: 'ExchangeRate-API',
      source_updated_at: sourceUpdatedAt,
      fetched_at: fetchedAt,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    // 실패 시 기준환율(base_kip/base_thb/base_krw)은 절대 변경하지 않는다.
    // 상태/오류시각만 기록하여 마지막 정상 환율을 계속 사용한다.
    await admin
      .from('exchange_rate_settings')
      .update({
        last_fetch_at: fetchedAt,
        fetch_status: 'error',
        last_fetch_error: message.slice(0, 1000),
      })
      .eq('id', 1);

    return json(502, {
      ok: false,
      error: message,
      kept_last_successful_rates: true,
    });
  }
});
