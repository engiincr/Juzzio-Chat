// =============================================================================
// JUZZIO v0.0.9 — Supabase Edge Function: push-webhook (Üretim Güvenliği Sürümü)
// - Atomik İdempotency (23505 benzersiz kısıt koruması ile yarış koşulu engelleme)
// - Bütün Erken Dönüşlerde ve Hata Durumlarında push_delivery_logs Güncellemesi
// - Katı UNREGISTERED Ayrıştırması (HTTP 404 tuzağı kaldırıldı)
// - Hassas Veri Koruması ve Güvenli Hata Tanılaması
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { buildLocalizedPush, type Gender } from "../_shared/push_i18n.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-webhook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_EVENT_TYPES = new Set([
  "like",
  "comment",
  "reply",
  "follow",
  "follow_request",
  "follow_accepted",
  "friend_request",
  "friend_accepted",
  "story_like",
  "story_reply",
  "message",
  "missed_call",
  "incoming_call",
  "group_activity",
  "system",
  "chick_invite",
  "chick_hatched",
  "chick_hungry",
  "chick_dying",
  "chick_died",
  "reaction",
  "save",
]);

let cachedOAuthToken: string | null = null;
let cachedOAuthExpiryEpochSec = 0;
let cachedOAuthProjectId = "";

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----[A-Z ]+KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

interface ServiceAccountConfig {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

function loadServiceAccountConfig(): { config?: ServiceAccountConfig; error?: string } {
  const rawJson = (Deno.env.get("FCM_SERVICE_ACCOUNT_JSON") ?? "").trim();
  if (!rawJson) {
    return { error: "missing_secret:FCM_SERVICE_ACCOUNT_JSON" };
  }
  try {
    const parsed = JSON.parse(rawJson);
    const projectId = String(parsed.project_id ?? "").trim();
    const clientEmail = String(parsed.client_email ?? "").trim();
    const privateKey = String(parsed.private_key ?? "").trim();

    if (!projectId || !clientEmail || !privateKey) {
      return { error: "invalid_service_account_fields" };
    }

    const explicitProjectId = (Deno.env.get("FCM_PROJECT_ID") ?? "").trim();
    if (explicitProjectId && explicitProjectId !== projectId) {
      return { error: "project_id_mismatch_with_FCM_PROJECT_ID" };
    }

    return { config: { projectId, clientEmail, privateKey } };
  } catch (_) {
    return { error: "invalid_json:FCM_SERVICE_ACCOUNT_JSON" };
  }
}

async function getFcmHttpV1AccessToken(sa: ServiceAccountConfig): Promise<string | null> {
  const nowSec = Math.floor(Date.now() / 1000);
  if (
    cachedOAuthToken &&
    cachedOAuthProjectId === sa.projectId &&
    nowSec < cachedOAuthExpiryEpochSec - 60
  ) {
    return cachedOAuthToken;
  }

  try {
    const header = { alg: "RS256", typ: "JWT" };
    const claimSet = {
      iss: sa.clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: nowSec - 30,
      exp: nowSec + 3300,
    };

    const signingInput =
      `${base64UrlEncode(JSON.stringify(header))}.${base64UrlEncode(JSON.stringify(claimSet))}`;
    const keyBuffer = pemToArrayBuffer(sa.privateKey);
    const cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      keyBuffer,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const signatureBuffer = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      new TextEncoder().encode(signingInput),
    );
    const jwt = `${signingInput}.${base64UrlEncode(new Uint8Array(signatureBuffer))}`;

    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    if (!tokenRes.ok) return null;
    const tokenJson = await tokenRes.json();
    const accessToken = String(tokenJson.access_token ?? "").trim();
    const expiresIn = Number(tokenJson.expires_in ?? 3300);
    if (!accessToken) return null;

    cachedOAuthToken = accessToken;
    cachedOAuthProjectId = sa.projectId;
    cachedOAuthExpiryEpochSec = nowSec + expiresIn;
    return accessToken;
  } catch (_) {
    return null;
  }
}

const SOUND_ID_RE = /^juzzio_(tone|ring)_[a-z]{2,16}$/;

