// =============================================================================
// JUZZIO — Edge Function ortak yardımcıları: CORS, JSON yanıt ve kullanıcı doğrulama
// Gizli anahtarlar YALNIZCA Supabase Secrets (Deno.env) üzerinden okunur.
// =============================================================================

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function requiredEnv(name: string): string {
  const value = (Deno.env.get(name) ?? "").trim();
  if (!value) {
    throw new Error(`missing_secret:${name}`);
  }
  return value;
}

export function adminClient(): SupabaseClient {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false },
  });
}

/** Authorization: Bearer <kullanıcı JWT> başlığını doğrular ve kullanıcı kimliğini döndürür. */
export async function requireUser(req: Request): Promise<{ id: string; email?: string } | null> {
  const authHeader = (req.headers.get("authorization") ?? "").trim();
  if (!authHeader.toLowerCase().startsWith("bearer ")) return null;
  const token = authHeader.slice(7).trim();
  if (!token) return null;
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data?.user?.id) return null;
  return { id: data.user.id, email: data.user.email ?? undefined };
}

// =============================================================================
// v0.9.0 ortak güvenlik yardımcıları (G03, G10, G04/G05 hız sınırı)
// =============================================================================

/** Kanonik UUID biçimi. Kullanıcı girdisi bir sorguya (özellikle .or() filtresine)
 *  girmeden önce DAİMA bununla doğrulanır; PostgREST filtre enjeksiyonu engellenir. */
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

/** Uzunluktan bağımsız, sabit zamanlı dize karşılaştırması (webhook gizlisi vb.). */
export function constantTimeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  const len = Math.max(ea.length, eb.length);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < len; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Kimliği olmayan çağıranlar (ör. giriş öncesi IP) için hız sınırı anahtarını UUID'ye
 *  çevirir. Ham IP saklanmaz: yalnızca tuzlu SHA-256 özetinin ilk 128 biti. */
export async function keyToUuid(key: string): Promise<string> {
  const h = await sha256Hex(`juzzio-rate:${key}`);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/** Sunucu tarafı hız sınırı (juzzio_rate_check). Veritabanı hatasında varsayılan olarak
 *  güvenli tarafta kalınır: istek REDDEDİLİR (maliyetli sağlayıcı çağrıları kötüye
 *  kullanılamasın). `failOpen` yalnızca kendi ek koruması olan uç noktalar içindir
 *  (ör. giriş: Supabase Auth'un kendi hız sınırı vardır; altyapı hatası herkesi kilitlemesin). */
export async function rateLimit(
  userId: string,
  action: string,
  limit: number,
  windowSeconds: number,
  failOpen = false,
): Promise<boolean> {
  try {
    const { data, error } = await adminClient().rpc("juzzio_rate_check", {
      p_user: userId,
      p_action: action,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.error("rate_check_failed", error.code ?? "unknown");
      return failOpen;
    }
    return data === true;
  } catch (_) {
    return failOpen;
  }
}

/**
 * v0.9.6: Kullanıcı başına günlük AI (çeviri/döküm) kotası. Kota yönetici panelinden
 * `ai_daily_quota_per_user` ayarıyla belirlenir (0 = sınırsız). Maliyet koruması olduğu
 * için veritabanı hatasında AÇIK kalır (çeviri kesilmez); güvenlik sınırı değildir.
 */
export async function aiQuotaTake(userId: string, kind: string, units = 1): Promise<boolean> {
  try {
    const { data, error } = await adminClient().rpc("juzzio_ai_quota_take", {
      p_user: userId,
      p_kind: kind,
      p_units: units,
    });
    if (error) {
      console.error("ai_quota_check_failed", error.code ?? "unknown");
      return true;
    }
    return data !== false;
  } catch (_) {
    return true;
  }
}

export function clientIp(req: Request): string {
  const fwd = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  return fwd || (req.headers.get("cf-connecting-ip") ?? "").trim() || "unknown";
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
