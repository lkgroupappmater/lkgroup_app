import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) throw new Error("로그인이 필요합니다.");

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: caller },
      error: callerError,
    } = await userClient.auth.getUser();
    if (callerError || !caller) throw new Error("로그인 사용자를 확인할 수 없습니다.");

    const admin = createClient(url, serviceRoleKey);
    const { data: callerProfile, error: profileError } = await admin
      .from("profiles")
      .select("role,approval_status")
      .eq("id", caller.id)
      .single();

    if (profileError ||
        callerProfile?.role !== "admin" ||
        callerProfile?.approval_status !== "approved") {
      return new Response(JSON.stringify({ error: "총괄 관리자 권한이 필요합니다." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const role = String(body.role ?? "member");
    if (!["member", "staff", "partner", "admin"].includes(role)) {
      throw new Error("잘못된 권한입니다.");
    }

    const { data, error } = await admin.auth.admin.createUser({
      email: String(body.email ?? "").trim(),
      password: String(body.password ?? ""),
      email_confirm: true,
      user_metadata: {
        full_name: String(body.name ?? "").trim(),
        phone: String(body.phone ?? "").trim(),
        company: String(body.company ?? "").trim(),
        requested_role: role,
        role,
      },
    });

    if (error) throw error;
    if (!data.user) throw new Error("Auth 사용자를 생성하지 못했습니다.");

    const { error: updateError } = await admin.from("profiles").upsert({
      id: data.user.id,
      email: data.user.email ?? String(body.email ?? "").trim(),
      name: String(body.name ?? "").trim(),
      phone: String(body.phone ?? "").trim(),
      company: String(body.company ?? "").trim(),
      role,
      requested_role: role,
      approval_status: "approved",
      updated_at: new Date().toISOString(),
    });

    if (updateError) {
      await admin.auth.admin.deleteUser(data.user.id);
      throw updateError;
    }

    return new Response(JSON.stringify({ id: data.user.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error?.message ?? error) }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
