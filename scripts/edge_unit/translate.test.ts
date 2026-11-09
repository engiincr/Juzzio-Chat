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
