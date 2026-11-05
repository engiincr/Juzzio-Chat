// =============================================================================
// JUZZIO - Supabase Edge Function: translate-bridge
//  mode = 'text'           → metin çevirisi
//  mode = 'voice_note'     → Storage'daki sesli mesajı Deepgram ile yazıya döker ve çevirir
//                             v0.9.0 (G04): istemci URL'si yetki DEĞİLDİR; kayıt kimlik/yol ile
//                             veritabanından çözülür, oda üyeliği + yasak + engel denetlenir,
//                             ses dosyası sunucuda (service_role) indirilip Deepgram'a BAYT
//                             olarak gönderilir (özel bucket'ta herkese açık URL yoktur).
//  mode = 'deepgram_token' → canlı altyazı için kısa ömürlü Deepgram erişim token'ı verir
//                             v0.9.0 (G05): yalnızca yasaklı olmayan, ETKİN çağrı katılımcısına.
//  mode = 'batch_ui'       → v0.9.0 (G12): arayüz dil paketi; sunucu önbellekli toplu çeviri
//  mode = 'content'        → (v0.5) Küresel akış gönderi/yorum toplu çevirisi + sunucu önbelleği.
//                             Orijinal metin kullanıcının kendi oturumuyla (RLS) okunur; çeviri
//                             (tür, içerik, dil, metin karması) anahtarıyla content_translations'a
//                             yazılır, böylece aynı içerik her okuyucu için yeniden çevrilmez.
// Deepgram anahtarı yalnızca Supabase Secrets (DEEPGRAM_API_KEY) içinde tutulur;
// mobil uygulamaya hiçbir zaman gömülmez.
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  adminClient,
  corsHeaders,
  isUuid,
  jsonResponse,
  rateLimit,
  requiredEnv,
  requireUser,
  sha256Hex,
  UUID_RE,
} from "../_shared/auth.ts";
import { translateChunked } from "../_shared/translate.ts";

/** Çeviri; başarısızsa null döner (orijinali çeviri gibi göstermemek için).
 *  v0.9.3: uzun metin parçalara bölünür; sağlayıcı hata metni çeviri sayılmaz. */
async function translateOrNull(
  text: string,
  sourceLang: string,
  targetLang: string,
): Promise<{ text: string; detected: string } | null> {
  return await translateChunked(text, sourceLang, targetLang);
}

const LANG_RE = /^[a-z]{2,3}(-[a-z0-9]{2,4})?$/;
const VOICE_MAX_BYTES = 25 * 1024 * 1024;

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
  // v0.9.3: parçalı çeviri; çevrilemezse orijinal (hata metni ASLA döndürülmez)
  const r = await translateChunked(clean, sourceLang, targetLang);
  return r?.text ?? clean;
}

async function transcribeWithDeepgram(audio: ArrayBuffer, mime: string, lang: string) {
  const dgLang = lang === "tr" ? "tr" : (lang === "en" ? "en-US" : lang);
  const res = await fetch(
    `https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true&punctuate=true&language=${encodeURIComponent(dgLang)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Token ${requiredEnv("DEEPGRAM_API_KEY")}`,
        "Content-Type": mime,
      },
      body: audio,
      signal: AbortSignal.timeout(45_000),
    },
  );
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`deepgram_stt_failed_${res.status}`);
  }
  const result = await res.json();
  const alt = result?.results?.channels?.[0]?.alternatives?.[0];
  return {
    transcript: String(alt?.transcript ?? "").trim(),
    confidence: Number(alt?.confidence ?? 0),
  };
}

