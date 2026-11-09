// =============================================================================
// JUZZIO — Push bildirim metinleri (alıcının uygulama dilinde)
//  • tr / en / de: elle yazılmış tam çeviriler
//  • Diğer diller: İngilizce metin sunucuda çevrilir (başarısız olursa İngilizce)
//  • Civciv bildirimleri alıcının (gizli) cinsiyetine göre kişiselleştirilir
// =============================================================================

export type PushLang = "tr" | "en" | "de";
export type Gender = "female" | "male" | "unspecified";

interface Ctx {
  actor: string; // bildirimi tetikleyen kişinin adı
  me: string; // alıcının görünen adı
  preview: string; // DB'deki önizleme (çağrı anahtarı, civciv adı vb.)
  gender: Gender;
}

type Builder = (c: Ctx) => { title: string; body: string };

function callKind(preview: string): { group: boolean; video: boolean; groupTitle: string } {
  // Yeni biçim: "call:voice" | "call:video" | "call:group_voice:Başlık" | "call:group_video:Başlık"
  if (preview.startsWith("call:")) {
    const parts = preview.split(":");
    const kind = parts[1] ?? "voice";
    return { group: kind.startsWith("group_"), video: kind.endsWith("video"), groupTitle: parts.slice(2).join(":") };
  }
  // Eski kayıtlar (Türkçe önizleme)
  const lower = preview.toLowerCase();
  return { group: lower.includes("•") || lower.includes("grup"), video: lower.includes("görüntülü"), groupTitle: "" };
}


// Tepki önizlemesi "🌸|mesaj metni" biçimindedir
function reactionParts(preview: string): { emoji: string; text: string } {
  const i = preview.indexOf("|");
  if (i < 0) return { emoji: preview || "❤️", text: "" };
  return { emoji: preview.slice(0, i) || "❤️", text: preview.slice(i + 1).trim() };
}

// v0.9.3: yanıt önizlemesi "reply|<yorum>|<yanıt>"
export function replyParts(preview: string): { comment: string; reply: string } | null {
  if (!preview.startsWith("reply|")) return null;
  const rest = preview.slice(6);
  const i = rest.indexOf("|");
  if (i < 0) return null;
  return { comment: rest.slice(0, i).trim(), reply: rest.slice(i + 1).trim() };
}

/** v0.9.5: "<önek>|a|b|c" önizlemesini parçalara ayırır. */
export function previewParts(preview: string, prefix: string): string[] | null {
  if (!preview.startsWith(prefix + "|")) return null;
  return preview.slice(prefix.length + 1).split("|");
}

function clip(text: string, max = 40): string {
  return text.length > max ? text.slice(0, max - 1) + "…" : text;
}

