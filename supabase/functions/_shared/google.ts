// =============================================================================
// JUZZIO — Google hizmet hesabı ile kısa ömürlü OAuth erişim belirteci (RS256 JWT)
// Gizli anahtarlar yalnızca Supabase Secrets'tan okunur.
// =============================================================================

export interface GoogleServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[A-Z ]+KEY-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** İlk dolu ortam değişkenindeki hizmet hesabı JSON'unu okur. */
export function loadServiceAccount(envNames: string[]): GoogleServiceAccount | null {
  for (const name of envNames) {
    const raw = (Deno.env.get(name) ?? "").trim();
    if (!raw) continue;
    try {
      const parsed = JSON.parse(raw);
      const projectId = String(parsed.project_id ?? "").trim();
      const clientEmail = String(parsed.client_email ?? "").trim();
      const privateKey = String(parsed.private_key ?? "").trim();
      if (projectId && clientEmail && privateKey) return { projectId, clientEmail, privateKey };
    } catch (_) {
      // sonraki adı dene
    }
  }
  return null;
}

const tokenCache = new Map<string, { token: string; exp: number }>();

export async function getGoogleAccessToken(sa: GoogleServiceAccount, scope: string): Promise<string | null> {
  const key = `${sa.clientEmail}|${scope}`;
  const nowSec = Math.floor(Date.now() / 1000);
  const cached = tokenCache.get(key);
  if (cached && nowSec < cached.exp - 60) return cached.token;
  try {
    const header = { alg: "RS256", typ: "JWT" };
    const claims = {
      iss: sa.clientEmail,
      scope,
      aud: "https://oauth2.googleapis.com/token",
      iat: nowSec - 30,
      exp: nowSec + 3300,
    };
    const signingInput = `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claims))}`;
    const cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      pemToArrayBuffer(sa.privateKey),
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(signingInput));
    const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
    });
    if (!res.ok) {
      await res.body?.cancel();
      return null;
    }
    const json = await res.json();
    const token = String(json.access_token ?? "").trim();
    if (!token) return null;
    tokenCache.set(key, { token, exp: nowSec + Number(json.expires_in ?? 3300) });
    return token;
  } catch (_) {
    return null;
  }
}
