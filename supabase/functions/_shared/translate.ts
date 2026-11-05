// =============================================================================
// JUZZIO v0.9.3 — Ortak çeviri yardımcıları
//  Sorun: uzun metin (ör. sesli mesaj dökümü) tek istekte gönderiliyordu. Google'ın GET adresi
//  uzunlukta başarısız olunca yedek servis MyMemory'ye düşülüyor, o da 500 karakter sınırında
//  "QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS" HATA METNİNİ çeviri gibi
//  döndürüyordu → kullanıcı ekranda hata yazısını görüyordu.
//  Çözüm: metin cümle sınırlarından ≤ 450 karakterlik parçalara bölünür, her parça ayrı
//  çevrilir; sağlayıcı hata/uyarı metinleri ASLA çeviri kabul edilmez (orijinal korunur).
// =============================================================================

export const CHUNK_MAX = 450;

/** Uygulamanın küçük harfli dil kodunu Google'ın beklediği biçime çevirir (zh-tw → zh-TW, pa-arab → pa-Arab). */
export function googleLangCode(code: string): string {
  const c = code.trim();
  const i = c.indexOf("-");
  if (i < 0) return c.toLowerCase();
  const base = c.slice(0, i).toLowerCase();
  const sub = c.slice(i + 1);
  if (sub.length === 4) return `${base}-${sub[0].toUpperCase()}${sub.slice(1).toLowerCase()}`;
  return `${base}-${sub.toUpperCase()}`;
}

/** Metni cümle → kelime sınırlarından en fazla [max] karakterlik parçalara böler (kayıpsız). */
export function splitForTranslation(text: string, max = CHUNK_MAX): string[] {
  const clean = text.trim();
  if (!clean) return [];
  if (clean.length <= max) return [clean];
  const out: string[] = [];
  // Cümle sonlarından böl, ayırıcıları koru
  const sentences = clean.match(/[^.!?。！？\n]+[.!?。！？]*[\s\n]*/g) ?? [clean];
  let buf = "";
  const flush = () => {
    if (buf.trim()) out.push(buf.trim());
    buf = "";
  };
  for (const s of sentences) {
    if ((buf + s).length <= max) {
      buf += s;
      continue;
    }
    flush();
    if (s.length <= max) {
      buf = s;
      continue;
    }
    // Tek cümle çok uzun → kelime sınırından böl; tek kelime de uzunsa zorla kes
    let rest = s;
    while (rest.length > max) {
      let cut = rest.lastIndexOf(" ", max);
      if (cut < max * 0.5) cut = max;
      out.push(rest.slice(0, cut).trim());
      rest = rest.slice(cut);
    }
    buf = rest;
  }
  flush();
  return out.filter((p) => p.length > 0);
}

/** Sağlayıcının çeviri yerine döndürdüğü hata/uyarı metinleri. */
export function isProviderErrorText(s: string): boolean {
  const u = s.trim().toUpperCase();
  return (
    u.startsWith("QUERY LENGTH LIMIT") ||
    u.includes("MAX ALLOWED QUERY") ||
    u.startsWith("MYMEMORY WARNING") ||
    u.includes("YOU USED ALL AVAILABLE FREE TRANSLATIONS") ||
    u.startsWith("INVALID LANGUAGE PAIR") ||
    u.startsWith("PLEASE SELECT TWO DISTINCT LANGUAGES") ||
    u.startsWith("NO QUERY SPECIFIED")
  );
}

type FetchLike = (url: string, init?: Record<string, unknown>) => Promise<{
  ok: boolean;
  json: () => Promise<unknown>;
}>;

async function googleChunk(f: FetchLike, chunk: string, sl: string, tl: string): Promise<{ text: string; detected: string } | null> {
  try {
    const url = `https://translate.googleapis.com/translate_a/single?client=gtx&sl=${encodeURIComponent(googleLangCode(sl))}` +
      `&tl=${encodeURIComponent(googleLangCode(tl))}&dt=t&q=${encodeURIComponent(chunk)}`;
    const res = await f(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!res.ok) return null;
    const data = await res.json();
    if (Array.isArray(data) && Array.isArray(data[0])) {
      const joined = (data[0] as unknown[])
        .map((seg) => (Array.isArray(seg) && seg[0] ? String(seg[0]) : ""))
        .join("")
        .trim();
      const detected = typeof data[2] === "string" ? String(data[2]).toLowerCase() : sl;
      if (joined && !isProviderErrorText(joined)) return { text: joined, detected };
    }
  } catch (_) {
    // yedeğe geç
  }
  return null;
}

async function myMemoryChunk(f: FetchLike, chunk: string, sl: string, tl: string): Promise<string | null> {
  try {
    const pair = `${sl === "auto" ? "tr" : sl}|${tl}`;
    const res = await f(
      `https://api.mymemory.translated.net/get?q=${encodeURIComponent(chunk)}&langpair=${encodeURIComponent(pair)}`,
    );
    if (!res.ok) return null;
    const json = (await res.json()) as { responseStatus?: unknown; responseData?: { translatedText?: unknown } };
    const status = Number(json?.responseStatus ?? 0);
    const t = String(json?.responseData?.translatedText ?? "").trim();
    if (status !== 200 || !t || isProviderErrorText(t)) return null;
    return t;
  } catch (_) {
    return null;
  }
}

/**
 * Parçalı çeviri. Bir parça çevrilemezse o parçanın ORİJİNALİ kullanılır; hiçbir parça
 * çevrilemezse null döner (çağıran orijinali "çeviri" diye göstermez).
 */
export async function translateChunked(
  text: string,
  sourceLang: string,
  targetLang: string,
  f: FetchLike = fetch as unknown as FetchLike,
): Promise<{ text: string; detected: string } | null> {
  const parts = splitForTranslation(text);
  if (parts.length === 0) return null;
  if (sourceLang !== "auto" && sourceLang === targetLang) return { text: text.trim(), detected: sourceLang };
  const out: string[] = [];
  let any = false;
  let detected = sourceLang;
  for (const p of parts) {
    const g = await googleChunk(f, p, sourceLang, targetLang);
    if (g) {
      out.push(g.text);
      if (!any) detected = g.detected;
      any = true;
      continue;
    }
    const m = await myMemoryChunk(f, p, sourceLang, targetLang);
    if (m) {
      out.push(m);
      any = true;
      continue;
    }
    out.push(p);
  }
  return any ? { text: out.join(" ").trim(), detected } : null;
}
