#!/usr/bin/env bash
# =============================================================================
# JUZZIO — Güvenli GitHub Push (Termux / Linux / macOS / Git Bash)
#
# Kullanım:
#   bash scripts/push.sh "Commit mesajı"      → kontrol + commit + push (geçmiş korunur)
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
  python3 scripts/ci_guards.py || fail "CI koruma kapısı başarısız; gönderim durduruldu."
fi
MSG="${*:-Juzzio güncellemesi $(date '+%Y-%m-%d %H:%M')}"

# Yarım kalmış işlem / kilit dosyası varsa güvenle temizle (push'u engellemesin)
[ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] && { git rebase --abort >/dev/null 2>&1 || true; warn "Yarım kalmış rebase iptal edildi."; }
[ -f .git/MERGE_HEAD ] && { git merge --abort >/dev/null 2>&1 || true; warn "Yarım kalmış merge iptal edildi."; }
if [ -f .git/index.lock ] && ! pgrep -x git >/dev/null 2>&1; then rm -f .git/index.lock; warn "Eski index.lock kaldırıldı."; fi
# Büyük dosyalarda HTTPS push zaman aşımını önle
git config http.postBuffer 524288000 >/dev/null 2>&1 || true

# Ayrık HEAD (detached) ise hedef dala geç
CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [ -z "$CURRENT_BRANCH" ]; then
  git checkout -q -B "$BRANCH" || fail "Dal ($BRANCH) seçilemedi."
  CURRENT_BRANCH="$BRANCH"
fi

# v0.9.0: Varsayılan olarak Git GEÇMİŞİ KORUNUR (normal commit + normal push).
# Eski sürümler, etiketler, GitHub Release'leri ve diğer dallar ASLA silinmez.
# İsteğe bağlı tek-commit kipi: JUZZIO_SQUASH_HISTORY=1 → yalnızca bu dalın geçmişi
# tek commit'e indirilir ve --force-with-lease ile gönderilir (başka hiçbir şey silinmez).
if [ "${JUZZIO_SQUASH_HISTORY:-0}" = "1" ]; then
  warn "JUZZIO_SQUASH_HISTORY=1: '$CURRENT_BRANCH' dalının geçmişi tek commit'e indirilecek."
  git branch -D juzzio_clean_tmp >/dev/null 2>&1 || true
  git checkout -q --orphan juzzio_clean_tmp || fail "Geçici dal oluşturulamadı."
  git add -A
  git commit -q -m "$MSG" || fail "Commit oluşturulamadı."
  git branch -D "$CURRENT_BRANCH" >/dev/null 2>&1 || true
  git branch -m "$CURRENT_BRANCH"
  git fetch -q origin "$CURRENT_BRANCH" >/dev/null 2>&1 || true
  git push --force-with-lease -u origin "$CURRENT_BRANCH" || fail "Push başarısız. 'gh auth login' yapın; dal kuralı force push'u engelliyorsa JUZZIO_SQUASH_HISTORY kullanmayın."
else
  if git diff --cached --quiet; then
    warn "Commit edilecek değişiklik yok; yalnızca push denenecek."
  else
    git commit -q -m "$MSG" || fail "Commit oluşturulamadı."
    ok "Commit: $MSG"
  fi
  pushed=0
  for attempt in 1 2 3; do
    if git push -q -u origin "$CURRENT_BRANCH" 2>/tmp/juzzio_push_err.txt; then pushed=1; break; fi
    if grep -qiE "could not read Username|Authentication failed|403|denied" /tmp/juzzio_push_err.txt; then
      cat /tmp/juzzio_push_err.txt
      fail "GitHub kimlik doğrulaması gerekli: 'gh auth login' çalıştırın ve tekrar deneyin."
    fi
    # Uzakta yeni commit var (ör. CI'nin version.json güncellemesi): yerel değişiklikler
    # korunarak üstüne alınır; aynı dosyada çakışmada YEREL sürüm kazanır.
    warn "Uzakta yeni commit var; birleştiriliyor (deneme $attempt/3)..."
    if ! git pull -q --rebase --autostash -X theirs origin "$CURRENT_BRANCH"; then
      git rebase --abort >/dev/null 2>&1 || true
      git pull -q --no-rebase --no-edit -X ours origin "$CURRENT_BRANCH" || {
        git merge --abort >/dev/null 2>&1 || true
        fail "Uzak değişikliklerle çakışma çözülemedi. 'git status' ile kontrol edin."
      }
    fi
    sleep 2
  done
  [ "$pushed" = "1" ] || { cat /tmp/juzzio_push_err.txt 2>/dev/null; fail "Push 3 denemede başarısız. İnternet bağlantısını ve 'gh auth status' çıktısını kontrol edin."; }
fi

REPO_PATH="$(git remote get-url origin | sed -E 's#(https://github.com/|git@github.com:)##; s#\.git$##')"
ok "Push tamamlandı."
echo -e "${CYAN}Derleme durumu: https://github.com/${REPO_PATH}/actions${NC}"
echo -e "${CYAN}APK (derleme bitince): https://github.com/${REPO_PATH}/releases/latest${NC}"
