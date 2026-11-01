// =============================================================================
// JUZZIO - Supabase Edge Function: translate-bridge
//  mode = 'text'           → metin çevirisi
//  mode = 'voice_note'     → Storage'daki sesli mesajı Deepgram ile yazıya döker ve çevirir
//  mode = 'deepgram_token' → canlı altyazı için kısa ömürlü Deepgram erişim token'ı verir
//  mode = 'content'        → (v0.5) Küresel akış gönderi/yorum toplu çevirisi + sunucu önbelleği.
//                             Orijinal metin kullanıcının kendi oturumuyla (RLS) okunur; çeviri
//                             (tür, içerik, dil, metin karması) anahtarıyla content_translations'a
//                             yazılır, böylece aynı içerik her okuyucu için yeniden çevrilmez.
// Deepgram anahtarı yalnızca Supabase Secrets (DEEPGRAM_API_KEY) içinde tutulur;
// mobil uygulamaya hiçbir zaman gömülmez.
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { adminClient, corsHeaders, jsonResponse, requiredEnv, requireUser } from "../_shared/auth.ts";

/** Çeviri; başarısızsa null döner (orijinali çeviri gibi göstermemek için). */
async function translateOrNull(
  text: string,
  sourceLang: string,
  targetLang: string,
): Promise<{ text: string; detected: string } | null> {
  const clean = text.trim();
  if (!clean) return null;
  try {
    const url =
      `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${encodeURIComponent(sourceLang)}` +
      `&tl=${encodeURIComponent(targetLang)}&dt=t&q=${encodeURIComponent(clean)}`;
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data) && Array.isArray(data[0])) {
        const joined = data[0]
          .map((segment: unknown[]) => (segment && segment[0] ? String(segment[0]) : ""))
          .join("")
          .trim();
        const detected = typeof data[2] === "string" ? String(data[2]).toLowerCase() : sourceLang;
        if (joined.length > 0) return { text: joined, detected };
      }
    }
  } catch (_) {
    // başarısız
  }
  return null;
}

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Gönderi / yorum toplu çevirisi (önbellekli). */
async function translateContent(req: Request, body: Record<string, unknown>) {
  const kind = String(body.kind ?? "post") === "comment" ? "comment" : "post";
  const targetLang = String(body.targetLang ?? "").toLowerCase().slice(0, 8);
  if (!/^[a-z]{2,3}(-[a-z0-9]{2,4})?$/.test(targetLang)) return jsonResponse({ error: "bad_target_lang" }, 400);
  const ids = (Array.isArray(body.ids) ? body.ids : [])
    .map((x) => String(x))
    .filter((x) => UUID_RE.test(x))
    .slice(0, 40);
  if (ids.length === 0) return jsonResponse({ translations: {} });

  // Orijinal metin kullanıcının kendi yetkisiyle okunur (görmediği içeriği çeviremez)
  const userClient = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false },
    global: { headers: { Authorization: req.headers.get("authorization") ?? "" } },
  });
  const table = kind === "post" ? "posts" : "post_comments";
  const col = kind === "post" ? "caption" : "content";
  const { data: rows, error } = await userClient.from(table).select(`id, ${col}`).in("id", ids);
  if (error) return jsonResponse({ error: "content_read_failed" }, 500);

  const originals = new Map<string, { text: string; hash: string }>();
  for (const r of (rows ?? []) as Record<string, unknown>[]) {
    const text = String(r[col] ?? "").trim();
    if (text) originals.set(String(r.id), { text, hash: await sha256Hex(text) });
  }
  const admin = adminClient();
  const out: Record<string, { text: string; sourceLang: string; ok: boolean }> = {};
  let hits = 0;
  let failures = 0;

  if (originals.size > 0) {
    const { data: cached } = await admin
      .from("content_translations")
      .select("content_id, source_hash, translated_text, source_lang")
      .eq("kind", kind)
      .eq("target_lang", targetLang)
      .in("content_id", [...originals.keys()]);
    for (const c of (cached ?? []) as Record<string, unknown>[]) {
      const id = String(c.content_id);
      const o = originals.get(id);
      if (o && o.hash === String(c.source_hash)) {
        out[id] = { text: String(c.translated_text), sourceLang: String(c.source_lang), ok: true };
        hits++;
      }
    }
    const misses = [...originals.entries()].filter(([id]) => !out[id]);
    const upserts: Record<string, unknown>[] = [];
    // Sağlayıcıyı boğmamak için 5'li gruplar
    for (let i = 0; i < misses.length; i += 5) {
      const chunk = misses.slice(i, i + 5);
      const results = await Promise.all(chunk.map(([, o]) => translateOrNull(o.text, "auto", targetLang)));
      chunk.forEach(([id, o], k) => {
        const r = results[k];
        if (!r) {
          failures++;
          out[id] = { text: o.text, sourceLang: "auto", ok: false };
          return;
        }
        out[id] = { text: r.text, sourceLang: r.detected, ok: true };
        upserts.push({
          kind,
          content_id: id,
          target_lang: targetLang,
          source_hash: o.hash,
          source_lang: r.detected,
          translated_text: r.text,
          provider: "gtx",
          created_at: new Date().toISOString(),
        });
      });
    }
    if (upserts.length > 0) {
      await admin.from("content_translations").upsert(upserts, { onConflict: "kind,content_id,target_lang" });
    }
  }
  try {
    await admin.rpc("bump_translation_usage", {
      p_kind: kind,
      p_requests: originals.size,
      p_hits: hits,
      p_failures: failures,
    });
  } catch (_) {
    // ölçüm hatası çeviriyi engellemez
  }
  return jsonResponse({ kind, targetLang, translations: out });
}