// deno-lint-ignore no-explicit-any
async function resolveRecipientSound(client: any, recipientId: string, actorId: string, eventType: string): Promise<{ channelId: string; soundName: string }> {
  const isCall = eventType === "missed_call" || eventType === "incoming_call";
  const isMessage = eventType === "message" || eventType === "group_activity" || eventType === "reaction";
  if ((!isCall && !isMessage) || !recipientId) return { channelId: "", soundName: "" };
  try {
    const { data } = await client
      .from("user_sound_prefs")
      .select("message_tone, ringtone, contact_prefs")
      .eq("user_id", recipientId)
      .maybeSingle();
    let tone = String(data?.message_tone ?? "juzzio_tone_glass");
    let ring = String(data?.ringtone ?? "juzzio_ring_aurora");
    const per = actorId && data?.contact_prefs && typeof data.contact_prefs === "object"
      ? (data.contact_prefs as Record<string, Record<string, string>>)[actorId]
      : undefined;
    if (per?.tone) tone = String(per.tone);
    if (per?.ring) ring = String(per.ring);
    const id = isCall ? ring : tone;
    if (!SOUND_ID_RE.test(id)) return { channelId: "", soundName: "" };
    return { channelId: `${isCall ? "juzzio_call_" : "juzzio_msg_"}${id}`, soundName: id };
  } catch (_) {
    return { channelId: "", soundName: "" };
  }
}

