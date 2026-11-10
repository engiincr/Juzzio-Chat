#!/usr/bin/env bash
# Juzzio — push öncesi yerel kontrol (Flutter gerekmez; Termux'ta da çalışır: pkg install python)
# Kullanım: bash scripts/precheck.sh
# CI'daki "Analiz ve Test" adımında yakalanan hata sınıflarının çoğunu push'tan ÖNCE bulur:
#  parantez/dize dengesi, belirsiz içe aktarma, yönetici kayıt cümleleri, yerelleştirme,
#  gizli bilgi taraması, yasal metin güncelliği, sürüm bilgisi.
set -u
cd "$(dirname "$0")/.."
fail=0
run() { echo "▶ $1"; shift; if ! "$@"; then fail=1; echo "✖ başarısız"; fi; }
run "Dart sözcük denetimi"      python3 scripts/dart_lexcheck.py
run "Belirsiz içe aktarma"      python3 scripts/dart_import_conflicts.py
run "CI koruma kapısı"          python3 scripts/ci_guards.py
run "Yerelleştirme"             python3 scripts/l10n_tools.py check
run "Gizli bilgi taraması"      python3 scripts/check_secrets.py
run "Yasal metinler"            python3 scripts/gen_legal.py --check
cp version.json /tmp/juzzio_version.bak 2>/dev/null || true
run "Sürüm bilgisi"             python3 scripts/release_meta.py check
cp /tmp/juzzio_version.bak version.json 2>/dev/null || true
if [ "$fail" = 0 ]; then echo "✔ Tüm yerel kontroller geçti — push edebilirsin"; else echo "✖ Yukarıdaki hatayı düzeltmeden push etme"; fi
exit $fail
