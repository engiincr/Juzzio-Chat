// =============================================================================
// JUZZIO — Supabase Edge Function: auth-username-login
// Kullanıcı adı (veya e-posta) + şifre ile giriş. E-posta adresi istemciye HİÇ
// gönderilmez: sunucu kullanıcı adını e-postaya çevirir, Supabase Auth ile giriş
// yapar ve yalnızca oturum belirteçlerini döndürür. (Eski sürümde herkes, herhangi
// bir kullanıcı adının e-postasını öğrenebiliyordu.)
//
// Gerekli Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
// (Supabase bunları Edge Functions'a otomatik verir.)
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { adminClient, clientIp, corsHeaders, jsonResponse, keyToUuid, rateLimit, requiredEnv, sleep } from "../_shared/auth.ts";

const GENERIC_ERROR = "invalid_credentials";
// v0.9.0 (G10): Başarısız her yanıt en az bu kadar sürer (+ rastgele sapma). Önceden kullanıcı
// adı bulunamadığında yanıt anında dönüyor, bulunduğunda Auth çağrısı kadar gecikiyordu;
// bu süre farkı kullanıcı adının varlığını sızdırıyordu.
const MIN_FAILURE_MS = 900;
const JITTER_MS = 250;

async function padTiming(startedAt: number): Promise<void> {
  const target = MIN_FAILURE_MS + Math.floor(Math.random() * JITTER_MS);
  const elapsed = Date.now() - startedAt;
  if (elapsed < target) await sleep(target - elapsed);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);

  const startedAt = Date.now();
  const fail = async (error: string, status: number): Promise<Response> => {
    await padTiming(startedAt);
    return jsonResponse({ ok: false, error }, status);
  };
  try {
    // Giriş öncesi uç nokta: IP başına sınır (ham IP saklanmaz, yalnız tuzlu özet)
    if (!(await rateLimit(await keyToUuid(clientIp(req)), "username_login", 60, 300, true))) {
      return await fail("rate_limited", 429);
    }
    const contentLength = Number(req.headers.get("content-length") ?? "0");
    if (contentLength > 4096) return jsonResponse({ ok: false, error: "payload_too_large" }, 413);

    const body = await req.json().catch(() => ({}));
    const login = String(body?.login ?? "").trim();
    const password = String(body?.password ?? "");
    if (!login || !password || login.length > 254 || password.length > 256) {
      return await fail(GENERIC_ERROR, 400);
    }

    let email = "";
    if (login.includes("@") && !login.startsWith("@")) {
      email = login.toLowerCase();
    } else {
      const { data, error } = await adminClient().rpc("resolve_email_by_username", { p_username: login });
      if (error) {
        console.error("username_lookup_failed", { code: error.code ?? "unknown" });
        return await fail("server_error", 500);
      }
      email = String(data ?? "").trim();
    }
    // Kullanıcı bulunamasa da aynı hata döner (kullanıcı adı varlığı sızdırılmaz)
    if (!email) return await fail(GENERIC_ERROR, 401);

    const anon = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: signIn, error: signErr } = await anon.auth.signInWithPassword({ email, password });
    if (signErr || !signIn?.session) {
      // v0.9.0 (G10): "e-posta onaylanmadı" ayrı bir kod olarak DÖNDÜRÜLMEZ; tüm kimlik
      // hataları aynı genel kodu ve aynı süreyi paylaşır (hesap varlığı ayırt edilemez).
      const msg = String(signErr?.message ?? "").toLowerCase();
      const code = msg.includes("rate") ? "rate_limited" : GENERIC_ERROR;
      return await fail(code, code === "rate_limited" ? 429 : 401);
    }

    return jsonResponse({
      ok: true,
      access_token: signIn.session.access_token,
      refresh_token: signIn.session.refresh_token,
      user_id: signIn.user?.id ?? "",
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    if (message.startsWith("missing_secret:")) return await fail("service_not_configured", 500);
    console.error("auth_username_login_failed", { message });
    return await fail("server_error", 500);
  }
});
