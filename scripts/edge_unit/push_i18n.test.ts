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
