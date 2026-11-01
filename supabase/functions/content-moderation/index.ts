// =============================================================================
// JUZZIO v0.6 — Supabase Edge Function: content-moderation
//  action = "avatar"      : yüklenen profil fotoğrafını müstehcenlik açısından denetler.
//                            Uygunsa onay kaydı yazılır (veritabanı tetikleyicisi yalnızca
//                            onaylı adresi kabul eder); uygunsuzsa dosya silinir, reddedilir.
//  action = "call_frame"  : görüntülü aramada kişinin KENDİ kamerasından alınan küçük kare.
//                            Müstehcen → ihlal + ceza basamağı (1 sa / 4 sa / kalıcı) +
//                            LiveKit bağlantısı kesilir (birebir aramada oda kapatılır).
//  action = "call_speech" : kişinin kendi konuşmasının metni; aynı aramada 2. ağır ifade → ihlal.
// Görüntü sınıflandırma: Google Cloud Vision SafeSearch. Kimlik doğrulama sırasıyla:
//   GOOGLE_VISION_API_KEY  veya  MODERATION_SERVICE_ACCOUNT_JSON  veya  FCM_SERVICE_ACCOUNT_JSON
//   (hizmet hesabının projesinde "Cloud Vision API" etkin olmalıdır).
// Sağlayıcı yoksa görüntü "unchecked" sayılır: profil fotoğrafı yönetici kuyruğuna düşer.
// =============================================================================

import { adminClient, corsHeaders, jsonResponse, requireUser } from "../_shared/auth.ts";
import { getGoogleAccessToken, loadServiceAccount } from "../_shared/google.ts";
import { deleteRoom, removeUserFromRoom } from "../_shared/livekit_admin.ts";

type Likelihood = "UNKNOWN" | "VERY_UNLIKELY" | "UNLIKELY" | "POSSIBLE" | "LIKELY" | "VERY_LIKELY";
const LEVEL: Record<string, number> = {
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
};

interface SafeSearch {
  adult: Likelihood;
  racy: Likelihood;
  violence: Likelihood;
}

interface Classification {
  verdict: "safe" | "nsfw" | "unchecked";
  provider: string;
  scores: Record<string, unknown>;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

async function visionSafeSearch(imageBase64: string): Promise<SafeSearch | null | "unconfigured"> {
  const apiKey = (Deno.env.get("GOOGLE_VISION_API_KEY") ?? "").trim();
  let url = "https://vision.googleapis.com/v1/images:annotate";
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (apiKey) {
    url += `?key=${encodeURIComponent(apiKey)}`;
  } else {
    const sa = loadServiceAccount(["MODERATION_SERVICE_ACCOUNT_JSON", "FCM_SERVICE_ACCOUNT_JSON"]);
    if (!sa) return "unconfigured";
    const token = await getGoogleAccessToken(sa, "https://www.googleapis.com/auth/cloud-vision");
    if (!token) return null;
    headers.Authorization = `Bearer ${token}`;
    headers["x-goog-user-project"] = sa.projectId;
  }
  try {
    const res = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify({
        requests: [{ image: { content: imageBase64 }, features: [{ type: "SAFE_SEARCH_DETECTION" }] }],
      }),
    });
    if (!res.ok) {
      console.error("vision_http_error", res.status);
      await res.body?.cancel();
      return null;
    }
    const json = await res.json();
    const ann = json?.responses?.[0]?.safeSearchAnnotation;
    if (!ann) return null;
    return {
      adult: (ann.adult ?? "UNKNOWN") as Likelihood,
      racy: (ann.racy ?? "UNKNOWN") as Likelihood,
      violence: (ann.violence ?? "UNKNOWN") as Likelihood,
    };
  } catch (e) {
    console.error("vision_error", e instanceof Error ? e.message : "unknown");
    return null;
  }
}

async function classify(imageBase64: string, strict: boolean): Promise<Classification> {
  const ss = await visionSafeSearch(imageBase64);
  if (ss === "unconfigured") return { verdict: "unchecked", provider: "none", scores: {} };
  if (ss === null) return { verdict: "unchecked", provider: "google_vision_error", scores: {} };
  const adult = LEVEL[ss.adult] ?? 0;
  const racy = LEVEL[ss.racy] ?? 0;
  // Çıplaklık / cinsel organ: adult LIKELY ve üzeri. Profil fotoğrafında daha sıkı (racy VERY_LIKELY de red).
  const nsfw = adult >= 4 || (strict && racy >= 5) || (!strict && adult >= 3 && racy >= 5);
  return { verdict: nsfw ? "nsfw" : "safe", provider: "google_vision", scores: { ...ss } };
}

async function settingBool(key: string, fallback: boolean): Promise<boolean> {
  try {
    const { data } = await adminClient().rpc("get_app_config");
    const v = (data ?? {})[key];
    return typeof v === "boolean" ? v : fallback;
  } catch (_) {
    return fallback;
  }
}

/** İhlal sonrası LiveKit yaptırımı: grup aramasında yalnız kişi çıkarılır, birebirde oda kapanır. */
async function enforceInRoom(roomName: string, userId: string): Promise<{ removed: number; roomClosed: boolean }> {
  const admin = adminClient();
  let isGroup = false;
  try {
    const { data } = await admin
      .from("call_logs")
      .select("is_group")
      .eq("livekit_room_name", roomName)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    isGroup = data?.is_group === true;
  } catch (_) {
    // varsayılan: birebir
  }
  if (!isGroup) {
    const closed = await deleteRoom(roomName);
    if (closed) return { removed: 0, roomClosed: true };
  }
  const removed = await removeUserFromRoom(roomName, userId);
  return { removed, roomClosed: false };
}