const T: Record<PushLang, Record<string, Builder>> = {
  tr: {
    message: (c) => ({ title: c.actor, body: "Size yeni bir mesaj gönderdi." }),
    poll_closed: (c) => {
      const p = previewParts(c.preview, "poll") ?? [];
      return { title: "📊 Anket sonuçlandı", body: p[1] ? `${clip(p[0] ?? "", 60)} → ${p[1]} (${p[2]}/${p[3]} oy)` : `${clip(p[0] ?? "", 60)} — oy kullanılmadı` };
    },
    memory: (c) => {
      const p = previewParts(c.preview, "memory") ?? [];
      return { title: `📸 Bugün ${p[0] ?? "1"} yıl önce`, body: p[1] ? clip(p[1], 80) : "O gün paylaştığın anıya göz at." };
    },
    sos: (c) => {
      const p = previewParts(c.preview, "sos") ?? [];
      const why = p[0] === "battery" ? "Pili bitmek üzere" : p[0] === "inactive" ? "Uzun süredir hareket yok" : p[0] === "overdue" ? "Varış süresi doldu, haber yok" : "Acil yardım istedi";
      return { title: `🆘 ${c.actor} — GÜVENLİK UYARISI`, body: `${why}. ${p[1] ? "Son konum: " + p[1] : "Konum bilinmiyor."}` };
    },
    qa_question: (c) => ({ title: "❓ Yeni soru", body: `${c.actor || "Anonim"}: ${clip(c.preview, 80)}` }),
    qa_answer: (c) => ({ title: `💬 ${c.actor} sorunu yanıtladı`, body: clip(c.preview, 80) }),
    watch_party: (c) => ({ title: `🎬 ${c.actor} izleme partisi başlattı`, body: `${clip(c.preview.replace(/^watch\|/, ""), 60)} — katılmak için dokun` }),
    reminder: (c) => c.preview.startsWith("event|") ? { title: "📅 Etkinlik yaklaşıyor", body: c.preview.slice(6) } : (c.preview.startsWith("message|") ? { title: "⏰ Hatırlatma", body: "Yanıtlamak için işaretlediğin mesajın zamanı geldi." } : { title: "⏰ Hatırlatma", body: c.preview.replace(/^task\|/, "") || "Görevinin zamanı geldi." }),
    mention: (c) => ({ title: c.actor, body: c.preview.startsWith("comment|") ? "Bir yorumda sizden bahsetti." : c.preview.startsWith("story|") ? "Hikâyesinde sizden bahsetti." : "Bir gönderide sizden bahsetti." }),
    group_activity: (c) => ({ title: c.actor, body: "Grup sohbetinde yeni bir mesaj var." }),
    missed_call: (c) => {
      const k = callKind(c.preview);
      return { title: c.actor, body: k.video ? "Cevapsız görüntülü arama" : "Cevapsız sesli arama" };
    },
    incoming_call: (c) => {
      const k = callKind(c.preview);
      const what = k.video ? "görüntülü" : "sesli";
      return {
        title: c.actor,
        body: k.group ? `📞 ${k.groupTitle || "Grup"} • ${what} konferans` : `📞 Sizi ${what} arıyor`,
      };
    },
    friend_request: (c) => ({ title: c.actor, body: "Size arkadaşlık isteği gönderdi." }),
    friend_accepted: (c) => ({ title: c.actor, body: "Arkadaşlık isteğinizi kabul etti." }),
    follow: (c) => ({ title: c.actor, body: "Sizi takip etmeye başladı." }),
    follow_request: (c) => ({ title: c.actor, body: "Sizi takip etmek istiyor." }),
    follow_accepted: (c) => ({ title: c.actor, body: "Takip isteğinizi kabul etti." }),
    like: (c) => ({ title: c.actor, body: "Gönderinizi beğendi." }),
    story_like: (c) => ({ title: c.actor, body: "Hikâyenizi beğendi." }),
    comment: (c) => ({ title: c.actor, body: "Gönderinize yorum yaptı." }),
    save: (c) => ({ title: c.actor, body: "Gönderinizi kaydetti." }),
    reaction: (c) => {
      const r = reactionParts(c.preview);
      return { title: c.actor, body: r.text ? `"${clip(r.text)}" mesajınıza ${r.emoji} tepkisi verdi.` : `Mesajınıza ${r.emoji} tepkisi verdi.` };
    },
    reply: (c) => { const r = replyParts(c.preview); return { title: c.actor, body: !r ? "Yorumunuza yanıt verdi." : r.comment ? `"${clip(r.comment)}" yorumunuza "${clip(r.reply)}" yanıtını verdi.` : `Yorumunuza "${clip(r.reply)}" yanıtını verdi.` }; },
    comment_like: (c) => ({ title: c.actor, body: c.preview ? `"${clip(c.preview)}" yorumunuzu beğendi.` : "Yorumunuzu beğendi." }),
    story_reply: (c) => ({ title: c.actor, body: "Hikâyenize yanıt verdi." }),
    chick_invite: (c) => ({ title: "🐣 Civciv daveti", body: `${c.actor} seninle "${c.preview}" adlı civcivi büyütmek istiyor.` }),
    chick_hatched: (c) => ({ title: "🐣 Civcivin yumurtadan çıktı!", body: `${c.actor} daveti kabul etti. "${c.preview}" artık sizin!` }),
    chick_hungry: (c) => ({
      title: `🐥 ${c.preview || "Civciv"}`,
      body: c.gender === "female" ? "Acıktım annecim 🥺" : c.gender === "male" ? "Acıktım babacım 🥺" : `${c.me}, acıkmaya başladım 🥺`,
    }),
    chick_dying: (c) => ({ title: `🐥 ${c.preview || "Civciv"}`, body: "Ölüyorum! 3 gündür beni beslemedin 😢" }),
    chick_died: (c) => ({ title: "🪦 Civcivin öldü", body: `${c.preview || "Civciv"} 7 gün boyunca beslenmediği için öldü.` }),
    system: (c) => ({ title: "Juzzio", body: c.preview || "Yeni bir bildiriminiz var." }),
    push_test: () => ({ title: "Juzzio ✅", body: "Bildirimler çalışıyor. Bu test bildirimi sunucudan gönderildi." }),
  },
  en: {
    message: (c) => ({ title: c.actor, body: "Sent you a new message." }),
    poll_closed: (c) => {
      const p = previewParts(c.preview, "poll") ?? [];
      return { title: "📊 Poll closed", body: p[1] ? `${clip(p[0] ?? "", 60)} → ${p[1]} (${p[2]}/${p[3]} votes)` : `${clip(p[0] ?? "", 60)} — no votes` };
    },
    memory: (c) => {
      const p = previewParts(c.preview, "memory") ?? [];
      return { title: `📸 ${p[0] ?? "1"} year(s) ago today`, body: p[1] ? clip(p[1], 80) : "Look back at what you shared." };
    },
    sos: (c) => {
      const p = previewParts(c.preview, "sos") ?? [];
      const why = p[0] === "battery" ? "Battery almost empty" : p[0] === "inactive" ? "No movement for a while" : p[0] === "overdue" ? "Arrival time passed with no check-in" : "Asked for help";
      return { title: `🆘 ${c.actor} — SAFETY ALERT`, body: `${why}. ${p[1] ? "Last location: " + p[1] : "Location unknown."}` };
    },
    qa_question: (c) => ({ title: "❓ New question", body: `${c.actor || "Anonymous"}: ${clip(c.preview, 80)}` }),
    qa_answer: (c) => ({ title: `💬 ${c.actor} answered your question`, body: clip(c.preview, 80) }),
    watch_party: (c) => ({ title: `🎬 ${c.actor} started a watch party`, body: `${clip(c.preview.replace(/^watch\|/, ""), 60)} — tap to join` }),
    reminder: (c) => c.preview.startsWith("event|") ? { title: "📅 Event starting soon", body: c.preview.slice(6) } : (c.preview.startsWith("message|") ? { title: "⏰ Reminder", body: "Time to reply to the message you marked." } : { title: "⏰ Reminder", body: c.preview.replace(/^task\|/, "") || "Your task is due." }),
    mention: (c) => ({ title: c.actor, body: c.preview.startsWith("comment|") ? "Mentioned you in a comment." : c.preview.startsWith("story|") ? "Mentioned you in their story." : "Mentioned you in a post." }),
    group_activity: (c) => ({ title: c.actor, body: "There is a new message in the group chat." }),
    missed_call: (c) => {
      const k = callKind(c.preview);
      return { title: c.actor, body: k.video ? "Missed video call" : "Missed voice call" };
    },
    incoming_call: (c) => {
      const k = callKind(c.preview);
      const what = k.video ? "video" : "voice";
      return { title: c.actor, body: k.group ? `📞 ${k.groupTitle || "Group"} • ${what} conference` : `📞 Incoming ${what} call` };
    },
    friend_request: (c) => ({ title: c.actor, body: "Sent you a friend request." }),
    friend_accepted: (c) => ({ title: c.actor, body: "Accepted your friend request." }),
    follow: (c) => ({ title: c.actor, body: "Started following you." }),
    follow_request: (c) => ({ title: c.actor, body: "Wants to follow you." }),
    follow_accepted: (c) => ({ title: c.actor, body: "Accepted your follow request." }),
    like: (c) => ({ title: c.actor, body: "Liked your post." }),
    story_like: (c) => ({ title: c.actor, body: "Liked your story." }),
    comment: (c) => ({ title: c.actor, body: "Commented on your post." }),
    save: (c) => ({ title: c.actor, body: "Saved your post." }),
    reaction: (c) => {
      const r = reactionParts(c.preview);
      return { title: c.actor, body: r.text ? `Reacted ${r.emoji} to your message: "${clip(r.text)}"` : `Reacted ${r.emoji} to your message.` };
    },
    reply: (c) => { const r = replyParts(c.preview); return { title: c.actor, body: !r ? "Replied to your comment." : r.comment ? `Replied "${clip(r.reply)}" to your comment "${clip(r.comment)}".` : `Replied "${clip(r.reply)}" to your comment.` }; },
    comment_like: (c) => ({ title: c.actor, body: c.preview ? `Liked your comment "${clip(c.preview)}".` : "Liked your comment." }),
    story_reply: (c) => ({ title: c.actor, body: "Replied to your story." }),
    chick_invite: (c) => ({ title: "🐣 Chick invitation", body: `${c.actor} wants to raise a chick called "${c.preview}" with you.` }),
    chick_hatched: (c) => ({ title: "🐣 Your chick has hatched!", body: `${c.actor} accepted. "${c.preview}" is yours now!` }),
    chick_hungry: (c) => ({
      title: `🐥 ${c.preview || "Chick"}`,
      body: c.gender === "female" ? "I'm hungry, mommy 🥺" : c.gender === "male" ? "I'm hungry, daddy 🥺" : `${c.me}, I'm getting hungry 🥺`,
    }),
    chick_dying: (c) => ({ title: `🐥 ${c.preview || "Chick"}`, body: "I'm dying! You haven't fed me for 3 days 😢" }),
    chick_died: (c) => ({ title: "🪦 Your chick died", body: `${c.preview || "Chick"} died after 7 days without food.` }),
    system: (c) => ({ title: "Juzzio", body: c.preview || "You have a new notification." }),
    push_test: () => ({ title: "Juzzio ✅", body: "Notifications are working. This test notification was sent by the server." }),
  },
  de: {
    message: (c) => ({ title: c.actor, body: "Hat dir eine neue Nachricht gesendet." }),
    poll_closed: (c) => {
      const p = previewParts(c.preview, "poll") ?? [];
      return { title: "📊 Umfrage beendet", body: p[1] ? `${clip(p[0] ?? "", 60)} → ${p[1]} (${p[2]}/${p[3]} Stimmen)` : `${clip(p[0] ?? "", 60)} — keine Stimmen` };
    },
    memory: (c) => {
      const p = previewParts(c.preview, "memory") ?? [];
      return { title: `📸 Heute vor ${p[0] ?? "1"} Jahr(en)`, body: p[1] ? clip(p[1], 80) : "Schau dir deine Erinnerung an." };
    },
    sos: (c) => {
      const p = previewParts(c.preview, "sos") ?? [];
      const why = p[0] === "battery" ? "Akku fast leer" : p[0] === "inactive" ? "Seit Längerem keine Bewegung" : p[0] === "overdue" ? "Ankunftszeit überschritten" : "Bittet um Hilfe";
      return { title: `🆘 ${c.actor} — SICHERHEITSALARM`, body: `${why}. ${p[1] ? "Letzter Standort: " + p[1] : "Standort unbekannt."}` };
    },
    qa_question: (c) => ({ title: "❓ Neue Frage", body: `${c.actor || "Anonym"}: ${clip(c.preview, 80)}` }),
    qa_answer: (c) => ({ title: `💬 ${c.actor} hat deine Frage beantwortet`, body: clip(c.preview, 80) }),
    watch_party: (c) => ({ title: `🎬 ${c.actor} hat eine Watch-Party gestartet`, body: `${clip(c.preview.replace(/^watch\|/, ""), 60)} — zum Beitreten tippen` }),
    reminder: (c) => c.preview.startsWith("event|") ? { title: "📅 Termin beginnt bald", body: c.preview.slice(6) } : (c.preview.startsWith("message|") ? { title: "⏰ Erinnerung", body: "Zeit, auf die markierte Nachricht zu antworten." } : { title: "⏰ Erinnerung", body: c.preview.replace(/^task\|/, "") || "Deine Aufgabe ist fällig." }),
    mention: (c) => ({ title: c.actor, body: c.preview.startsWith("comment|") ? "Hat dich in einem Kommentar erwähnt." : c.preview.startsWith("story|") ? "Hat dich in der Story erwähnt." : "Hat dich in einem Beitrag erwähnt." }),
    group_activity: (c) => ({ title: c.actor, body: "Neue Nachricht im Gruppenchat." }),
    missed_call: (c) => {
      const k = callKind(c.preview);
      return { title: c.actor, body: k.video ? "Verpasster Videoanruf" : "Verpasster Sprachanruf" };
    },
    incoming_call: (c) => {
      const k = callKind(c.preview);
      return {
        title: c.actor,
        body: k.group
          ? `📞 ${k.groupTitle || "Gruppe"} • ${k.video ? "Videokonferenz" : "Sprachkonferenz"}`
          : `📞 Eingehender ${k.video ? "Videoanruf" : "Sprachanruf"}`,
      };
    },
    friend_request: (c) => ({ title: c.actor, body: "Hat dir eine Freundschaftsanfrage gesendet." }),
    friend_accepted: (c) => ({ title: c.actor, body: "Hat deine Freundschaftsanfrage angenommen." }),
    follow: (c) => ({ title: c.actor, body: "Folgt dir jetzt." }),
    follow_request: (c) => ({ title: c.actor, body: "Möchte dir folgen." }),
    follow_accepted: (c) => ({ title: c.actor, body: "Hat deine Folgeanfrage angenommen." }),
    like: (c) => ({ title: c.actor, body: "Gefällt dein Beitrag." }),
    story_like: (c) => ({ title: c.actor, body: "Gefällt deine Story." }),
    comment: (c) => ({ title: c.actor, body: "Hat deinen Beitrag kommentiert." }),
    save: (c) => ({ title: c.actor, body: "Hat deinen Beitrag gespeichert." }),
    reaction: (c) => {
      const r = reactionParts(c.preview);
      return { title: c.actor, body: r.text ? `Hat mit ${r.emoji} auf deine Nachricht reagiert: "${clip(r.text)}"` : `Hat mit ${r.emoji} auf deine Nachricht reagiert.` };
    },
    reply: (c) => { const r = replyParts(c.preview); return { title: c.actor, body: !r ? "Hat auf deinen Kommentar geantwortet." : r.comment ? `Hat auf deinen Kommentar „${clip(r.comment)}“ mit „${clip(r.reply)}“ geantwortet.` : `Hat mit „${clip(r.reply)}“ auf deinen Kommentar geantwortet.` }; },
    comment_like: (c) => ({ title: c.actor, body: c.preview ? `Gefällt dein Kommentar „${clip(c.preview)}“.` : "Gefällt dein Kommentar." }),
    story_reply: (c) => ({ title: c.actor, body: "Hat auf deine Story geantwortet." }),
    chick_invite: (c) => ({ title: "🐣 Küken-Einladung", body: `${c.actor} möchte mit dir das Küken „${c.preview}“ großziehen.` }),
    chick_hatched: (c) => ({ title: "🐣 Dein Küken ist geschlüpft!", body: `${c.actor} hat angenommen. „${c.preview}“ gehört jetzt euch!` }),
    chick_hungry: (c) => ({
      title: `🐥 ${c.preview || "Küken"}`,
      body: c.gender === "female" ? "Ich habe Hunger, Mama 🥺" : c.gender === "male" ? "Ich habe Hunger, Papa 🥺" : `${c.me}, ich bekomme Hunger 🥺`,
    }),
    chick_dying: (c) => ({ title: `🐥 ${c.preview || "Küken"}`, body: "Ich sterbe! Du hast mich seit 3 Tagen nicht gefüttert 😢" }),
    chick_died: (c) => ({ title: "🪦 Dein Küken ist gestorben", body: `${c.preview || "Küken"} ist nach 7 Tagen ohne Futter gestorben.` }),
    system: (c) => ({ title: "Juzzio", body: c.preview || "Du hast eine neue Benachrichtigung." }),
    push_test: () => ({ title: "Juzzio ✅", body: "Benachrichtigungen funktionieren. Diese Testnachricht kam vom Server." }),
  },
};

