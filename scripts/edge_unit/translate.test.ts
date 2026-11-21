import { isProviderErrorText, splitForTranslation, translateChunked, CHUNK_MAX } from "./translate.js";
declare const process: { exit(c: number): never };
let n = 0;
const ok = (c: boolean, name: string) => {
  n++;
  if (!c) {
    console.log("FAIL", name);
    process.exit(1);
  }
};
// 1) Bölme: kayıpsız ve sınır içinde
const long = Array.from({ length: 40 }, (_, i) => `Bu ${i}. cümle sesli mesaj dökümünden geliyor.`).join(" ");
const parts = splitForTranslation(long);
ok(long.length > 1000, "uzun metin");
ok(parts.length > 1, "birden çok parça");
ok(parts.every((p) => p.length <= CHUNK_MAX), "her parça ≤ 450");
ok(parts.join(" ").replace(/\s+/g, " ") === long.replace(/\s+/g, " "), "kayıpsız");
const noPunct = "kelime ".repeat(300).trim();
ok(splitForTranslation(noPunct).every((p) => p.length <= CHUNK_MAX), "noktalamasız metin bölünür");
ok(splitForTranslation("x".repeat(1200)).every((p) => p.length <= CHUNK_MAX), "boşluksuz metin zorla bölünür");
ok(splitForTranslation("  ").length === 0, "boş");
ok(splitForTranslation("kısa").length === 1, "kısa tek parça");
// 2) Hata metni tanınır
ok(isProviderErrorText("QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS"), "500 hatası");
ok(isProviderErrorText("MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS FOR TODAY"), "kota");
ok(!isProviderErrorText("Merhaba dünya"), "normal metin");
// 3) Google başarısız + MyMemory hata metni → çeviri SAYILMAZ (null)
const failing = async (url: string) => {
  if (url.includes("googleapis")) return { ok: false, json: async () => ({}) };
  return { ok: true, json: async () => ({ responseStatus: 403, responseData: { translatedText: "QUERY LENGTH LIMIT EXCEEDED. MAX ALLOWED QUERY : 500 CHARS" } }) };
};
const r1 = await translateChunked(long, "tr", "en", failing);
ok(r1 === null, "hata metni çeviri olarak dönmez");
// 4) Google parça parça çevirir; her istek ≤ 450 karakterlik parça içerir
const seen: number[] = [];
const google = async (url: string) => {
  const q = decodeURIComponent(url.split("&q=")[1] ?? "");
  seen.push(q.length);
  return { ok: true, json: async () => [[[`[${q.length}]`, q]], null, "tr"] };
};
const r2 = await translateChunked(long, "auto", "en", google);
ok(r2 !== null && seen.length === parts.length, "her parça ayrı istek");
ok(seen.every((l) => l <= CHUNK_MAX), "istek uzunluğu sınır içinde");
ok(r2!.detected === "tr", "algılanan dil");
// 5) Kısmi başarısızlık: çevrilemeyen parça orijinal kalır
let i = 0;
const partial = async (url: string) => {
  i++;
  if (url.includes("googleapis") && i % 2 === 0) return { ok: false, json: async () => ({}) };
  if (url.includes("mymemory")) return { ok: true, json: async () => ({ responseStatus: 200, responseData: { translatedText: "MM" } }) };
  return { ok: true, json: async () => [[["G", "x"]], null, "tr"] };
};
const r3 = await translateChunked(long, "tr", "en", partial);
ok(r3 !== null && !r3.text.includes("QUERY"), "kısmi başarı");
console.log(`translate: ${n}/${n} PASS`);

// v0.9.3: Google dil kodu biçimi
{
  const { googleLangCode } = await import("./translate.js");
  const cases: Array<[string, string]> = [["zh-tw", "zh-TW"], ["pa-arab", "pa-Arab"], ["pt-pt", "pt-PT"], ["fa-af", "fa-AF"], ["TR", "tr"], ["auto", "auto"]];
  for (const [i, o] of cases) {
    if (googleLangCode(i) !== o) throw new Error(`googleLangCode(${i}) = ${googleLangCode(i)} ≠ ${o}`);
  }
  console.log("translate googleLangCode: 6/6 PASS");
}