async function handleAvatar(userId: string, body: Record<string, unknown>): Promise<Response> {
  const admin = adminClient();
  const url = String(body.url ?? "").trim();
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim().replace(/\/+$/, "");
  const marker = `/storage/v1/object/public/avatars/`;
  const idx = url.indexOf(marker);
  if (!url || idx < 0 || url.length > 600) return jsonResponse({ error: "invalid_url" }, 400);
  let host = "";
  let expectedHost = "";
  try {
    host = new URL(url).host;
    expectedHost = new URL(supabaseUrl).host;
  } catch (_) {
    return jsonResponse({ error: "invalid_url" }, 400);
  }
  const objectPath = decodeURIComponent(url.slice(idx + marker.length).split("?")[0]);
  if (host !== expectedHost || !objectPath.startsWith(`${userId}/`)) {
    return jsonResponse({ error: "forbidden_object" }, 403);
  }

  if (!(await settingBool("avatar_moderation_enabled", true))) {
    await admin.from("media_moderation").insert({
      user_id: userId, kind: "avatar", url, verdict: "unchecked", provider: "disabled", review_status: "auto",
    });
    return jsonResponse({ ok: true, verdict: "unchecked" });
  }

  const { data: blob, error: dlErr } = await admin.storage.from("avatars").download(objectPath);
  if (dlErr || !blob) return jsonResponse({ error: "download_failed" }, 404);
  const bytes = new Uint8Array(await blob.arrayBuffer());
  if (bytes.length > 12 * 1024 * 1024) return jsonResponse({ error: "image_too_large" }, 413);

  const result = await classify(bytesToBase64(bytes), true);
  await admin.from("media_moderation").insert({
    user_id: userId,
    kind: "avatar",
    url,
    verdict: result.verdict,
    provider: result.provider,
    scores: result.scores,
    review_status: result.verdict === "unchecked" ? "pending" : "auto",
  });

  if (result.verdict === "nsfw") {
    try {
      await admin.storage.from("avatars").remove([objectPath]);
    } catch (_) {
      // dosya silinemese de profil alanı onaysız kalır
    }
    return jsonResponse({ ok: false, verdict: "nsfw", error: "inappropriate_image" });
  }
  return jsonResponse({ ok: true, verdict: result.verdict });
}

async function canUseRoom(userId: string, roomName: string): Promise<boolean> {
  if (!roomName || roomName.length > 128) return false;
  try {
    const { data } = await adminClient().rpc("can_join_livekit_room", { p_user: userId, p_livekit_room: roomName });
    if (data === true) return true;
    // Bağlıyken engellenmiş olabilir: son 12 saatte bu odada kaydı var mı?
    const { data: row } = await adminClient()
      .from("call_logs")
      .select("id")
      .eq("livekit_room_name", roomName)
      .or(`caller_id.eq.${userId},receiver_id.eq.${userId}`)
      .gte("created_at", new Date(Date.now() - 12 * 3600 * 1000).toISOString())
      .limit(1)
      .maybeSingle();
    return !!row;
  } catch (_) {
    return false;
  }
}

async function handleCallFrame(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomName = String(body.roomName ?? "").trim();
  const image = String(body.image ?? "").trim();
  if (!image || image.length > 2_800_000) return jsonResponse({ error: "invalid_image" }, 400);
  if (!(await settingBool("call_moderation_enabled", true))) return jsonResponse({ ok: true, verdict: "disabled" });
  if (!(await canUseRoom(userId, roomName))) return jsonResponse({ error: "forbidden_room" }, 403);

  const result = await classify(image, false);
  if (result.verdict !== "nsfw") return jsonResponse({ ok: true, verdict: result.verdict });

  const admin = adminClient();
  await admin.from("media_moderation").insert({
    user_id: userId, kind: "call_frame", url: "", verdict: "nsfw", provider: result.provider, scores: result.scores,
  });
  const { data: violation, error } = await admin.rpc("juzzio_record_violation", {
    p_user: userId,
    p_kind: "call_nudity",
    p_detail: "vision",
    p_room: roomName,
  });
  if (error) console.error("record_violation_failed", error.code);
  const enforcement = await enforceInRoom(roomName, userId);
  return jsonResponse({ ok: true, verdict: "nsfw", violation, enforcement });
}

// v0.7.0: Aramalarda küfür/argo serbest — konuşma hiçbir zaman ceza sebebi değildir.
// Yalnızca görüntülü aramada çıplaklık/müstehcen görüntü denetimi sürer (handleCallFrame).
async function handleCallSpeech(_userId: string, _body: Record<string, unknown>): Promise<Response> {
  return jsonResponse({ ok: true, explicit: false, disabled: true });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  try {
    const user = await requireUser(req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    switch (String(body.action ?? "")) {
      case "avatar":
        return await handleAvatar(user.id, body);
      case "call_frame":
        return await handleCallFrame(user.id, body);
      case "call_speech":
        return await handleCallSpeech(user.id, body);
      default:
        return jsonResponse({ error: "invalid_action" }, 400);
    }
  } catch (error) {
    console.error("content-moderation error", error instanceof Error ? error.message : "unknown");
    return jsonResponse({ error: "moderation_failed" }, 500);
  }
});
