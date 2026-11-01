#!/usr/bin/env bash
# =============================================================================
# JUZZIO — Güvenli GitHub Push (Termux / Linux / macOS / Git Bash)
#
# Kullanım:
#   bash scripts/push.sh "Commit mesajı"      → kontrol + commit + push
#   bash scripts/push.sh --install            → Termux'ta 'juz' kısayolunu kurar
#   juz "Commit mesajı"                        → (kurulumdan sonra) her yerden
#
# Bu betik HİÇBİR token/şifre içermez. GitHub kimlik doğrulaması için bir kez:
#   Termux : pkg install gh && gh auth login        (veya git credential helper)
#   Linux  : gh auth login
# Push sonrası derleme, test, Supabase senkronu ve APK yayını GitHub Actions'ta
# (.github/workflows/android-ci.yml) otomatik çalışır.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
fail() { echo -e "${RED}${BOLD}✖ $*${NC}"; exit 1; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
DEFAULT_REMOTE="https://github.com/engiincr/Juzzio-Chat.git"
BRANCH="${JUZZIO_BRANCH:-main}"

# --- Kısayol kurulumu (Termux) ----------------------------------------------
if [[ "${1:-}" == "--install" ]]; then
  BIN_DIR="${PREFIX:-$HOME/.local}/bin"
  mkdir -p "$BIN_DIR"
  for name in juz Juz; do
    cat > "$BIN_DIR/$name" <<EOF
#!/usr/bin/env bash
exec bash "$PROJECT_DIR/scripts/push.sh" "\$@"
EOF
    chmod +x "$BIN_DIR/$name"
  done
  if command -v pkg >/dev/null 2>&1; then
    pkg install -y git gh >/dev/null 2>&1 || true
  fi
  ok "'juz' komutu kuruldu ($BIN_DIR). Artık 'juz \"mesaj\"' yazarak push yapabilirsiniz."
  command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1 && warn "GitHub girişi için bir kez çalıştırın: gh auth login"
  exit 0
fi

command -v git >/dev/null 2>&1 || fail "git bulunamadı. Termux: pkg install git"
git config --global --add safe.directory "$PROJECT_DIR" >/dev/null 2>&1 || true

# --- Depo ve uzak sunucu ----------------------------------------------------
if [ ! -d .git ]; then
  git init -b "$BRANCH" >/dev/null
  ok "Yeni git deposu oluşturuldu ($BRANCH)."
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "${JUZZIO_REMOTE:-$DEFAULT_REMOTE}"
  ok "origin → $(git remote get-url origin)"
fi
# Eski betikler origin adresine token gömüyordu; temizle
ORIGIN_URL="$(git remote get-url origin)"
if [[ "$ORIGIN_URL" =~ https://[^/]+@github\.com ]]; then
  CLEAN_URL="$(echo "$ORIGIN_URL" | sed -E 's#https://[^/]+@github\.com#https://github.com#')"
  git remote set-url origin "$CLEAN_URL"
  warn "origin adresindeki gömülü token kaldırıldı → $CLEAN_URL"
fi
if [ -z "$(git config user.name || true)" ]; then
  git config user.name "${GIT_AUTHOR_NAME:-engiincr}"
fi
if [ -z "$(git config user.email || true)" ]; then
  git config user.email "${GIT_AUTHOR_EMAIL:-engiincr@users.noreply.github.com}"
fi
# gh kimlik yardımcısını yalnızca bir kez kur (her push'ta ağ sorgusu yapmasın)
if [ -z "$(git config --get credential.https://github.com.helper || true)" ] && command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 && gh auth setup-git >/dev/null 2>&1 || true
fi

# --- Hassas dosyaları Git takibinden çıkar ----------------------------------
for f in .env .env.local .env.production android/key.properties android/app/google-services.json; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git rm --cached -q "$f"
    warn "$f Git takibinden çıkarıldı (dosya diskte duruyor)."
  fi
done

# v0.1.0'dan kalan eski/tehlikeli dosyalar (token içeren betik, eski iş akışı vb.)
for old in .github/workflows/supabase-sync.yml scripts/auto_setup_and_sync.sh fix_juzzio_build.py juzzio_sync.sh; do
  if [ -e "$old" ]; then rm -f "$old"; warn "Eski dosya silindi: $old"; fi
done
rm -rf android/app/src/main/kotlin/com/engiincr android/app/src/main/java/com/engiincr 2>/dev/null || true

python3 scripts/verify_tree.py || exit 1
echo -e "${CYAN}${BOLD}[1/4] Dosyalar hazırlanıyor...${NC}"
git add -A

echo -e "${CYAN}${BOLD}[2/4] Gizli anahtar taraması...${NC}"
PATTERN='(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sb_secret_[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Z2hwX[A-Za-z0-9+/=]{20,}|c2Jfc2VjcmV0[A-Za-z0-9+/=]{10,}|"private_key"[[:space:]]*:)'
if git grep --cached -nIE "$PATTERN" -- . ':!*.md' ':!.github/workflows/android-ci.yml' ':!scripts/push.sh' ':!scripts/push.bat'; then
  git reset -q
  fail "Gizli anahtar/token bulundu! Yukarıdaki satırları temizleyin, anahtarı iptal edip yenileyin."
fi
ok "Gizli anahtar bulunmadı."

echo -e "${CYAN}${BOLD}[3/4] Flutter analizi: GitHub Actions'ta (yerelde istenirse ANALYZE=1)${NC}"
if [ "${ANALYZE:-0}" = "1" ] && command -v flutter >/dev/null 2>&1; then
  flutter pub get >/dev/null && flutter analyze --no-fatal-infos --no-fatal-warnings || fail "flutter analyze hata verdi."
  ok "Analiz temiz."
fi

echo -e "${CYAN}${BOLD}[4/4] Commit ve push...${NC}"
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/check_secrets.py || fail "Hassas bilgi bulundu; gönderim durduruldu."
fi
MSG="${*:-Juzzio güncellemesi $(date '+%Y-%m-%d %H:%M')}"

# v0.8.0: VARSAYILAN olarak tüm geçmiş silinir → tek temiz commit (yalnızca sizin
# adınızla); eski etiketler, Release'ler ve main dışındaki dallar silinir.
# Geçmişi korumak için: JUZZIO_KEEP_HISTORY=1 bash scripts/push.sh "mesaj"
if [ "${JUZZIO_KEEP_HISTORY:-0}" != "1" ]; then
  git rebase --abort >/dev/null 2>&1 || true
  git merge --abort >/dev/null 2>&1 || true
  git branch -D juzzio_clean_tmp >/dev/null 2>&1 || true
  git checkout -q --orphan juzzio_clean_tmp || fail "Geçici dal oluşturulamadı."
  git add -A
  git commit -q -m "$MSG" || fail "Commit oluşturulamadı."
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  git branch -m "$BRANCH"
  git reflog expire --expire=now --all >/dev/null 2>&1 || true
  git gc -q --prune=now >/dev/null 2>&1 || true
  git push -f -u origin "$BRANCH" || fail "Push başarısız. 'gh auth login' yapın; main dal kuralı force push'u engelliyorsa kapatın."
  if command -v gh >/dev/null 2>&1; then
    for t in $(gh release list --limit 300 --json tagName -q '.[].tagName' 2>/dev/null || true); do
      gh release delete "$t" --cleanup-tag -y >/dev/null 2>&1 || true
    done
  fi
  for t in $(git ls-remote --tags origin 2>/dev/null | awk '{print $2}' | sed 's#\^{}##' | sort -u); do
    git push -q origin ":$t" >/dev/null 2>&1 || true
  done
  for b in $(git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##'); do
    [ "$b" = "$BRANCH" ] || git push -q origin --delete "$b" >/dev/null 2>&1 || true
  done
  git tag -l | xargs -r git tag -d >/dev/null 2>&1 || true
  ok "Geçmiş temizlendi: tek commit, eski etiket/Release/dallar silindi."
else
  if git diff --cached --quiet; then
    warn "Commit edilecek değişiklik yok; yalnızca push denenecek."
  else
    git commit -q -m "$MSG"
    ok "Commit: $MSG"
  fi
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if ! git push -q -u origin "$CURRENT_BRANCH" 2>/dev/null; then
    warn "Uzakta yeni commit var; birleştiriliyor..."
    if ! git pull -q --rebase -X theirs origin "$CURRENT_BRANCH"; then
      git rebase --abort >/dev/null 2>&1 || true
      fail "Uzak değişikliklerle çakışma çözülemedi. 'git status' ile kontrol edin."
    fi
    git push -q -u origin "$CURRENT_BRANCH" || fail "Push başarısız. GitHub girişi için: gh auth login"
  fi
fi

REPO_PATH="$(git remote get-url origin | sed -E 's#(https://github.com/|git@github.com:)##; s#\.git$##')"
ok "Push tamamlandı."
echo -e "${CYAN}Derleme durumu: https://github.com/${REPO_PATH}/actions${NC}"
echo -e "${CYAN}APK (derleme bitince): https://github.com/${REPO_PATH}/releases/latest${NC}"
