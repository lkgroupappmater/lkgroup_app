import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

const sha256 = async (value: string) => {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
};

const makeCode = () => {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return String(100000 + (value[0] % 900000));
};

const tombstoneEmail = (userId: string) =>
  `deleted.${userId}.${Date.now()}@lkgroup.trading`;

const deletionEmailHtml = (code: string) => `
<div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#222">
  <h2 style="margin-bottom:16px">LK Group 회원 탈퇴 인증</h2>
  <p style="font-size:15px;line-height:1.6">LK Group 계정의 회원 탈퇴를 위한 이메일 인증 코드입니다.</p>
  <div style="margin:24px 0;padding:18px;text-align:center;font-size:32px;font-weight:700;letter-spacing:8px;border:1px solid #ddd;border-radius:10px;background:#f7f7f7">${code}</div>
  <p style="font-size:14px;line-height:1.6">LK Group 앱의 <strong>회원 탈퇴 이메일 인증 코드</strong> 입력란에 위 코드를 입력해 주세요.</p>
  <p style="font-size:13px;color:#777;line-height:1.6">본인이 회원 탈퇴를 요청하지 않았다면 인증 코드를 입력하지 말고 이 메일을 무시해 주세요.</p>
  <hr style="margin:28px 0;border:0;border-top:1px solid #eee">
  <p style="font-size:12px;color:#999">LK Group<br>This is an automated email. Please do not reply.</p>
</div>`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "로그인이 필요합니다." }, 401);
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();

    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!url || !serviceKey || !anonKey) {
      return json({ error: "서버 설정이 누락되었습니다." }, 500);
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    const { data: { user: caller }, error: callerError } = await admin.auth.getUser(token);
    if (callerError || !caller) return json({ error: "로그인 사용자를 확인할 수 없습니다." }, 401);

    const body = await req.json();
    const action = String(body.action ?? "");

    const requireTotalAdmin = async () => {
      const { data, error } = await admin.rpc("is_total_admin_user", {
        target_user_id: caller.id,
      });
      if (error) {
        return { ok: false as const, response: json({
          error: "총괄 관리자 권한을 확인할 수 없습니다.",
          detail: error.message,
        }, 403) };
      }
      if (data !== true) {
        return { ok: false as const, response: json({ error: "총괄 관리자 권한이 필요합니다." }, 403) };
      }
      return { ok: true as const };
    };

    if (action === "send_self_delete_code") {
      const email = String(caller.email ?? "").trim().toLowerCase();
      if (!email) return json({ error: "등록된 이메일이 없습니다." }, 400);

      const resendKey = Deno.env.get("RESEND_API_KEY");
      if (!resendKey) {
        return json({ error: "회원 탈퇴 인증메일 서버 설정(RESEND_API_KEY)이 누락되었습니다." }, 500);
      }

      const { data: existing } = await admin
        .from("account_deletion_email_otps")
        .select("sent_at")
        .eq("user_id", caller.id)
        .maybeSingle();

      if (existing?.sent_at) {
        const elapsed = Date.now() - new Date(String(existing.sent_at)).getTime();
        if (Number.isFinite(elapsed) && elapsed >= 0 && elapsed < 60_000) {
          return json({ error: "인증 코드는 60초 후 다시 요청할 수 있습니다." }, 429);
        }
      }

      const code = makeCode();
      const codeHash = await sha256(`${caller.id}:${code}:${serviceKey}`);
      const now = new Date();
      const expiresAt = new Date(now.getTime() + 10 * 60 * 1000);

      const { error: otpError } = await admin.from("account_deletion_email_otps").upsert({
        user_id: caller.id,
        code_hash: codeHash,
        expires_at: expiresAt.toISOString(),
        sent_at: now.toISOString(),
        attempts: 0,
      });
      if (otpError) return json({ error: otpError.message }, 400);

      const mailResponse = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          from: "LK Group <auth@lkgroup.trading>",
          to: [email],
          subject: "[LK Group] 회원 탈퇴 인증 코드",
          html: deletionEmailHtml(code),
        }),
      });

      if (!mailResponse.ok) {
        await admin.from("account_deletion_email_otps").delete().eq("user_id", caller.id);
        const detail = await mailResponse.text();
        return json({ error: "회원 탈퇴 인증메일 발송에 실패했습니다.", detail }, 502);
      }

      return json({ ok: true, expires_in_seconds: 600 });
    }

    if (action === "self_delete") {
      const currentPassword = String(body.current_password ?? "");
      const verificationCode = String(body.verification_code ?? "").trim();
      if (!currentPassword) return json({ error: "본인 암호를 입력해 주세요." }, 400);
      if (!/^\d{6}$/.test(verificationCode)) {
        return json({ error: "6자리 회원 탈퇴 이메일 인증 코드를 입력해 주세요." }, 400);
      }

      const { data: otp, error: otpReadError } = await admin
        .from("account_deletion_email_otps")
        .select("code_hash,expires_at,attempts")
        .eq("user_id", caller.id)
        .maybeSingle();
      if (otpReadError) return json({ error: otpReadError.message }, 400);
      if (!otp) return json({ error: "회원 탈퇴 이메일 인증 코드를 먼저 받아 주세요." }, 400);
      if (new Date(String(otp.expires_at)).getTime() < Date.now()) {
        return json({ error: "회원 탈퇴 이메일 인증 코드가 만료되었습니다. 다시 받아 주세요." }, 400);
      }
      if (Number(otp.attempts ?? 0) >= 5) {
        return json({ error: "인증 코드 입력 횟수를 초과했습니다. 새 인증 코드를 받아 주세요." }, 429);
      }

      const expectedHash = await sha256(`${caller.id}:${verificationCode}:${serviceKey}`);
      if (expectedHash !== String(otp.code_hash)) {
        await admin.from("account_deletion_email_otps").update({
          attempts: Number(otp.attempts ?? 0) + 1,
        }).eq("user_id", caller.id);
        return json({ error: "회원 탈퇴 이메일 인증 코드가 올바르지 않습니다." }, 400);
      }

      const email = String(caller.email ?? "").trim();
      if (!email) return json({ error: "등록된 이메일이 없습니다." }, 400);

      const passwordClient = createClient(url, anonKey, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      });
      const { data: passwordData, error: passwordError } = await passwordClient.auth.signInWithPassword({
        email,
        password: currentPassword,
      });
      if (passwordError || passwordData.user?.id !== caller.id) {
        return json({ error: "본인 암호가 올바르지 않습니다." }, 400);
      }

      const tempEmail = tombstoneEmail(caller.id);
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(caller.id, {
        email: tempEmail,
        email_confirm: true,
        ban_duration: "876000h",
      });
      if (authUpdateError) return json({ error: authUpdateError.message }, 400);

      const { data: result, error: pendingError } = await admin.rpc(
        "mark_member_deletion_pending",
        { target_user_id: caller.id, deletion_kind: "self" },
      );
      if (pendingError) {
        await admin.auth.admin.updateUserById(caller.id, {
          email,
          email_confirm: true,
          ban_duration: "none",
        });
        return json({ error: pendingError.message }, 400);
      }
      return json(result ?? { ok: true });
    }

    if (action === "admin_delete") {
      const authz = await requireTotalAdmin();
      if (!authz.ok) return authz.response;

      const targetId = String(body.user_id ?? "").trim();
      if (!targetId) return json({ error: "삭제할 회원 ID가 없습니다." }, 400);
      if (targetId === caller.id) {
        return json({ error: "현재 로그인한 본인 계정은 회원 관리에서 삭제할 수 없습니다." }, 400);
      }

      const { data: profile, error: profileError } = await admin
        .from("profiles")
        .select("email,deletion_status")
        .eq("id", targetId)
        .maybeSingle();
      if (profileError || !profile) return json({ error: profileError?.message ?? "회원을 찾을 수 없습니다." }, 400);
      if (profile.deletion_status === "pending") return json({ error: "이미 탈퇴 처리 대기 중인 회원입니다." }, 400);

      const originalEmail = String(profile.email ?? "").trim();
      const tempEmail = tombstoneEmail(targetId);
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(targetId, {
        email: tempEmail,
        email_confirm: true,
        ban_duration: "876000h",
      });
      if (authUpdateError) return json({ error: authUpdateError.message }, 400);

      const { data: result, error: pendingError } = await admin.rpc(
        "mark_member_deletion_pending",
        { target_user_id: targetId, deletion_kind: "admin" },
      );
      if (pendingError) {
        if (originalEmail) {
          await admin.auth.admin.updateUserById(targetId, {
            email: originalEmail,
            email_confirm: true,
            ban_duration: "none",
          });
        }
        return json({ error: pendingError.message }, 400);
      }
      return json(result ?? { ok: true });
    }

    if (action === "admin_cancel_delete") {
      const authz = await requireTotalAdmin();
      if (!authz.ok) return authz.response;

      const targetId = String(body.user_id ?? "").trim();
      if (!targetId) return json({ error: "회원 ID가 없습니다." }, 400);
      if (targetId === caller.id) return json({ error: "현재 로그인한 본인 계정은 처리할 수 없습니다." }, 400);

      const { data: profile, error: profileError } = await admin
        .from("profiles")
        .select("email,deletion_status")
        .eq("id", targetId)
        .maybeSingle();
      if (profileError || !profile) return json({ error: profileError?.message ?? "회원을 찾을 수 없습니다." }, 400);
      if (profile.deletion_status !== "pending") return json({ error: "탈퇴 대기 중인 회원이 아닙니다." }, 400);

      const originalEmail = String(profile.email ?? "").trim();
      if (!originalEmail) return json({ error: "복구할 이메일 정보가 없습니다." }, 400);

      const { error: restoreError } = await admin.auth.admin.updateUserById(targetId, {
        email: originalEmail,
        email_confirm: true,
        ban_duration: "none",
      });
      if (restoreError) {
        return json({
          error: "탈퇴 취소에 실패했습니다. 동일 이메일로 이미 새 계정이 가입되어 있는지 확인해 주세요.",
          detail: restoreError.message,
        }, 409);
      }

      const { data: result, error: cancelError } = await admin.rpc(
        "cancel_member_deletion",
        { target_user_id: targetId },
      );
      if (cancelError) return json({ error: cancelError.message }, 400);
      return json(result ?? { ok: true });
    }

    if (action === "admin_confirm_delete") {
      const authz = await requireTotalAdmin();
      if (!authz.ok) return authz.response;

      const targetId = String(body.user_id ?? "").trim();
      if (!targetId) return json({ error: "회원 ID가 없습니다." }, 400);
      if (targetId === caller.id) return json({ error: "현재 로그인한 본인 계정은 처리할 수 없습니다." }, 400);

      const { data: profile, error: profileError } = await admin
        .from("profiles")
        .select("deletion_status")
        .eq("id", targetId)
        .maybeSingle();
      if (profileError || !profile) return json({ error: profileError?.message ?? "회원을 찾을 수 없습니다." }, 400);
      if (profile.deletion_status !== "pending") return json({ error: "탈퇴 대기 중인 회원이 아닙니다." }, 400);

      const { data: result, error: hardDeleteError } = await admin.rpc(
        "hard_delete_member_account",
        { target_user_id: targetId },
      );
      if (hardDeleteError) return json({ error: hardDeleteError.message }, 400);
      return json(result ?? { ok: true });
    }

    return json({ error: "잘못된 요청입니다." }, 400);
  } catch (error) {
    return json({ error: String((error as { message?: unknown })?.message ?? error) }, 400);
  }
});