/** zh-tw → zh-TW, pa-arab → pa-Arab (translate.ts ile aynı; bağımsız birim testi için kopya). */
function googleLangCode(code: string): string {
  const c = code.trim();
  const i = c.indexOf("-");
  if (i < 0) return c.toLowerCase();
  const base = c.slice(0, i).toLowerCase();
  const sub = c.slice(i + 1);
  if (sub.length === 4) return `${base}-${sub[0].toUpperCase()}${sub.slice(1).toLowerCase()}`;
  return `${base}-${sub.toUpperCase()}`;
}

async function machineTranslate(text: string, target: string): Promise<string | null> {
  if (!text.trim()) return text;
  try {
    const url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&dt=t" +
      `&tl=${encodeURIComponent(googleLangCode(target))}&q=${encodeURIComponent(text)}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 2500);
    const res = await fetch(url, { signal: ctrl.signal });
    clearTimeout(timer);
    if (!res.ok) return null;
    const data = await res.json();
    if (!Array.isArray(data) || !Array.isArray(data[0])) return null;
    const out = (data[0] as unknown[]).map((seg) => (Array.isArray(seg) ? String(seg[0] ?? "") : "")).join("").trim();
    return out || null;
  } catch (_) {
    return null;
  }
}

export async function buildLocalizedPush(
  eventType: string,
  lang: string,
  ctx: Ctx,
): Promise<{ title: string; body: string }> {
  const code = (lang || "en").toLowerCase();
  const table = (code === "tr" || code === "en" || code === "de") ? T[code as PushLang] : T.en;
  const builder = table[eventType] ?? table.system;
  const safeCtx: Ctx = {
    actor: ctx.actor.trim() || "Juzzio",
    me: ctx.me.trim() || "Juzzio",
    preview: ctx.preview,
    gender: ctx.gender,
  };
  const built = builder(safeCtx);
  if (code === "tr" || code === "en" || code === "de") return built;

  // Diğer diller: başlık kişi adıysa olduğu gibi kalır; gövde çevrilir
  const translatedBody = await machineTranslate(built.body, code);
  const titleIsName = built.title === safeCtx.actor || built.title.startsWith("Juzzio");
  const translatedTitle = titleIsName ? built.title : (await machineTranslate(built.title, code)) ?? built.title;
  return { title: translatedTitle, body: translatedBody ?? built.body };
}
