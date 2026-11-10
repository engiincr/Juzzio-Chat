#!/usr/bin/env bash
# =============================================================================
# JUZZIO — GitHub "Contributors" listesinden Claude'u kaldırma (bir kez çalıştırılır)
#
# Neden görünüyor: 1–2 Kasım 2026'da main dalına doğrudan gönderilen 20 commit'in yazarı
# "Claude <noreply@anthropic.com>"; GitHub bu adresi "claude" hesabına bağlıyor. Listeden
# çıkması için bu commit'lerin yazarı engiincr olarak YENİDEN YAZILMALI ve main dalı zorla
# gönderilmeli (force push). Bu işlem main dalının geçmişini değiştirir:
#   • Önce main'in tam kopyası "yedek/claude-yazar-oncesi" dalı olarak GitHub'a yüklenir
#     (hiçbir şey kaybolmaz; dal/etiket/sürüm SİLİNMEZ).
#   • Commit içeriği (dosyalar) birebir aynı kalır; yalnız yazar adı/e-postası ve mesajlardaki
#     "Co-Authored-By: Claude" / "Claude-Session:" satırları değişir.
#   • Zorla gönderim --force-with-lease ile yapılır (arada başka biri push ettiyse durur).
#   • En üste "[skip ci]" etiketli boş bir commit eklenir → GitHub Actions yeniden derleme/
#     sürüm yayımlama başlatmaz.
# GitHub katkıcı grafiği önbelleklidir; değişikliğin görünmesi birkaç saat sürebilir.
#
# Kullanım (Termux, depo klasöründe):  bash scripts/github_yazar_duzelt.sh
# =============================================================================
set -euo pipefail

NEW_NAME="engiincr"
NEW_EMAIL="engiincr@users.noreply.github.com"
OLD_EMAIL="noreply@anthropic.com"
BRANCH="main"
BACKUP="yedek/claude-yazar-oncesi"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Bu klasör bir git deposu değil. Önce: cd ~/Juzzio-Chat"; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
  echo "Kaydedilmemiş değişiklik var. Önce commit/push et, sonra tekrar çalıştır."; exit 1
fi

git fetch origin
git checkout "$BRANCH"
git pull --ff-only origin "$BRANCH"

COUNT=$(git log --format='%ae%n%ce' "$BRANCH" | grep -c "^${OLD_EMAIL}$" || true)
TRAILERS=$(git log --format='%b' "$BRANCH" | grep -ciE '^(co-authored-by: claude|claude-session:)' || true)
echo "Claude yazarlı/işlemeli kayıt: $COUNT · mesajdaki Claude satırı: $TRAILERS"
if [ "$COUNT" = "0" ] && [ "$TRAILERS" = "0" ]; then echo "Düzeltilecek bir şey yok."; exit 0; fi

# 1) Yedek dal (GitHub'da da saklanır)
if git ls-remote --exit-code --heads origin "$BACKUP" >/dev/null 2>&1; then
  echo "Yedek dal zaten var: $BACKUP (üzerine yazılmaz)"
else
  git branch -f "$BACKUP" "$BRANCH"
  git push origin "$BACKUP"
fi

# 2) Geçmişi yeniden yaz (yalnız main; etiketler olduğu gibi kalır)
export FILTER_BRANCH_SQUELCH_WARNING=1
git filter-branch -f \
  --env-filter "
if [ \"\$GIT_AUTHOR_EMAIL\" = \"$OLD_EMAIL\" ]; then
  export GIT_AUTHOR_NAME=\"$NEW_NAME\"; export GIT_AUTHOR_EMAIL=\"$NEW_EMAIL\"
fi
if [ \"\$GIT_COMMITTER_EMAIL\" = \"$OLD_EMAIL\" ]; then
  export GIT_COMMITTER_NAME=\"$NEW_NAME\"; export GIT_COMMITTER_EMAIL=\"$NEW_EMAIL\"
fi" \
  --msg-filter "sed -E '/^[Cc]o-[Aa]uthored-[Bb]y: Claude/d; /^Claude-Session:/d'" \
  -- "$BRANCH"

LEFT=$(git log --format='%ae%n%ce' "$BRANCH" | grep -c "^${OLD_EMAIL}$" || true)
echo "Yeniden yazım sonrası Claude kaydı: $LEFT"
[ "$LEFT" = "0" ] || { echo "Beklenmeyen durum; gönderim yapılmadı. Yedek: $BACKUP"; exit 1; }

# 3) CI tetiklenmesin ve gönder
git -c user.name="$NEW_NAME" -c user.email="$NEW_EMAIL" commit --allow-empty -m "chore: commit yazar bilgisi düzeltildi [skip ci]"
git push --force-with-lease origin "$BRANCH"
rm -rf .git/refs/original
echo "Tamam. GitHub katkıcı listesi birkaç saat içinde güncellenir. Yedek dal: $BACKUP"
