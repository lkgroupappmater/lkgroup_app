import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "로그인이 필요합니다." }, 401);
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) return json({ error: "서버 설정이 누락되었습니다." }, 500);

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data: { user: caller }, error: callerError } = await admin.auth.getUser(token);
    if (callerError || !caller) return json({ error: "로그인 사용자를 확인할 수 없습니다." }, 401);

    const body = await req.json();
    const action = String(body.action ?? "");
    let targetId = caller.id;

    if (action === "admin_delete") {
      const { data: profile } = await admin.from("profiles")
        .select("role,approval_status").eq("id", caller.id).maybeSingle();
      if (!profile || profile.role !== "admin" || String(profile.approval_status ?? "approved") !== "approved") {
        return json({ error: "총괄 관리자 권한이 필요합니다." }, 403);
      }
      targetId = String(body.user_id ?? "").trim();
      if (!targetId) return json({ error: "삭제할 회원 ID가 없습니다." }, 400);
      if (targetId === caller.id) return json({ error: "현재 로그인한 본인 계정은 회원 관리에서 삭제할 수 없습니다." }, 400);
    } else if (action === "self_delete") {
      // 앱에서 updateUser(currentPassword + nonce)를 통과한 직후 기록되는 메타데이터를 확인합니다.
      const verifiedAt = caller.user_metadata?.account_deletion_verified_at;
      if (!verifiedAt) return json({ error: "암호 및 이메일 본인 인증이 필요합니다." }, 403);
      const age = Date.now() - new Date(String(verifiedAt)).getTime();
      if (!Number.isFinite(age) || age < 0 || age > 10 * 60 * 1000) {
        return json({ error: "본인 인증 시간이 만료되었습니다. 다시 인증해 주세요." }, 403);
      }
    } else {
      return json({ error: "잘못된 요청입니다." }, 400);
    }

    const now = new Date();
    const purge = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
    const { error: profileError } = await admin.from("profiles").update({
      deletion_status: "pending",
      deleted_at: now.toISOString(),
      purge_after: purge.toISOString(),
      approval_status: "rejected",
    }).eq("id", targetId);
    if (profileError) return json({ error: profileError.message }, 400);

    // 30일 보관 중에는 Auth 계정을 ban하여 즉시 재로그인을 차단합니다.
    const { error: banError } = await admin.auth.admin.updateUserById(targetId, {
      ban_duration: "876000h",
    });
    if (banError) return json({ error: banError.message }, 400);

    return json({ ok: true, purge_after: purge.toISOString() });
  } catch (error) {
    return json({ error: String((error as { message?: unknown })?.message ?? error) }, 400);
  }
});
