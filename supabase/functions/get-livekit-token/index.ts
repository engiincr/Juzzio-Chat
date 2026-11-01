// =============================================================================
// JUZZIO - Supabase Edge Function: get-livekit-token
// - Yalnızca oturum açmış kullanıcıya ve yalnızca üyesi olduğu / davet edildiği
//   LiveKit odası için kısa ömürlü token üretir.
// - Kimlik (identity) istemciden değil, doğrulanmış JWT'den alınır.
// - LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET yalnızca Supabase Secrets'tan okunur.
// =============================================================================

import { adminClient, corsHeaders, isUuid, jsonResponse, rateLimit, requiredEnv, requireUser } from "../_shared/auth.ts";
import { listUserIdentities, participantJwt, removeIdentities } from "../_shared/livekit_admin.ts";

// v0.9.0 (G11): JWT imzalama ve LiveKit HTTP adres çözümü _shared/livekit_admin.ts'de
// tek yerde; bu dosyadaki kopya generateRoomAdminJWT / liveKitHttpBase kaldırıldı.

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
  if (!isUuid(targetUserId)) return jsonResponse({ error: "invalid_target" }, 400);
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

  // Kimlik `${userId}_${lang}` biçimindedir; istemcinin gördüğü kimlik yoksa odadaki eşleşmeler bulunur
  const identities = targetIdentity ? [targetIdentity] : await listUserIdentities(roomName, targetUserId);
  const disconnected = await removeIdentities(roomName, identities);
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
    const rawLang = String(body.lang ?? "tr").trim().toLowerCase().slice(0, 8);
    // Kimlik ve meta veriye giren dil kodu yalnızca güvenli karakterlerden oluşur
    const lang = /^[a-z]{2,3}(-[a-z0-9]{2,4})?$/.test(rawLang) ? rawLang : "tr";
    if (!roomName || roomName.length > 128) {
      return jsonResponse({ error: "room_name_required" }, 400);
    }

    if (!(await rateLimit(user.id, "livekit_token", 60, 60))) {
      return jsonResponse({ error: "rate_limited" }, 429);
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

    const token = await participantJwt({
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
