// =============================================================================
// JUZZIO — LiveKit ortak modülü: erişim token'ı, oda yöneticisi JWT'si, sunucu API'si
// (Twirp) yardımcıları — katılımcı listeleme/çıkarma, oda kapatma.
// v0.9.0 (G11): get-livekit-token içindeki kopya JWT/HTTP kodu buraya taşındı; tüm
// fonksiyonlar tek bir imzalama ve adres çözümleme yolunu kullanır.
// =============================================================================

export function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** HS256 ile LiveKit JWT imzalar (tek imzalama yolu). */
export async function signLiveKitJwt(apiSecret: string, payload: Record<string, unknown>): Promise<string> {
  const header = { alg: "HS256", typ: "JWT" };
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

/** Sunucu API'si için kısa ömürlü (120 sn), yalnız tek odada geçerli yönetici JWT'si. */
export async function roomAdminJwt(apiKey: string, apiSecret: string, roomName: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await signLiveKitJwt(apiSecret, {
    iss: apiKey,
    sub: "juzzio-server",
    nbf: now - 10,
    exp: now + 120,
    video: { room: roomName, roomAdmin: true, roomCreate: true },
  });
}

/** Katılımcı erişim token'ı (oda katılımı). Kimlik doğrulanmış JWT'den gelir. */
export async function participantJwt(params: {
  apiKey: string;
  apiSecret: string;
  identity: string;
  name: string;
  roomName: string;
  lang: string;
  ttlSeconds?: number;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  return await signLiveKitJwt(params.apiSecret, {
    iss: params.apiKey,
    sub: params.identity,
    nbf: now - 10,
    exp: now + (params.ttlSeconds ?? 60 * 60 * 4),
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
  });
}

/** wss://… → https://… (LiveKit sunucu API'si HTTP üzerindedir). */
export function httpBase(wsUrl: string): string {
  const t = wsUrl.trim().replace(/\/+$/, "");
  if (t.startsWith("wss://")) return `https://${t.slice(6)}`;
  if (t.startsWith("ws://")) return `http://${t.slice(5)}`;
  return t;
}

export function liveKitEnv(): { key: string; secret: string; base: string } | null {
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

/** Odadaki, kullanıcıya ait (`<uuid>` veya `<uuid>_<dil>`) kimlikleri listeler. */
export async function listUserIdentities(roomName: string, userId: string): Promise<string[]> {
  try {
    const list = await twirp("ListParticipants", roomName, { room: roomName });
    if (!list || !list.ok) {
      await list?.body?.cancel();
      return [];
    }
    const json = await list.json().catch(() => ({}));
    const participants = Array.isArray(json?.participants) ? json.participants : [];
    return participants
      .map((p: { identity?: string }) => String(p?.identity ?? ""))
      .filter((id: string) => id === userId || id.startsWith(`${userId}_`));
  } catch (_) {
    return [];
  }
}

/** Verilen kimlikleri odadan çıkarır; başarıyla çıkarılan sayısını döndürür. */
export async function removeIdentities(roomName: string, identities: string[]): Promise<number> {
  let removed = 0;
  for (const identity of identities) {
    try {
      const res = await twirp("RemoveParticipant", roomName, { room: roomName, identity });
      if (res?.ok) removed++;
      else await res?.body?.cancel();
    } catch (_) {
      // ağ hatası: veritabanı kaydı yeniden katılımı yine engeller
    }
  }
  return removed;
}

/** Kullanıcının odadaki tüm kimliklerini (`<uuid>_<dil>`) çıkarır; çıkarılan sayısını döndürür. */
export async function removeUserFromRoom(roomName: string, userId: string): Promise<number> {
  return await removeIdentities(roomName, await listUserIdentities(roomName, userId));
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