/** Eski istemcilerin gönderdiği Storage URL'sinden (public/sign/authenticated) yolu çıkarır. */
function voicePathFromLegacyUrl(audioUrl: string, supabaseUrl: string): string | null {
  const base = supabaseUrl.replace(/\/+$/, "");
  for (const kind of ["public", "sign", "authenticated"]) {
    const prefix = `${base}/storage/v1/object/${kind}/voice-notes/`;
    if (audioUrl.startsWith(prefix)) {
      try {
        return decodeURIComponent(audioUrl.slice(prefix.length).split("?")[0]);
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

/** Sesli mesajı yetki denetimiyle çözer, sunucuda indirir ve yazıya döker. */
async function handleVoiceNote(
  userId: string,
  body: Record<string, unknown>,
  sourceLang: string,
  targetLang: string,
): Promise<Response> {
  const voiceNoteId = String(body.voiceNoteId ?? "").trim();
  const messageId = String(body.messageId ?? "").trim();
  let storagePath = String(body.storagePath ?? "").trim();
  if (!storagePath && typeof body.audioUrl === "string") {
    storagePath = voicePathFromLegacyUrl(String(body.audioUrl), requiredEnv("SUPABASE_URL")) ?? "";
  }
  if (!isUuid(voiceNoteId) && !isUuid(messageId) && !storagePath) {
    return jsonResponse({ error: "voice_note_reference_required" }, 400);
  }
  if (storagePath.length > 512 || storagePath.includes("..") || storagePath.startsWith("/")) {
    return jsonResponse({ error: "invalid_path" }, 400);
  }
  if (!(await rateLimit(userId, "voice_transcribe", 20, 600))) return jsonResponse({ error: "rate_limited" }, 429);

  const admin = adminClient();
  const { data: resolved, error } = await admin.rpc("juzzio_voice_note_for_transcription", {
    p_user: userId,
    p_voice_note: isUuid(voiceNoteId) ? voiceNoteId : null,
    p_message: isUuid(messageId) ? messageId : null,
    p_storage_path: storagePath || null,
  });
  if (error) {
    console.error("voice_note_resolve_failed", error.code ?? "unknown");
    return jsonResponse({ error: "voice_note_check_failed" }, 500);
  }
  const r = (resolved ?? {}) as { ok?: boolean; error?: string; storage_path?: string; mime_type?: string };
  if (r.ok !== true || !r.storage_path) {
    const code = String(r.error ?? "forbidden");
    return jsonResponse({ error: code }, code === "not_found" ? 404 : 403);
  }

  const { data: blob, error: dlErr } = await admin.storage.from("voice-notes").download(r.storage_path);
  if (dlErr || !blob) return jsonResponse({ error: "audio_not_found" }, 404);
  if (blob.size > VOICE_MAX_BYTES) return jsonResponse({ error: "audio_too_large" }, 413);
  const mime = String(r.mime_type || blob.type || "audio/mp4").toLowerCase();
  if (!mime.startsWith("audio/")) return jsonResponse({ error: "unsupported_media_type" }, 415);
  const bytes = await blob.arrayBuffer();

  const { transcript, confidence } = await transcribeWithDeepgram(bytes, mime, sourceLang === "auto" ? "tr" : sourceLang);
  const translatedText = transcript ? await translateFast(transcript, sourceLang, targetLang) : "";
  return jsonResponse({ mode: "voice_note", sourceLang, targetLang, originalText: transcript, translatedText, confidence });
}

/**
 * Arayüz dil paketi (G12). İstemci yalnızca UYGULAMA metinlerini (katalog) gönderir; her
 * (hedef dil, metin özeti) sunucuda bir kez çevrilir ve ui_translations'ta herkes için
 * önbelleğe alınır. Sağlayıcıya en fazla 4 eşzamanlı istek gider. Kullanıcı başına sınır vardır.
 */
async function handleBatchUi(userId: string, body: Record<string, unknown>): Promise<Response> {
  const targetLang = String(body.targetLang ?? "").toLowerCase().slice(0, 10);
  if (!LANG_RE.test(targetLang)) return jsonResponse({ error: "bad_target_lang" }, 400);
  const raw = Array.isArray(body.texts) ? body.texts : [];
  if (raw.length > 80) return jsonResponse({ error: "too_many_texts" }, 413);
  const texts = raw.map((t) => String(t ?? "")).filter((t) => t.trim().length > 0 && t.length <= 600);
  if (texts.length === 0) return jsonResponse({ targetLang, translations: {} });
  if (!(await rateLimit(userId, "batch_ui", 60, 600))) return jsonResponse({ error: "rate_limited" }, 429);

  const admin = adminClient();
  const hashes = await Promise.all(texts.map((t) => sha256Hex(t)));
  const byHash = new Map<string, string>();
  texts.forEach((t, i) => byHash.set(hashes[i], t));
  const out: Record<string, string> = {};

  const { data: cached } = await admin
    .from("ui_translations")
    .select("source_hash, translated_text")
    .eq("target_lang", targetLang)
    .in("source_hash", [...byHash.keys()]);
  const cachedRows = (cached ?? []) as { source_hash: string; translated_text: string }[];
  for (const row of cachedRows) {
    out[row.source_hash] = row.translated_text;
  }
  const misses = [...byHash.entries()].filter(([h]) => out[h] === undefined);
  const upserts: Record<string, unknown>[] = [];
  for (let i = 0; i < misses.length; i += 4) {
    const chunk = misses.slice(i, i + 4);
    const results = await Promise.all(chunk.map(([, text]) => translateOrNull(text, "en", targetLang)));
    chunk.forEach(([h], k) => {
      const r = results[k];
      if (!r || r.text.length > 2000) return; // başarısız: istemci İngilizce kaynağı gösterir
      out[h] = r.text;
      upserts.push({ target_lang: targetLang, source_hash: h, translated_text: r.text, provider: "gtx" });
    });
  }
  if (upserts.length > 0) {
    await admin.from("ui_translations").upsert(upserts, { onConflict: "target_lang,source_hash" });
  }
  // Yanıt: kaynak metin → çeviri (eksikler yanıtta yok; istemci yedek yolu kullanır)
  const translations: Record<string, string> = {};
  for (const [h, text] of byHash.entries()) {
    if (out[h] !== undefined) translations[text] = out[h];
  }
  return jsonResponse({ targetLang, translations, cached: cachedRows.length, translated: upserts.length });
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

    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const mode = String(body.mode ?? "text");
    const sourceLang = String(body.sourceLang ?? "auto").toLowerCase();
    const targetLang = String(body.targetLang ?? (sourceLang === "tr" ? "en" : "tr")).toLowerCase();

    if (!LANG_RE.test(targetLang) || (sourceLang !== "auto" && !LANG_RE.test(sourceLang))) {
      return jsonResponse({ error: "bad_lang" }, 400);
    }

    if (mode === "deepgram_token") {
      const { data: allowed, error: capErr } = await adminClient().rpc("juzzio_can_use_live_captions", { p_user: user.id });
      if (capErr) {
        console.error("live_caption_check_failed", capErr.code ?? "unknown");
        return jsonResponse({ error: "caption_check_failed" }, 500);
      }
      if (allowed !== true) return jsonResponse({ error: "no_active_call" }, 403);
      if (!(await rateLimit(user.id, "deepgram_token", 30, 600))) return jsonResponse({ error: "rate_limited" }, 429);
      const grant = await grantDeepgramToken();
      if (!grant.accessToken) return jsonResponse({ error: "deepgram_grant_empty" }, 502);
      return jsonResponse({ accessToken: grant.accessToken, expiresIn: grant.expiresIn });
    }

    if (mode === "content") {
      if (!(await rateLimit(user.id, "content_translate", 120, 600))) return jsonResponse({ error: "rate_limited" }, 429);
      return await translateContent(req, body);
    }

    if (mode === "voice_note") {
      return await handleVoiceNote(user.id, body, sourceLang, targetLang);
    }

    if (mode === "batch_ui") {
      return await handleBatchUi(user.id, body);
    }

    if (mode !== "text") return jsonResponse({ error: "invalid_mode" }, 400);
    if (!(await rateLimit(user.id, "text_translate", 120, 60))) return jsonResponse({ error: "rate_limited" }, 429);
    const text = String(body.text ?? "").slice(0, 5000);
    const translatedText = await translateFast(text, sourceLang, targetLang);
    return jsonResponse({ mode: "text", sourceLang, targetLang, originalText: text, translatedText });
  } catch (error) {
    const message = error instanceof Error ? error.message : "translation_bridge_error";
    console.error("translate-bridge error", message);
    // İç hata ayrıntısı istemciye sızdırılmaz; yalnızca kararlı bir kod döner
    const code = message.startsWith("missing_secret:") ? "service_not_configured"
      : message.startsWith("deepgram_") ? "transcription_failed" : "translation_bridge_error";
    return jsonResponse({ error: code }, 500);
  }
});
