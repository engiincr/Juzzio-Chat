// =============================================================================
// JUZZIO — Supabase Edge Function: storage-cleanup (v0.9.0, G22)
//
// Supabase, storage.objects satırlarının SQL ile silinmesine izin vermez; dosyalar
// yalnızca Storage API ile silinir. Veritabanı tetikleyicileri silinecek nesneleri
// `juzzio_storage_cleanup_queue` kuyruğuna yazar; bu fonksiyon kuyruğu boşaltır.
//
// Kimlik (ikisinden biri zorunlu):
//   • x-cron-secret başlığı = STORAGE_CLEANUP_SECRET (GitHub Actions bakım iş akışı)
//   • Kullanıcı JWT + 'settings' izni (yönetici panelinden elle tetikleme)
// Kuyrukta olmayan HİÇBİR yol silinmez; istemciden yol kabul edilmez.
// =============================================================================

import { adminClient, constantTimeEqual, corsHeaders, jsonResponse, requireUser } from "../_shared/auth.ts";

const ALLOWED_BUCKETS = new Set(["stories", "avatars", "voice-notes", "chat-media", "posts", "reels"]);
const MAX_ITEMS_PER_RUN = 200;
const MAX_PREFIX_OBJECTS = 1000;

type QueueRow = { id: number; bucket: string; object_name: string; is_prefix: boolean };

/** Bir klasör önekinin altındaki tüm dosya yollarını (en fazla 3 seviye) listeler. */
async function listPrefix(bucket: string, prefix: string): Promise<{ paths: string[]; complete: boolean }> {
  const admin = adminClient();
  const paths: string[] = [];
  const queue: { dir: string; depth: number }[] = [{ dir: prefix.replace(/\/+$/, ""), depth: 0 }];
  while (queue.length > 0) {
    const { dir, depth } = queue.shift()!;
    let offset = 0;
    for (;;) {
      const { data, error } = await admin.storage.from(bucket).list(dir, { limit: 100, offset });
      if (error) throw new Error(`list_failed:${bucket}`);
      const items = (data ?? []) as { name: string; id: string | null }[];
      for (const it of items) {
        const full = `${dir}/${it.name}`;
        if (it.id === null) {
          if (depth < 3) queue.push({ dir: full, depth: depth + 1 });
        } else {
          paths.push(full);
          if (paths.length >= MAX_PREFIX_OBJECTS) return { paths, complete: false };
        }
      }
      if (items.length < 100) break;
      offset += 100;
    }
  }
  return { paths, complete: true };
}

async function removePaths(bucket: string, paths: string[]): Promise<void> {
  const admin = adminClient();
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
    if (error) throw new Error(`remove_failed:${bucket}`);
  }
}

async function authorized(req: Request): Promise<boolean> {
  const expected = (Deno.env.get("STORAGE_CLEANUP_SECRET") ?? "").trim();
  const given = (req.headers.get("x-cron-secret") ?? "").trim();
  if (expected.length >= 24 && given && constantTimeEqual(given, expected)) return true;
  const user = await requireUser(req);
  if (!user) return false;
  const { data } = await adminClient().rpc("juzzio_has_permission", { p_perm: "settings", p_user: user.id });
  return data === true;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);
  try {
    if (!(await authorized(req))) return jsonResponse({ error: "unauthorized" }, 401);
    const admin = adminClient();

    // pg_cron yoksa süresi dolan içerik de buradan temizlenir (idempotent)
    const { data: purged } = await admin.rpc("juzzio_purge_expired_content");

    const { data: claimed, error } = await admin.rpc("juzzio_storage_cleanup_claim", { p_limit: MAX_ITEMS_PER_RUN });
    if (error) {
      console.error("cleanup_claim_failed", error.code ?? "unknown");
      return jsonResponse({ error: "claim_failed" }, 500);
    }
    const rows = (claimed ?? []) as QueueRow[];
    const done: number[] = [];
    const failed: number[] = [];
    let removedObjects = 0;

    // Tekil dosyalar: bucket başına toplu silme
    const byBucket = new Map<string, QueueRow[]>();
    for (const r of rows.filter((x) => !x.is_prefix)) {
      if (!ALLOWED_BUCKETS.has(r.bucket) || r.object_name.includes("..")) {
        done.push(r.id); // geçersiz kayıt: işlenmiş say, asla silme denemesi yapma
        continue;
      }
      byBucket.set(r.bucket, [...(byBucket.get(r.bucket) ?? []), r]);
    }
    for (const [bucket, list] of byBucket) {
      try {
        await removePaths(bucket, list.map((r) => r.object_name));
        removedObjects += list.length;
        done.push(...list.map((r) => r.id));
      } catch (_) {
        failed.push(...list.map((r) => r.id));
      }
    }

    // Klasör önekleri (hesap silme)
    for (const r of rows.filter((x) => x.is_prefix)) {
      if (!ALLOWED_BUCKETS.has(r.bucket) || r.object_name.includes("..") || !/^[0-9a-f-]{36}\/$/i.test(r.object_name)) {
        done.push(r.id);
        continue;
      }
      try {
        const { paths, complete } = await listPrefix(r.bucket, r.object_name);
        await removePaths(r.bucket, paths);
        removedObjects += paths.length;
        // Tamamlanmadıysa (çok dosya) kayıt açık kalır, bir sonraki çalıştırmada devam eder
        if (complete) done.push(r.id);
      } catch (_) {
        failed.push(r.id);
      }
    }

    if (done.length > 0) await admin.rpc("juzzio_storage_cleanup_done", { p_ids: done, p_error: "" });
    if (failed.length > 0) await admin.rpc("juzzio_storage_cleanup_done", { p_ids: failed, p_error: "storage_api_error" });
    return jsonResponse({ ok: true, purged: purged ?? null, claimed: rows.length, done: done.length, failed: failed.length, removedObjects });
  } catch (e) {
    console.error("storage-cleanup error", e instanceof Error ? e.message : "unknown");
    return jsonResponse({ error: "cleanup_failed" }, 500);
  }
});