// v1.2.9: resmî API anahtarı varsa resmî olmayan uç noktaya HİÇ gidilmez
{
  const { translateChunked: tc, translationProviderStatus, deeplLang } = await import("./translate.js");
  const urls: string[] = [];
  const cloud = async (url: string, init?: Record<string, unknown>) => {
    urls.push(url);
    if (url.startsWith("https://translation.googleapis.com/language/translate/v2")) {
      const b = JSON.parse(String(init?.body ?? "{}"));
      return { ok: true, json: async () => ({ data: { translations: [{ translatedText: `C:${b.q}`, detectedSourceLanguage: "tr" }] } }) };
    }
    return { ok: true, json: async () => [[["GTX", "x"]], null, "tr"] };
  };
  const r = await tc("Merhaba dünya", "auto", "en", cloud, { google: "k" });
  if (!r || r.text !== "C:Merhaba dünya") throw new Error("google cloud çevirisi kullanılmadı");
  if (urls.some((u) => u.includes("client=gtx") || u.includes("mymemory"))) throw new Error("resmî anahtar varken gtx/mymemory çağrıldı");
  // Google Cloud başarısız → DeepL; DeepL de yoksa orijinal (gtx'e düşmez)
  const urls2: string[] = [];
  const deepl = async (url: string, init?: Record<string, unknown>) => {
    urls2.push(url);
    if (url.includes("deepl.com")) {
      const b = JSON.parse(String(init?.body ?? "{}"));
      if (b.target_lang !== "EN-US") throw new Error("deepl hedef kodu");
      return { ok: true, json: async () => ({ translations: [{ text: "D", detected_source_language: "TR" }] }) };
    }
    return { ok: false, json: async () => ({}) };
  };
  const r2 = await tc("Selam", "auto", "en", deepl, { google: "k", deepl: "x:fx" });
  if (!r2 || r2.text !== "D" || !urls2.some((u) => u.startsWith("https://api-free.deepl.com"))) throw new Error("deepl yedeği");
  if (urls2.some((u) => u.includes("client=gtx"))) throw new Error("gtx'e düşüldü");
  if (translationProviderStatus({}) !== "unofficial" || translationProviderStatus({ deepl: "a" }) !== "deepl" || translationProviderStatus({ google: "a" }) !== "google_cloud") throw new Error("sağlayıcı durumu");
  if (deeplLang("pt", true) !== "PT-BR" || deeplLang("tr", false) !== "TR" || deeplLang("zh-tw", true) !== "ZH-HANT") throw new Error("deeplLang");
  console.log("translate v1.2.9 resmî sağlayıcı: 8/8 PASS");
}
// v2.1 (Faz 7.5): çeviri kipi
{
  const m = await import("./translate.js");
  const { parseQuality, deeplModelType, translateChunked: tc } = m as unknown as {
    parseQuality: (v: unknown) => string;
    deeplModelType: (q: string) => string | null;
    translateChunked: (...a: unknown[]) => Promise<{ text: string } | null>;
  };
  if (parseQuality("accurate") !== "accurate" || parseQuality("REALTIME") !== "realtime" || parseQuality("x") !== "fast" || parseQuality(undefined) !== "fast") throw new Error("parseQuality");
  if (deeplModelType("accurate") !== "prefer_quality_optimized" || deeplModelType("realtime") !== "latency_optimized" || deeplModelType("fast") !== null) throw new Error("deeplModelType");
  const order: string[] = [] as string[];
  let model: unknown = "yok";
  const f = async (url: string, init?: { body?: string }) => {
    if (url.includes("deepl.com")) {
      order.push("deepl");
      model = JSON.parse(String(init?.body ?? "{}")).model_type;
      return { ok: true, json: async () => ({ translations: [{ text: "D", detected_source_language: "TR" }] }) };
    }
    order.push("google");
    return { ok: true, json: async () => ({ data: { translations: [{ translatedText: "G", detectedSourceLanguage: "tr" }] } }) };
  };
  const r = await tc("Selam", "auto", "en", f, { google: "k", deepl: "x:fx" }, "accurate");
  if (!r || r.text !== "D" || String(order[0]) !== "deepl" || model !== "prefer_quality_optimized") throw new Error("yüksek doğruluk DeepL önce");
  order.length = 0;
  const r2 = await tc("Selam", "auto", "en", f, { google: "k", deepl: "x:fx" }, "fast");
  if (!r2 || r2.text !== "G" || String(order[0]) !== "google") throw new Error("hızlı kip Google önce");
  console.log("translate v2.1 çeviri kipi: 4/4 PASS");
}
