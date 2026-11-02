// =============================================================================
// JUZZIO v0.9.0 (ek paket N-D) — Mesaj bildirimi önizleme kipleri
//  full   → sunucu yine GENEL metin gönderir; cihaz mesajı kendisi çözüp gösterir
//  sender → gönderen adı + genel metin (cihaz çözmeye çalışmaz)
//  hidden → "Juzzio — Yeni mesaj" (gönderen adı, kişi ve mesaj kimliği de gönderilmez)
// Hiçbir kipte FCM yükünde mesaj metni bulunmaz (E2EE ve grup mesajları dahil).
// =============================================================================

export const MESSAGE_EVENTS = new Set(["message", "group_activity", "story_reply", "reaction"]);
export type PreviewMode = "full" | "sender" | "hidden";

const HIDDEN_BODY: Record<string, string> = {
  tr: "Yeni mesaj",
  en: "New message",
  de: "Neue Nachricht",
};

export function normalizePreviewMode(v: string): PreviewMode {
  const m = (v || "").trim().toLowerCase();
  return m === "sender" || m === "hidden" ? m : "full";
}

export function messagePushView(
  eventType: string,
  rawMode: string,
  lang: string,
  title: string,
  body: string,
): { mode: PreviewMode; title: string; body: string; dataOnly: boolean } {
  if (!MESSAGE_EVENTS.has(eventType)) {
    return { mode: "full", title, body, dataOnly: false };
  }
  const mode = normalizePreviewMode(rawMode);
  if (mode === "hidden") {
    const code = (lang || "en").toLowerCase().split(/[-_]/)[0];
    return { mode, title: "Juzzio", body: HIDDEN_BODY[code] ?? HIDDEN_BODY.en, dataOnly: true };
  }
  // 'sender' kipinde tepki bildirimindeki mesaj alıntısı ("…") da çıkarılır
  if (mode === "sender" && eventType === "reaction") {
    return { mode, title, body: stripQuotedExcerpt(body), dataOnly: true };
  }
  return { mode, title, body, dataOnly: true };
}

/** Tepki gövdesindeki tırnaklı mesaj alıntısını çıkarır (tr/en/de şablonları). */
export function stripQuotedExcerpt(body: string): string {
  let out = body.replace(/"[^"]*"/g, "").replace(/\s+/g, " ").trim();
  out = out.replace(/[\s:]+$/u, "").replace(/\s+\./g, ".");
  if (!/[.!?]$/.test(out)) out += ".";
  return out.charAt(0).toLocaleUpperCase() + out.slice(1);
}
