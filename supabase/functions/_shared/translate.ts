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

// -----------------------------------------------------------------------------
// v1.2.9 (politika): resmî çeviri API'leri. Sunucuda GOOGLE_TRANSLATE_API_KEY (Google Cloud
// Translation v2) veya DEEPL_API_KEY tanımlıysa YALNIZ resmî API kullanılır; resmî olmayan
// "translate_a/single?client=gtx" uç noktasına (Google hizmet koşullarına aykırı otomatik erişim)
// hiç gidilmez. Anahtar yoksa eski davranış sürer ve Sistem Sağlığı bunu uyarır.
// -----------------------------------------------------------------------------
export type OfficialKeys = { google?: string; deepl?: string };

export function officialKeysFromEnv(): OfficialKeys {
  try {
    const env = (globalThis as unknown as { Deno?: { env: { get(k: string): string | undefined } } }).Deno?.env;
    return {
      google: (env?.get("GOOGLE_TRANSLATE_API_KEY") ?? "").trim() || undefined,
      deepl: (env?.get("DEEPL_API_KEY") ?? "").trim() || undefined,
    };
  } catch (_) {
    return {};
  }
}

/** Hangi sağlayıcı kullanılıyor? (Sistem Sağlığı'nda gösterilir; anahtar değeri ASLA dönmez) */
export function translationProviderStatus(keys: OfficialKeys = officialKeysFromEnv()): "google_cloud" | "deepl" | "unofficial" {
  if (keys.google) return "google_cloud";
  if (keys.deepl) return "deepl";
  return "unofficial";
}

/** DeepL dil kodu (saf): hedefte EN→EN-US, PT→PT-BR; kaynak yalnız temel kod */
export function deeplLang(code: string, target: boolean): string {
  const c = code.trim().toLowerCase();
  const base = c.split("-")[0].toUpperCase();
  if (!target) return base;
  if (base === "EN") return c === "en-gb" ? "EN-GB" : "EN-US";
  if (base === "PT") return c === "pt-pt" ? "PT-PT" : "PT-BR";
  if (base === "ZH") return c === "zh-tw" ? "ZH-HANT" : "ZH-HANS";
  return base;
}

async function googleCloudChunk(f: FetchLike, key: string, chunk: string, sl: string, tl: string): Promise<{ text: string; detected: string } | null> {
  try {
    const body: Record<string, string> = { q: chunk, target: googleLangCode(tl), format: "text" };
    if (sl !== "auto") body.source = googleLangCode(sl);
    const res = await f(`https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(key)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { data?: { translations?: Array<{ translatedText?: string; detectedSourceLanguage?: string }> } };
    const t = json?.data?.translations?.[0];
    const text = String(t?.translatedText ?? "").trim();
    if (!text) return null;
    return { text, detected: String(t?.detectedSourceLanguage ?? sl).toLowerCase() };
  } catch (_) {
    return null;
  }
}

/**
 * v2.1 (Faz 7.5): çeviri kipi — kullanıcının Ayarlar → Çeviri ve Dil seçimi.
 *  realtime → en düşük gecikme (canlı altyazı, sesli not)
 *  fast     → varsayılan
 *  accurate → "Yüksek Doğruluk": DeepL önce, kalite modeli
 */
export type TranslateQuality = "realtime" | "fast" | "accurate";

/** İstemciden gelen değeri güvenli kipe çevirir (saf) */
export function parseQuality(v: unknown): TranslateQuality {
  const s = String(v ?? "").toLowerCase();
  return s === "realtime" || s === "accurate" ? s : "fast";
}

/** DeepL model_type karşılığı (saf). "prefer_…" desteklenmeyen dil çiftinde otomatik geri düşer. */
export function deeplModelType(q: TranslateQuality): string | null {
  return q === "accurate" ? "prefer_quality_optimized" : q === "realtime" ? "latency_optimized" : null;
}

async function deeplChunk(f: FetchLike, key: string, chunk: string, sl: string, tl: string, quality: TranslateQuality = "fast"): Promise<{ text: string; detected: string } | null> {
  try {
    const host = key.endsWith(":fx") ? "api-free.deepl.com" : "api.deepl.com";
    const body: Record<string, unknown> = { text: [chunk], target_lang: deeplLang(tl, true) };
    const model = deeplModelType(quality);
    if (model) body.model_type = model;
    if (sl !== "auto") body.source_lang = deeplLang(sl, false);
    const res = await f(`https://${host}/v2/translate`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `DeepL-Auth-Key ${key}` },
      body: JSON.stringify(body),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as { translations?: Array<{ text?: string; detected_source_language?: string }> };
    const t = json?.translations?.[0];
    const text = String(t?.text ?? "").trim();
    if (!text) return null;
    return { text, detected: String(t?.detected_source_language ?? sl).toLowerCase() };
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
  keys: OfficialKeys = officialKeysFromEnv(),
  quality: TranslateQuality = "fast",
): Promise<{ text: string; detected: string } | null> {
  const parts = splitForTranslation(text);
  if (parts.length === 0) return null;
  if (sourceLang !== "auto" && sourceLang === targetLang) return { text: text.trim(), detected: sourceLang };
  const out: string[] = [];
  let any = false;
  let detected = sourceLang;
  const official = Boolean(keys.google || keys.deepl);
  for (const p of parts) {
    if (official) {
      // v1.2.9: resmî API(ler); biri olmazsa diğeri — resmî olmayan uç noktaya düşülmez
      // v2.1: "Yüksek Doğruluk" kipinde DeepL (kalite modeli) önce denenir
      const o = quality === "accurate"
        ? ((keys.deepl ? await deeplChunk(f, keys.deepl, p, sourceLang, targetLang, quality) : null) ??
          (keys.google ? await googleCloudChunk(f, keys.google, p, sourceLang, targetLang) : null))
        : ((keys.google ? await googleCloudChunk(f, keys.google, p, sourceLang, targetLang) : null) ??
          (keys.deepl ? await deeplChunk(f, keys.deepl, p, sourceLang, targetLang, quality) : null));
      if (o) {
        out.push(o.text);
        if (!any) detected = o.detected;
        any = true;
      } else {
        out.push(p);
      }
      continue;
    }
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