function resolveAndroidChannelId(eventType: string): string {
  if (eventType === "missed_call" || eventType === "incoming_call") return "juzzio_calls_priority_v2";
  if (eventType === "message" || eventType === "group_activity" || eventType === "reaction") {
    return "juzzio_high_priority_v2";
  }
  if (eventType === "system") return "juzzio_ota_update_v2";
  return "juzzio_social_priority_v2";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ ok: false, error: "method_not_allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const correlationId = crypto.randomUUID();

  try {
    const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
    const supabaseServiceRoleKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
    const supabaseAnonKey = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "server_misconfigured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const contentLength = Number(req.headers.get("content-length") ?? "0");
    if (contentLength > 65536) {
      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "payload_too_large" }),
        { status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const bodyJson = await req.json();
    const authHeader = (req.headers.get("authorization") ?? "").trim();
    const bearerToken = authHeader.toLowerCase().startsWith("bearer ")
      ? authHeader.slice(7).trim()
      : "";
    const webhookSecretHeader = (req.headers.get("x-webhook-secret") ?? "").trim();
    const expectedWebhookSecret = (Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "").trim();

    let recipientId = "";
    let actorId = "";
    let notificationId = "";
    let eventType = "system";
    let title = "Juzzio";
    let body = "";
    let targetId = "";
    let targetSecondaryId = "";
    let idempotencyKey = "";
    let isSelfTest = false;

    // --- YOL A: SELF TEST ---
    if (bodyJson.action === "self_test") {
      if (!bearerToken) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "missing_authorization_jwt" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const authClient = createClient(
        supabaseUrl,
        supabaseAnonKey || supabaseServiceRoleKey,
        { global: { headers: { Authorization: `Bearer ${bearerToken}` } } },
      );
      const { data: userData, error: userErr } = await authClient.auth.getUser(bearerToken);
      if (userErr || !userData?.user?.id) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "invalid_user_jwt" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const authenticatedUid = userData.user.id;
      if (bodyJson.recipient_id && bodyJson.recipient_id !== authenticatedUid) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "forbidden_cross_user_target" }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const oneMinuteAgo = new Date(Date.now() - 60 * 1000).toISOString();
      const { data: recentTests } = await adminClient
        .from("push_delivery_logs")
        .select("id")
        .eq("recipient_id", authenticatedUid)
        .like("idempotency_key", "selftest_%")
        .gte("created_at", oneMinuteAgo)
        .limit(1);

      if (recentTests && recentTests.length > 0) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "rate_limited_wait_60s" }),
          { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      isSelfTest = true;
      recipientId = authenticatedUid;
      actorId = authenticatedUid;
      eventType = "system";
      const { data: testerProfile } = await adminClient
        .from("profiles").select("app_lang").eq("id", authenticatedUid).maybeSingle();
      const testText = await buildLocalizedPush("push_test", String(testerProfile?.app_lang ?? "tr"), {
        actor: "Juzzio", me: "", preview: "", gender: "unspecified",
      });
      title = testText.title;
      body = testText.body;
      idempotencyKey = `selftest_${authenticatedUid}_${Math.floor(Date.now() / 60000)}`;
    } else {
      // --- YOL B: DATABASE WEBHOOK ---
      const isAuthorizedBySecret =
        expectedWebhookSecret.length > 0 && webhookSecretHeader === expectedWebhookSecret;
      const isAuthorizedByServiceRole =
        bearerToken.length > 0 && bearerToken === supabaseServiceRoleKey;

      if (!isAuthorizedBySecret && !isAuthorizedByServiceRole) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "unauthorized_webhook_caller" }),
          { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const webhookType = String(bodyJson.type ?? "").toUpperCase();
      const webhookSchema = String(bodyJson.schema ?? "public");
      const webhookTable = String(bodyJson.table ?? "");
      const record = bodyJson.record as Record<string, unknown> | undefined;

      if (webhookType !== "INSERT" || webhookSchema !== "public" || webhookTable !== "notifications" || !record?.id) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "unsupported_webhook_event" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      const notifRowId = String(record.id).trim();
      const { data: verifiedNotif, error: notifErr } = await adminClient
        .from("notifications")
        .select("*")
        .eq("id", notifRowId)
        .maybeSingle();

      if (notifErr || !verifiedNotif) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "notification_record_not_found" }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      notificationId = String(verifiedNotif.id);
      recipientId = String(verifiedNotif.recipient_id ?? "");
      actorId = String(verifiedNotif.actor_id ?? "");
      eventType = String(verifiedNotif.event_type ?? "system");

      if (!recipientId || !ALLOWED_EVENT_TYPES.has(eventType)) {
        return new Response(
          JSON.stringify({ ok: false, correlationId, error: "invalid_recipient_or_event_type" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 1. DÜZELTME: Self Actor Kontrolü (Şema uyumlu konsol logu ve 200 OK)
      if (actorId && actorId === recipientId) {
        console.warn(`[push-webhook] [${correlationId}] Skipped self actor notification.`);
        return new Response(
          JSON.stringify({ ok: true, correlationId, status: "skipped_self_actor" }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      // 2. DÜZELTME: Güvenli Engelleme Kontrolü (Hata yutulmaz, gönderim durdurulur)
      if (actorId) {
        const { data: isBlocked, error: blockErr } = await adminClient.rpc("is_blocked_between", {
          p_user_a: recipientId,
          p_user_b: actorId,
        });

        if (blockErr) {
          console.error("push_block_check_failed", {
            correlationId,
            code: blockErr.code ?? "unknown",
          });
          return new Response(
            JSON.stringify({ ok: false, correlationId, error: "block_check_error" }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }

        if (isBlocked === true) {
          return new Response(
            JSON.stringify({ ok: true, correlationId, status: "skipped_blocked" }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
          );
        }
      }

      // Alıcının uygulama dili, görünen adı ve (gizli) cinsiyeti — metin onun dilinde üretilir
      const { data: recipientProfile } = await adminClient
        .from("profiles")
        .select("app_lang, display_name, username")
        .eq("id", recipientId)
        .maybeSingle();
      const { data: recipientPrivate } = await adminClient
        .from("profile_private")
        .select("gender")
        .eq("user_id", recipientId)
        .maybeSingle();
      const gender = (["female", "male"].includes(String(recipientPrivate?.gender ?? ""))
        ? String(recipientPrivate?.gender)
        : "unspecified") as Gender;
      const built = await buildLocalizedPush(eventType, String(recipientProfile?.app_lang ?? "tr"), {
        actor: String(verifiedNotif.actor_display_name || verifiedNotif.actor_username || "Juzzio"),
        me: String(recipientProfile?.display_name || recipientProfile?.username || "Juzzio"),
        preview: String(verifiedNotif.preview_text ?? ""),
        gender,
      });
      title = built.title;
      body = built.body;
      targetId = String(verifiedNotif.target_id ?? "");
      targetSecondaryId = String(verifiedNotif.target_secondary_id ?? "");
      idempotencyKey = `notif_${notificationId}`;
    }

    // v0.7.0: alıcının ses tercihi (varsayılan + kişiye özel) → sese özel Android kanalı
    const sound = await resolveRecipientSound(adminClient, recipientId, actorId, eventType);
    const channelId = sound.channelId || resolveAndroidChannelId(eventType);

    // -------------------------------------------------------------------------
    // ATOMİK İDEMPOTENCY SAHİPLİĞİ (Yarış Koşulu Koruması - 23505 Unique Violation)
    // -------------------------------------------------------------------------
    const { data: insertedLog, error: insertLogErr } = await adminClient
      .from("push_delivery_logs")
      .insert({
        notification_id: notificationId || null,
        idempotency_key: idempotencyKey,
        recipient_id: recipientId,
        actor_id: actorId || null,
        event_type: eventType,
        channel_id: channelId,
        delivery_status: "processing",
        target_tokens_count: 0,
        fcm_accepted_count: 0,
        fcm_error_code: "",
      })
      .select("id")
      .maybeSingle();

    if (insertLogErr) {
      if (insertLogErr.code === "23505") {
        console.warn(`[push-webhook] [${correlationId}] Duplicate concurrent request intercepted.`);
        return new Response(
          JSON.stringify({
            ok: true,
            correlationId,
            status: "skipped_duplicate",
            reason: "concurrent_request_already_processing",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }

      console.error("push_delivery_claim_failed", {
        code: insertLogErr.code ?? "unknown",
        correlationId,
      });

      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "delivery_claim_failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const logId = insertedLog?.id;
    if (!logId) {
      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "delivery_log_id_missing" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // -------------------------------------------------------------------------
    // ALICININ TOKENLARINI SORGULA
    // -------------------------------------------------------------------------
    const { data: tokenRows, error: tokenErr } = await adminClient
      .from("user_push_tokens")
      .select("*")
      .eq("user_id", recipientId)
      .eq("is_active", true)
      .eq("notify_enabled", true);

    if (tokenErr) {
      await adminClient
        .from("push_delivery_logs")
        .update({
          delivery_status: "failed",
          fcm_error_code: "db_token_fetch_error",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);

      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "db_token_fetch_error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!tokenRows || tokenRows.length === 0) {
      await adminClient
        .from("push_delivery_logs")
        .update({
          delivery_status: "no_active_tokens",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);

      return new Response(
        JSON.stringify({
          ok: true,
          correlationId,
          status: "no_active_tokens",
          registeredTokensCount: 0,
          fcmAcceptedCount: 0,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Kategori Filtrelemesi
    const eligibleTokens = tokenRows.filter((row: Record<string, unknown>) => {
      if (isSelfTest) return true;
      if (eventType === "message" || eventType === "reaction") return row.notify_messages !== false;
      if (eventType === "group_activity") return row.notify_groups !== false;
      if (eventType === "missed_call" || eventType === "incoming_call") return row.notify_calls !== false;
      if (eventType.includes("follow") || eventType.includes("friend")) {
        return row.notify_follows !== false;
      }
      if (eventType === "like" || eventType === "comment" || eventType === "reply" || eventType === "save") {
        return row.notify_likes_comments !== false;
      }
      if (eventType.includes("story")) return row.notify_stories !== false;
      if (eventType === "system") return row.notify_system !== false;
      return true;
    });

    if (eligibleTokens.length === 0) {
      await adminClient
        .from("push_delivery_logs")
        .update({
          delivery_status: "skipped_preference",
          target_tokens_count: tokenRows.length,
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);

      return new Response(
        JSON.stringify({
          ok: true,
          correlationId,
          status: "skipped_preference",
          registeredTokensCount: tokenRows.length,
          fcmAcceptedCount: 0,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // --- FCM SERVICE ACCOUNT VE OAUTH ---
    const saResult = loadServiceAccountConfig();
    if (!saResult.config) {
      await adminClient
        .from("push_delivery_logs")
        .update({
          delivery_status: "failed",
          target_tokens_count: eligibleTokens.length,
          fcm_error_code: saResult.error ?? "missing_service_account",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);

      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "fcm_service_account_not_configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const oauthToken = await getFcmHttpV1AccessToken(saResult.config);
    if (!oauthToken) {
      await adminClient
        .from("push_delivery_logs")
        .update({
          delivery_status: "failed",
          target_tokens_count: eligibleTokens.length,
          fcm_error_code: "oauth_token_exchange_failed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", logId);

      return new Response(
        JSON.stringify({ ok: false, correlationId, error: "oauth_token_exchange_failed" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // --- FCM HTTP V1 GÖNDERİM ---
    const fcmEndpoint =
      `https://fcm.googleapis.com/v1/projects/${saResult.config.projectId}/messages:send`;

    let fcmAcceptedCount = 0;
    const unregisteredTokenIds: string[] = [];
    const errorCodes: string[] = [];

    for (const tokenRow of eligibleTokens) {
      const registrationToken = String(tokenRow.fcm_token ?? "").trim();
      if (!registrationToken) continue;

      const fcmBody = {
        message: {
          token: registrationToken,
          notification: { title, body },
          data: {
            type: eventType,
            event_type: eventType,
            notification_id: notificationId,
            target_id: targetId,
            target_secondary_id: targetSecondaryId,
            actor_id: actorId,
            channel_id: channelId,
            title,
            body,
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channelId,
              sound: sound.soundName || "default",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        },
      };

      const fcmRes = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${oauthToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(fcmBody),
      });

      if (fcmRes.ok) {
        fcmAcceptedCount++;
      } else {
        let fcmErrorCode = `HTTP_${fcmRes.status}`;
        let isStrictUnregistered = false;

        // 3. DÜZELTME: Katı ve Doğrulanmış UNREGISTERED Ayrıştırması
        try {
          const errJson = await fcmRes.json();
          const details = errJson?.error?.details;

          if (Array.isArray(details)) {
            const unregisteredDetail = details.find(
              (detail: Record<string, unknown>) =>
                detail?.errorCode === "UNREGISTERED",
            );

            if (unregisteredDetail) {
              fcmErrorCode = "UNREGISTERED";
              isStrictUnregistered = true;
            } else {
              const firstErrorDetail = details.find(
                (detail: Record<string, unknown>) =>
                  typeof detail?.errorCode === "string",
              );

              if (firstErrorDetail) {
                fcmErrorCode = String(firstErrorDetail.errorCode);
              }
            }
          }
        } catch (_) {}

        errorCodes.push(fcmErrorCode);

        if (isStrictUnregistered) {
          unregisteredTokenIds.push(String(tokenRow.id));
        }
      }
    }

    if (unregisteredTokenIds.length > 0) {
      await adminClient
        .from("user_push_tokens")
        .update({
          is_active: false,
          invalidated_reason: "UNREGISTERED",
          updated_at: new Date().toISOString(),
        })
        .in("id", unregisteredTokenIds);
    }

    const finalStatus = fcmAcceptedCount > 0 ? "fcm_accepted" : "failed";
    const { error: updateErr } = await adminClient
      .from("push_delivery_logs")
      .update({
        delivery_status: finalStatus,
        target_tokens_count: eligibleTokens.length,
        fcm_accepted_count: fcmAcceptedCount,
        fcm_error_code: errorCodes.join(",").slice(0, 120),
        completed_at: new Date().toISOString(),
      })
      .eq("id", logId);

    if (updateErr) {
      console.error("push_delivery_log_update_failed", { code: updateErr.code ?? "unknown", correlationId });
    }

    return new Response(
      JSON.stringify({
        ok: fcmAcceptedCount > 0,
        correlationId,
        status: finalStatus,
        registeredTokensCount: eligibleTokens.length,
        fcmAcceptedCount,
        unregisteredCleanedCount: unregisteredTokenIds.length,
        errorCodes,
      }),
      {
        status: fcmAcceptedCount > 0 ? 200 : 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error(`[push-webhook] [${correlationId}] Unhandled exception`);
    return new Response(
      JSON.stringify({ ok: false, correlationId, error: "internal_webhook_error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});