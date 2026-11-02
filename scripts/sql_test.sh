#!/usr/bin/env bash
# =============================================================================
# JUZZIO — Kanonik SQL doğrulaması (yerel PostgreSQL / CI servis konteyneri)
#
#   1) Boş veritabanı + Supabase iskeleti
#   2) supabase/juzzio_database.sql  → tek transaction, 2 kez (idempotentlik)
#   3) supabase/tests/juzzio_database_tests.sql (RLS pozitif/negatif testleri)
#
# Ortam değişkenleri: PGHOST, PGPORT, PGUSER (psql standartları). Gerçek
# Supabase projesine KARŞI ÇALIŞTIRMAYIN — betik hedef veritabanını siler.
# Kullanım: bash scripts/sql_test.sh [db_adı]
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
DB="${1:-juzzio_sqltest}"
case "$DB" in *test*) ;; *) echo "Güvenlik: veritabanı adı 'test' içermeli" >&2; exit 2;; esac
PSQL=(psql -X -q -v ON_ERROR_STOP=1 -d "$DB")

dropdb --if-exists "$DB"
createdb "$DB"
# Supabase varsayılanı: veritabanı search_path içinde extensions şeması bulunur
psql -X -q -d "$DB" -c "ALTER DATABASE \"$DB\" SET search_path = \"\$user\", public, extensions" >/dev/null
"${PSQL[@]}" -f supabase/tests/supabase_stub_bootstrap.sql >/dev/null
for i in 1 2; do
  echo "▶ Kanonik SQL uygulanıyor (#$i)…"
  "${PSQL[@]}" --single-transaction -f supabase/juzzio_database.sql >/tmp/juzzio_sql_apply_$i.log 2>&1 || {
    echo "✖ Kanonik SQL #$i başarısız:"; grep -n "ERROR" -A3 /tmp/juzzio_sql_apply_$i.log | head -40; exit 1; }
done
echo "✔ Kanonik SQL 2 kez hatasız uygulandı"
"${PSQL[@]}" -f supabase/tests/test_fixtures.sql >/dev/null
echo "▶ Veritabanı testleri…"
OUT="$("${PSQL[@]}" -f supabase/tests/juzzio_database_tests.sql 2>&1)" || { echo "$OUT" | grep -E "ERROR|FAIL|psql:.*(gset|error|hata)" | head -30; echo "$OUT" | tail -3; echo "✖ Testler başarısız"; exit 1; }
# İlk blok (P0001 senaryosu) bilerek hata üretir; gerçek başarısızlık "FAIL " satırıdır
# ve ON_ERROR_STOP=1 bölümündeki her hata psql'i sıfırdan farklı kodla durdurur.
if echo "$OUT" | grep -qE "FAIL "; then
  echo "$OUT" | grep -nE "FAIL " | head -30
  echo "✖ Testler başarısız"; exit 1
fi
echo "$OUT" | grep -E "TÜM .* GEÇTİ" | sed "s/^ */  ✔ /" || true
PASS=$(echo "$OUT" | grep -c "PASS " || true)
echo "✔ Veritabanı testleri geçti ($PASS doğrulama)"
