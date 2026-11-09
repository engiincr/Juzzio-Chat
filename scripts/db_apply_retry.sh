#!/usr/bin/env bash
# =============================================================================
# Juzzio — kanonik veritabanı dosyasını CANLI veritabanına kilitlenmesiz uygular.
#
#  Sorun (v1.0.0 dağıtımı): psql dosyayı satır satır, her ifade için ayrı ağ gidiş-dönüşüyle
#  gönderir (Avrupa/ABD'deki CI → ap-south-1: binlerce ifade × ~200 ms = dakikalar). Bu
#  sürede transaction tabloları TEK TEK kilitler; aynı anda birden çok tabloya dokunan
#  uygulama sorguları (RLS fonksiyonları: profiles, rooms, room_participants …) ters sırada
#  kilit beklediği için "deadlock detected" oluşur.
#
#  Çözüm — her deneme TEK transaction (başarısız deneme hiçbir şeyi değiştirmez):
#   1) lock_timeout (vars. 8 sn): kilit alınamazsa hızla vazgeçilir, uygulama donmaz.
#   2) Önce public şemasındaki TÜM tablolar (ve izin varsa storage.objects/buckets) sabit
#      alfabetik sırayla ACCESS EXCLUSIVE kilitlenir. Kilitler alındıktan sonra dosyanın
#      geri kalanında kilit beklenmez → transaction ortasında deadlock imkânsızdır.
#   3) Dosyanın tamamı tek bir DO bloğu içinde EXECUTE edilir → sunucuya TEK seferde
#      gider ve sunucuda saniyeler içinde biter (kilitler çok kısa tutulur).
#   4) Kilit kaynaklı hatalarda artan beklemeyle yeniden denenir; diğer hatalar hemen
#      raporlanır. Bağlantı adresi hiçbir zaman yazdırılmaz.
#
#  Kullanım: scripts/db_apply_retry.sh <db_url> <sql_dosyası> [deneme_sayısı]
# =============================================================================
set -uo pipefail
URL="${1:?db_url gerekli}"
FILE="${2:?sql dosyası gerekli}"
TRIES="${3:-6}"
LOCK_TIMEOUT="${JUZZIO_LOCK_TIMEOUT:-8s}"
BASE_WAIT="${JUZZIO_RETRY_BASE_WAIT:-10}"
TAG='juzzio_deploy_body_7f3a'

if grep -q "\$${TAG}\$" "$FILE"; then
  echo "❌ Dosya ayırıcı etiketi içeriyor (\$${TAG}\$); etiketi değiştirin." >&2
  exit 2
fi
if grep -qE '^\s*\\' "$FILE"; then
  echo "❌ Dosya psql meta komutu (\\…) içeriyor; sunucu tarafı tek sorguda çalıştırılamaz." >&2
  exit 2
fi

WRAP="$(mktemp)"
trap 'rm -f "$WRAP"' EXIT
{
  printf "SET LOCAL lock_timeout = '%s';\n" "$LOCK_TIMEOUT"
  cat <<'SQL'
DO $juzzio_lock_all$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname, c.relname
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r', 'p') AND n.nspname = 'public'
        ORDER BY c.relname
    LOOP
        EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE', r.nspname, r.relname);
    END LOOP;
    -- storage tabloları (dosya politikaları burada değişir); yetki yoksa atlanır
    BEGIN
        IF to_regclass('storage.buckets') IS NOT NULL THEN LOCK TABLE storage.buckets IN ACCESS EXCLUSIVE MODE; END IF;
        IF to_regclass('storage.objects') IS NOT NULL THEN LOCK TABLE storage.objects IN ACCESS EXCLUSIVE MODE; END IF;
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'storage kilidi için yetki yok; atlandı';
    END;
END
$juzzio_lock_all$;
SQL
  printf 'DO $juzzio_apply$\nBEGIN\nEXECUTE $%s$\n' "$TAG"
  cat "$FILE"
  printf '\n$%s$;\nEND\n$juzzio_apply$;\n' "$TAG"
} > "$WRAP"

LOCK_RE='deadlock detected|canceling statement due to lock timeout|lock timeout|could not obtain lock|could not serialize access'

for i in $(seq 1 "$TRIES"); do
  start=$(date +%s)
  out="$(psql "$URL" -v ON_ERROR_STOP=1 -q -X --single-transaction -f "$WRAP" 2>&1)"
  rc=$?
  took=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ]; then
    echo "✅ $(basename "$FILE") uygulandı (deneme $i/$TRIES, ${took} sn)"
    exit 0
  fi
  if printf '%s\n' "$out" | grep -qE "$LOCK_RE"; then
    wait_s=$(( BASE_WAIT * i ))
    echo "⚠️  Kilit çakışması (deneme $i/$TRIES, ${took} sn) — transaction geri alındı, hiçbir şey değişmedi."
    printf '%s\n' "$out" | grep -E 'ERROR|DETAIL' | head -3
    if [ "$i" -lt "$TRIES" ]; then
      echo "   ${wait_s} sn sonra yeniden denenecek…"
      sleep "$wait_s"
    fi
    continue
  fi
  # Kilit dışı hata: yeniden denemek anlamsız. Dosya tek EXECUTE içinde çalıştığından
  # CONTEXT tüm dosyayı içerir; yalnız hata/ayrıntı/ipucu satırları gösterilir.
  printf '%s\n' "$out" | grep -E '^(psql:.*)?(ERROR|DETAIL|HINT):' | head -10
  echo "ℹ️  Hatanın satırını bulmak için: bash scripts/sql_test.sh juzzio_sqltest (yerel PostgreSQL)"
  exit "$rc"
done
echo "❌ $TRIES denemede de kilit alınamadı. Canlı trafik azken iş akışını yeniden çalıştırın."
exit 1
