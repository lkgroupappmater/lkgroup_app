import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "로그인이 필요합니다." }, 401);

    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "로그인 토큰이 없습니다." }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceRoleKey) {
      return json({ error: "Edge Function 서버 설정이 누락되었습니다." }, 500);
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    // 전달된 실제 사용자 JWT를 service-role client에서 직접 검증합니다.
    const {
      data: { user: caller },
      error: callerError,
    } = await admin.auth.getUser(token);

    if (callerError || !caller) {
      return json({ error: "로그인 사용자를 확인할 수 없습니다." }, 401);
    }

    const { data: isTotalAdmin, error: adminCheckError } = await admin
      .rpc("is_total_admin_user", { target_user_id: caller.id });

    if (adminCheckError) {
      return json(
        {
          error: "총괄 관리자 권한을 확인할 수 없습니다.",
          detail: adminCheckError.message,
        },
        403,
      );
    }

    if (isTotalAdmin !== true) {
      return json({ error: "총괄 관리자 권한이 필요합니다." }, 403);
    }

    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const name = String(body.name ?? "").trim();
    const phone = String(body.phone ?? "").trim();
    const company = String(body.company ?? "").trim();
    const role = String(body.role ?? "member");

    if (!email || !email.includes("@")) {
      return json({ error: "올바른 이메일을 입력해 주세요." }, 400);
    }
    if (!name) {
      return json({ error: "이름을 입력해 주세요." }, 400);
    }
    if (!["member", "staff", "partner", "admin"].includes(role)) {
      return json({ error: "잘못된 권한입니다." }, 400);
    }

    // 총괄 관리자가 만드는 계정은 가입 시 별도 이메일 확인 없이
    // 바로 사용할 수 있도록 Supabase Auth에서는 confirmed 처리합니다.
    // 실제 이메일 소유 확인 여부는 profiles.email_ownership_verified_at으로
    // 별도 관리하며, 사용자가 암호 변경 시 이메일 OTP를 완료하면 기록됩니다.
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: name,
        phone,
        company,
        requested_role: role,
        role,
        created_by_admin: true,
      },
    });

    if (error) return json({ error: error.message }, 400);
    if (!data.user) {
      return json({ error: "Auth 사용자를 생성하지 못했습니다." }, 400);
    }

    const { error: updateError } = await admin.from("profiles").upsert({
      id: data.user.id,
      email: data.user.email ?? email,
      name,
      phone,
      company,
      role,
      requested_role: role,
      approval_status: "approved",
      email_ownership_verified_at: null,
      updated_at: new Date().toISOString(),
    });

    if (updateError) {
      await admin.auth.admin.deleteUser(data.user.id);
      return json({ error: updateError.message }, 400);
    }

    return json({
      id: data.user.id,
      email_verification_required_on_password_change: true,
    });
  } catch (error) {
    return json(
      { error: String((error as { message?: unknown })?.message ?? error) },
      400,
    );
  }
});
