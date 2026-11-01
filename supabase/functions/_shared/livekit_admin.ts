// =============================================================================
// JUZZIO — LiveKit sunucu API'si (Twirp) yardımcıları: katılımcı çıkarma, oda kapatma
// =============================================================================

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function roomAdminJwt(apiKey: string, apiSecret: string, roomName: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    iss: apiKey,
    sub: "juzzio-moderation",
    nbf: now - 10,
    exp: now + 120,
    video: { room: roomName, roomAdmin: true, roomCreate: true },
  };
  const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

function httpBase(wsUrl: string): string {
  const t = wsUrl.trim().replace(/\/+$/, "");
  if (t.startsWith("wss://")) return `https://${t.slice(6)}`;
  if (t.startsWith("ws://")) return `http://${t.slice(5)}`;
  return t;
}

function liveKitEnv(): { key: string; secret: string; base: string } | null {
  const key = (Deno.env.get("LIVEKIT_API_KEY") ?? "").trim();
  const secret = (Deno.env.get("LIVEKIT_API_SECRET") ?? "").trim();
  const url = (Deno.env.get("LIVEKIT_URL") ?? "").trim();
  if (!key || !secret || !url) return null;
  return { key, secret, base: httpBase(url) };
}

async function twirp(method: string, roomName: string, body: Record<string, unknown>): Promise<Response | null> {
  const env = liveKitEnv();
  if (!env) return null;
  const jwt = await roomAdminJwt(env.key, env.secret, roomName);
  return await fetch(`${env.base}/twirp/livekit.RoomService/${method}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

/** Kullanıcının odadaki tüm kimliklerini (`<uuid>_<dil>`) çıkarır; çıkarılan sayısını döndürür. */
export async function removeUserFromRoom(roomName: string, userId: string): Promise<number> {
  let removed = 0;
  try {
    const list = await twirp("ListParticipants", roomName, { room: roomName });
    if (!list || !list.ok) {
      await list?.body?.cancel();
      return 0;
    }
    const json = await list.json().catch(() => ({}));
    const participants = Array.isArray(json?.participants) ? json.participants : [];
    for (const p of participants) {
      const identity = String(p?.identity ?? "");
      if (identity !== userId && !identity.startsWith(`${userId}_`)) continue;
      const res = await twirp("RemoveParticipant", roomName, { room: roomName, identity });
      if (res?.ok) removed++;
      else await res?.body?.cancel();
    }
  } catch (_) {
    // ağ hatası: veritabanı kaydı yeniden katılımı yine engeller
  }
  return removed;
}

/** Odayı herkes için kapatır (birebir aramalarda ihlal anında arama iptal edilir). */
export async function deleteRoom(roomName: string): Promise<boolean> {
  try {
    const res = await twirp("DeleteRoom", roomName, { room: roomName });
    const ok = !!res?.ok;
    if (res && !ok) await res.body?.cancel();
    return ok;
  } catch (_) {
    return false;
  }
}
