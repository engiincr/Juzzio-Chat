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
