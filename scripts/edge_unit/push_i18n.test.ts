import { buildLocalizedPush, replyParts } from "./push_i18n.js";
declare const process: { exit(c: number): never };
let n = 0;
const eq = (a: unknown, b: unknown, name: string) => {
  n++;
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    console.log("FAIL", name, JSON.stringify(a), JSON.stringify(b));
    process.exit(1);
  }
};
const ctx = (preview: string) => ({ actor: "Engin", me: "Ali", preview, gender: "unspecified" as const });
eq(replyParts("reply|Harika|Katılıyorum"), { comment: "Harika", reply: "Katılıyorum" }, "parts");
eq(replyParts("düz metin"), null, "eski biçim");
eq((await buildLocalizedPush("reply", "tr", ctx("reply|Harika gönderi|Katılıyorum"))).body, '"Harika gönderi" yorumunuza "Katılıyorum" yanıtını verdi.', "tr yanıt");
eq((await buildLocalizedPush("reply", "tr", ctx("reply||Teşekkürler"))).body, 'Yorumunuza "Teşekkürler" yanıtını verdi.', "tr yanıt yorumsuz");
eq((await buildLocalizedPush("reply", "tr", ctx("eski"))).body, "Yorumunuza yanıt verdi.", "tr eski");
eq((await buildLocalizedPush("comment_like", "tr", ctx("Harika gönderi"))).body, '"Harika gönderi" yorumunuzu beğendi.', "tr beğeni");
eq((await buildLocalizedPush("comment_like", "en", ctx(""))).body, "Liked your comment.", "en beğeni boş");
eq((await buildLocalizedPush("comment_like", "de", ctx("x"))).title, "Engin", "de başlık");
console.log(`push_i18n: ${n}/${n} PASS`);

// v0.9.5 yeni bildirim türleri
{
  const m = await import("./push_i18n.js");
  const parts = m.previewParts("poll|Pizza mı?|Evet|2|2", "poll");
  if (!parts || parts[1] !== "Evet" || parts[3] !== "2") throw new Error("previewParts");
  if (m.previewParts("x|y", "poll") !== null) throw new Error("previewParts null");
  console.log("push_i18n v0.9.5: 2/2 PASS");
}
// v1.2.0 hikâye tepki / yorum bildirimleri
{
  const m = await import("./push_i18n.js");
  const c = (preview: string) => ({ actor: "Fikret39", me: "Ali", preview, gender: "unspecified" as const });
  const checks: Array<[string, string, string, string]> = [
    ["tr", "storyreact|🌸", "Hikâyene 🌸 tepkisi verdi.", "tr tepki"],
    ["tr", "storycomment|çok güzel", 'Hikâyene "çok güzel" yorumunu ekledi.', "tr yorum"],
    ["tr", "storycomment|", "Hikâyene yorum ekledi.", "tr şifreli yorum"],
    ["en", "storyreact|🔥", "Reacted 🔥 to your story.", "en tepki"],
    ["de", "storycomment|super", "Hat deine Story kommentiert: „super“", "de yorum"],
    ["tr", "📸 Hikâye yanıtı: x", "Hikâyenize yanıt verdi.", "tr eski biçim"],
  ];
  for (const [lang, pv, body, name] of checks) {
    const r = await m.buildLocalizedPush("story_reply", lang as "tr" | "en" | "de", c(pv));
    if (r.body !== body) { console.log("FAIL", name, r.body); process.exit(1); }
  }
  if (m.storyParts("x") !== null) throw new Error("storyParts null");
  console.log(`push_i18n v1.2.0: ${checks.length + 1}/${checks.length + 1} PASS`);
}