async function translateFast(text: string, sourceLang: string, targetLang: string): Promise<string> {
  const clean = text.trim();
  if (!clean) return "";
  if (sourceLang !== "auto" && sourceLang === targetLang) return clean;

  try {
    const url =
      `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${encodeURIComponent(sourceLang)}` +
      `&tl=${encodeURIComponent(targetLang)}&dt=t&q=${encodeURIComponent(clean)}`;
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data) && Array.isArray(data[0])) {
        const joined = data[0]
          .map((segment: unknown[]) => (segment && segment[0] ? String(segment[0]) : ""))
          .join("")
          .trim();
        if (joined.length > 0) return joined;
      }
    }
  } catch (_) {
    // yedek servise geç
  }

  try {
    const pair = `${sourceLang === "auto" ? "tr" : sourceLang}|${targetLang}`;
    const res = await fetch(
      `https://api.mymemory.translated.net/get?q=${encodeURIComponent(clean)}&langpair=${encodeURIComponent(pair)}`,
    );
    if (res.ok) {
      const json = await res.json();
      if (json?.responseData?.translatedText) return String(json.responseData.translatedText);
    }
  } catch (_) {
    // orijinal metni döndür
  }
  return clean;
}

async function transcribeWithDeepgram(audioUrl: string, lang: string) {
  const dgLang = lang === "tr" ? "tr" : (lang === "en" ? "en-US" : lang);
  const res = await fetch(
    `https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&punctuate=true&language=${encodeURIComponent(dgLang)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Token ${requiredEnv("DEEPGRAM_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url: audioUrl }),
    },
  );
  if (!res.ok) {
    throw new Error(`deepgram_stt_failed_${res.status}`);
  }
  const result = await res.json();
  const alt = result?.results?.channels?.[0]?.alternatives?.[0];
  return {
    transcript: String(alt?.transcript ?? "").trim(),
    confidence: Number(alt?.confidence ?? 0),
  };
}

async function grantDeepgramToken(): Promise<{ accessToken: string; expiresIn: number }> {
  const res = await fetch("https://api.deepgram.com/v1/auth/grant", {
    method: "POST",
    headers: {
      Authorization: `Token ${requiredEnv("DEEPGRAM_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ ttl_seconds: 120 }),
  });
  if (!res.ok) {
    throw new Error(`deepgram_grant_failed_${res.status}`);
  }
  const json = await res.json();
  return { accessToken: String(json.access_token ?? ""), expiresIn: Number(json.expires_in ?? 0) };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const user = await requireUser(req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const mode = String(body.mode ?? "text");
    const sourceLang = String(body.sourceLang ?? "auto").toLowerCase();
    const targetLang = String(body.targetLang ?? (sourceLang === "tr" ? "en" : "tr")).toLowerCase();

    if (mode === "deepgram_token") {
      const grant = await grantDeepgramToken();
      if (!grant.accessToken) return jsonResponse({ error: "deepgram_grant_empty" }, 502);
      return jsonResponse({ accessToken: grant.accessToken, expiresIn: grant.expiresIn });
    }

    if (mode === "content") {
      return await translateContent(req, body as Record<string, unknown>);
    }

    if (mode === "voice_note") {
      const audioUrl = String(body.audioUrl ?? "");
      const supabaseUrl = requiredEnv("SUPABASE_URL");
      if (!audioUrl.startsWith(`${supabaseUrl}/storage/v1/object/public/`)) {
        return jsonResponse({ error: "audio_url_must_be_project_storage" }, 400);
      }
      const { transcript, confidence } = await transcribeWithDeepgram(audioUrl, sourceLang === "auto" ? "tr" : sourceLang);
      const translatedText = transcript ? await translateFast(transcript, sourceLang, targetLang) : "";
      return jsonResponse({ mode, sourceLang, targetLang, originalText: transcript, translatedText, confidence });
    }

    const text = String(body.text ?? "").slice(0, 5000);
    const translatedText = await translateFast(text, sourceLang, targetLang);
    return jsonResponse({ mode: "text", sourceLang, targetLang, originalText: text, translatedText });
  } catch (error) {
    const message = error instanceof Error ? error.message : "translation_bridge_error";
    console.error("translate-bridge error", message);
    return jsonResponse({ error: message }, 500);
  }
});
