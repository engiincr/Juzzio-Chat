#!/usr/bin/env bash
# =============================================================================
# Juzzio — kanonik veritabanı dosyasını CANLI veritabanına güvenle uygular.
#
#  Dosya tek transaction içinde uygulanır (hata olursa hiçbir şey değişmez). Canlı
#  trafikte uygulamanın açık sorguları ile şema kilitleri çakışabilir:
#    • "deadlock detected"  → PostgreSQL bir tarafı iptal eder (transaction geri alınır)
#    • uzun kilit beklemesi → arkasında bekleyen tüm uygulama sorguları da donar
#  Bu yüzden:
#    • lock_timeout (varsayılan 8 sn): kilit alınamazsa hızlıca vazgeçilir, uygulama donmaz
#    • kilit kaynaklı hatalarda artan bekleme ile yeniden denenir (varsayılan 6 deneme)
#    • başka her hata hemen ve olduğu gibi raporlanır (yeniden denenmez)
#  Bağlantı adresi hiçbir zaman yazdırılmaz.
#
#  Kullanım: scripts/db_apply_retry.sh <db_url> <sql_dosyası> [deneme_sayısı]
# =============================================================================
set -uo pipefail
URL="${1:?db_url gerekli}"
FILE="${2:?sql dosyası gerekli}"
TRIES="${3:-6}"
LOCK_TIMEOUT="${JUZZIO_LOCK_TIMEOUT:-8s}"
BASE_WAIT="${JUZZIO_RETRY_BASE_WAIT:-10}"

# lock_timeout her rol için ayarlanabilir (süper kullanıcı gerektirmez)
export PGOPTIONS="-c lock_timeout=${LOCK_TIMEOUT}"

LOCK_RE='deadlock detected|canceling statement due to lock timeout|lock timeout|could not obtain lock|could not serialize access'

for i in $(seq 1 "$TRIES"); do
  out="$(psql "$URL" -v ON_ERROR_STOP=1 -q -X --single-transaction -f "$FILE" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✅ $(basename "$FILE") uygulandı (deneme $i/$TRIES)"
    exit 0
  fi
  if printf '%s\n' "$out" | grep -qE "$LOCK_RE"; then
    wait_s=$(( BASE_WAIT * i ))
    echo "⚠️  Kilit çakışması (deneme $i/$TRIES) — transaction geri alındı, hiçbir şey değişmedi."
    printf '%s\n' "$out" | grep -E '^psql:.*(ERROR|DETAIL)|^(ERROR|DETAIL)' | head -3
    if [ "$i" -lt "$TRIES" ]; then
      echo "   ${wait_s} sn sonra yeniden denenecek…"
      sleep "$wait_s"
    fi
    continue
  fi
  # Kilit dışı hata: yeniden denemek anlamsız — NOTICE gürültüsü olmadan raporla
  printf '%s\n' "$out" | grep -v 'NOTICE:' | tail -30
  exit "$rc"
done
echo "❌ $TRIES denemede de kilit çakışması sürdü. Canlı trafik azken yeniden çalıştırın (iş akışını yeniden başlatmak yeterli)."
exit 1
