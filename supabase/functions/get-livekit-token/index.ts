// =============================================================================
// JUZZIO - Supabase Edge Function: get-livekit-token
// - Yalnızca oturum açmış kullanıcıya ve yalnızca üyesi olduğu / davet edildiği
//   LiveKit odası için kısa ömürlü token üretir.
// - Kimlik (identity) istemciden değil, doğrulanmış JWT'den alınır.
// - LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET yalnızca Supabase Secrets'tan okunur.
// =============================================================================

import { adminClient, corsHeaders, jsonResponse, requiredEnv, requireUser } from "../_shared/auth.ts";

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function generateLiveKitJWT(params: {
  apiKey: string;
  apiSecret: string;
  identity: string;
  name: string;
  roomName: string;
  lang: string;
}): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: params.apiKey,
    sub: params.identity,
    nbf: now - 10,
    exp: now + 60 * 60 * 4, // 4 saat
    name: params.name,
    metadata: JSON.stringify({ preferred_lang: params.lang }),
    video: {
      room: params.roomName,
      roomJoin: true,
      roomCreate: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canUpdateOwnMetadata: true,
    },
  };

  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(params.apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

/** LiveKit sunucu API'si (Twirp) için kısa ömürlü yönetici JWT'si: yalnız tek odada roomAdmin. */
async function generateRoomAdminJWT(apiKey: string, apiSecret: string, roomName: string): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: apiKey,
    sub: "juzzio-server",
    nbf: now - 10,
    exp: now + 120,
    video: { room: roomName, roomAdmin: true },
  };
  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function liveKitHttpBase(wsUrl: string): string {
  const trimmed = wsUrl.trim().replace(/\/+$/, "");
  if (trimmed.startsWith("wss://")) return `https://${trimmed.slice(6)}`;
  if (trimmed.startsWith("ws://")) return `http://${trimmed.slice(5)}`;
  return trimmed;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Konferanstan katılımcı çıkarma. Yetki veritabanında doğrulanır
 * (juzzio_remove_call_participant: host veya grup owner/admin). Ardından LiveKit
 * RoomService/RemoveParticipant ile kişinin bağlantısı sunucu tarafında kesilir.
 */
async function removeParticipant(userId: string, body: Record<string, unknown>): Promise<Response> {
  const roomName = String(body.roomName ?? "").trim();
  const targetIdentity = String(body.targetIdentity ?? "").trim();
  const targetUserId = String(body.targetUserId ?? targetIdentity.slice(0, 36)).trim();
  if (!roomName || roomName.length > 128) return jsonResponse({ error: "room_name_required" }, 400);
  if (!UUID_RE.test(targetUserId)) return jsonResponse({ error: "invalid_target" }, 400);
  if (targetIdentity && !targetIdentity.startsWith(targetUserId)) {
    return jsonResponse({ error: "invalid_target" }, 400);
  }

  const admin = adminClient();
  const { data: result, error } = await admin.rpc("juzzio_remove_call_participant", {
    p_actor: userId,
    p_livekit_room: roomName,
    p_target: targetUserId,
  });
  if (error) {
    console.error("juzzio_remove_call_participant failed", error.code);
    return jsonResponse({ error: "remove_check_failed" }, 500);
  }
  const outcome = (result ?? {}) as { ok?: boolean; error?: string };
  if (outcome.ok !== true) {
    const code = String(outcome.error ?? "forbidden");
    return jsonResponse({ error: code }, code === "forbidden" ? 403 : 409);
  }

  const apiKey = requiredEnv("LIVEKIT_API_KEY");
  const apiSecret = requiredEnv("LIVEKIT_API_SECRET");
  const base = liveKitHttpBase(requiredEnv("LIVEKIT_URL"));
  const jwt = await generateRoomAdminJWT(apiKey, apiSecret, roomName);
  const headers = { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" };

  // Kimlik `${userId}_${lang}` biçimindedir; istemcinin gördüğü kimlik yoksa odadaki eşleşmeler bulunur
  let identities: string[] = targetIdentity ? [targetIdentity] : [];
  if (identities.length === 0) {
    try {
      const listRes = await fetch(`${base}/twirp/livekit.RoomService/ListParticipants`, {
        method: "POST",
        headers,
        body: JSON.stringify({ room: roomName }),
      });
      if (listRes.ok) {
        const listed = await listRes.json().catch(() => ({}));
        const participants = Array.isArray(listed?.participants) ? listed.participants : [];
        identities = participants
          .map((p: { identity?: string }) => String(p?.identity ?? ""))
          .filter((id: string) => id === targetUserId || id.startsWith(`${targetUserId}_`));
      }
    } catch (_) {
      // Liste alınamazsa veritabanı kaydı yine de yeniden katılımı engeller
    }
  }

  let disconnected = 0;
  for (const identity of identities) {
    try {
      const res = await fetch(`${base}/twirp/livekit.RoomService/RemoveParticipant`, {
        method: "POST",
        headers,
        body: JSON.stringify({ room: roomName, identity }),
      });
      if (res.ok) disconnected++;
      else await res.body?.cancel();
    } catch (_) {
      // ağ hatası: kayıt engeli geçerlidir, istemci de ayrılma sinyali alır
    }
  }
  return jsonResponse({ ok: true, removed: targetUserId, disconnected });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  try {
    const user = await requireUser(req);
    if (!user) return jsonResponse({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    if (String(body.action ?? "") === "remove_participant") {
      return await removeParticipant(user.id, body);
    }
    const roomName = String(body.roomName ?? "").trim();
    const lang = String(body.lang ?? "tr").trim().toLowerCase().slice(0, 8) || "tr";
    if (!roomName || roomName.length > 128) {
      return jsonResponse({ error: "room_name_required" }, 400);
    }

    const admin = adminClient();
    const { data: allowed, error: allowErr } = await admin.rpc("can_join_livekit_room", {
      p_user: user.id,
      p_livekit_room: roomName,
    });
    if (allowErr) {
      console.error("can_join_livekit_room failed", allowErr.code);
      return jsonResponse({ error: "membership_check_failed" }, 500);
    }
    if (allowed !== true) {
      return jsonResponse({ error: "forbidden_room" }, 403);
    }

    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, username")
      .eq("id", user.id)
      .maybeSingle();
    const displayName = String(profile?.display_name || profile?.username || body.displayName || "Juzzio").slice(0, 64);

    const token = await generateLiveKitJWT({
      apiKey: requiredEnv("LIVEKIT_API_KEY"),
      apiSecret: requiredEnv("LIVEKIT_API_SECRET"),
      identity: `${user.id}_${lang}`,
      name: displayName,
      roomName,
      lang,
    });

    return jsonResponse({
      token,
      wsUrl: requiredEnv("LIVEKIT_URL"),
      roomName,
      identity: `${user.id}_${lang}`,
      lang,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    console.error("get-livekit-token error", message);
    return jsonResponse({ error: message.startsWith("missing_secret:") ? message : "token_generation_failed" }, 500);
  }
});
