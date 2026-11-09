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
#   2) Önce dosyanın dokunduğu TÜM ilişkiler (public tablo/view/matview + auth.users,
#      storage.buckets/objects, realtime.messages, cron.job) sabit sırayla ACCESS EXCLUSIVE
#      kilitlenir. Kilitler alındıktan sonra dosyanın
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
    -- Dosyanın DDL ile dokunduğu HER ilişki (public tablo + view + matview ve
    -- Supabase'in auth/storage/realtime/cron tabloları) tek, sabit sırayla kilitlenir.
    FOR r IN
        SELECT n.nspname, c.relname
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE (n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm') AND NOT c.relispartition)
           OR (n.nspname, c.relname) IN (('auth', 'users'), ('storage', 'buckets'),
                                         ('storage', 'objects'), ('realtime', 'messages'),
                                         ('cron', 'job'))
        ORDER BY n.nspname, c.relname
    LOOP
        BEGIN
            EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE', r.nspname, r.relname);
        EXCEPTION WHEN insufficient_privilege OR wrong_object_type OR feature_not_supported THEN
            RAISE NOTICE 'ön kilit atlandı: %.%', r.nspname, r.relname;
        END;
    END LOOP;
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
  # NOT: "printf | grep -q" + pipefail → grep erken çıkınca printf SIGPIPE alır ve eşleşme
  # "başarısız" sayılır (v1.0.0 CI: deadlock yeniden denenmedi). Bash eşleşmesi kullanılır.
  if [[ "$out" =~ $LOCK_RE ]]; then
    wait_s=$(( BASE_WAIT * i ))
    echo "⚠️  Kilit çakışması (deneme $i/$TRIES, ${took} sn) — transaction geri alındı, hiçbir şey değişmedi."
    grep -E 'ERROR|DETAIL' <<<"$out" | head -3 || true
    # Hangi ilişki? (oid → ad; teşhis için, ayrı salt-okunur sorgu)
    oids="$(grep -oE 'relation [0-9]+' <<<"$out" | grep -oE '[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')"
    if [ -n "$oids" ]; then
      names="$(psql "$URL" -X -At -c "SELECT string_agg(oid::regclass::text, ', ') FROM pg_class WHERE oid IN ($oids)" 2>/dev/null || true)"
      [ -n "$names" ] && echo "   Çakışan ilişki(ler): $names"
    fi
    if [ "$i" -lt "$TRIES" ]; then
      echo "   ${wait_s} sn sonra yeniden denenecek…"
      sleep "$wait_s"
    fi
    continue
  fi
  # Kilit dışı hata: yeniden denemek anlamsız. Dosya tek EXECUTE içinde çalıştığından
  # CONTEXT tüm dosyayı içerir; yalnız hata/ayrıntı/ipucu satırları gösterilir.
  grep -E '^(psql:.*)?(ERROR|DETAIL|HINT):' <<<"$out" | head -10 || true
  echo "ℹ️  Hatanın satırını bulmak için: bash scripts/sql_test.sh juzzio_sqltest (yerel PostgreSQL)"
  exit "$rc"
done
echo "❌ $TRIES denemede de kilit alınamadı. Canlı trafik azken iş akışını yeniden çalıştırın."
exit 1
