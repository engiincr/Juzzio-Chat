import { messagePushView, stripQuotedExcerpt } from "./push_preview.js";
declare const process: { exit(c: number): never };
let n = 0;
const eq = (a: unknown, b: unknown, name: string) => {
  n++;
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    console.log("FAIL", name, JSON.stringify(a), JSON.stringify(b));
    process.exit(1);
  }
};
eq(stripQuotedExcerpt('"merhaba" mesajınıza ❤️ tepkisi verdi.'), "Mesajınıza ❤️ tepkisi verdi.", "tr");
eq(stripQuotedExcerpt('Reacted ❤️ to your message: "hi"'), "Reacted ❤️ to your message.", "en");
eq(stripQuotedExcerpt('Hat mit ❤️ auf deine Nachricht reagiert: "x"'), "Hat mit ❤️ auf deine Nachricht reagiert.", "de");
eq(messagePushView("like", "hidden", "tr", "A", "B"), { mode: "full", title: "A", body: "B", dataOnly: false }, "non-message");
eq(messagePushView("message", "hidden", "tr-TR", "Ali", "x"), { mode: "hidden", title: "Juzzio", body: "Yeni mesaj", dataOnly: true }, "hidden");
eq(messagePushView("message", "hidden", "ja", "Ali", "x").body, "New message", "hidden en fallback");
eq(messagePushView("message", "bogus", "tr", "Ali", "x"), { mode: "full", title: "Ali", body: "x", dataOnly: true }, "full default");
eq(messagePushView("reaction", "sender", "en", "Ali", 'Reacted ❤️ to your message: "secret"').body, "Reacted ❤️ to your message.", "sender reaction");
eq(messagePushView("incoming_call", "hidden", "tr", "Ali", "📞").dataOnly, false, "call untouched");
console.log(`push_preview: ${n}/${n} PASS`);
import { strictestPreview } from "./push_preview.js";
eq(strictestPreview("full", "hidden"), "hidden", "room stricter");
eq(strictestPreview("hidden", "full"), "hidden", "room cannot loosen");
eq(strictestPreview("sender", "inherit"), "sender", "inherit");
eq(strictestPreview("full", null), "full", "null");
console.log(`push_preview ek: ${n} toplam PASS`);
