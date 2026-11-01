@echo off
REM =============================================================================
REM JUZZIO - Guvenli GitHub Push (Windows CMD)
REM
REM Kullanim (proje klasorunde):
REM   scripts\push.bat "Commit mesaji"
REM
REM Bu betik HICBIR token/sifre icermez. GitHub girisi icin bir kez:
REM   winget install GitHub.cli   ve   gh auth login
REM   (veya Git for Windows ile gelen Git Credential Manager tarayicida giris ister)
REM Push sonrasi derleme, test, Supabase senkronu ve APK yayini GitHub Actions'ta
REM (.github\workflows\android-ci.yml) otomatik calisir.
REM =============================================================================
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

cd /d "%~dp0.."
set "DEFAULT_REMOTE=https://github.com/engiincr/Juzzio-Chat.git"
if "%JUZZIO_BRANCH%"=="" (set "BRANCH=main") else (set "BRANCH=%JUZZIO_BRANCH%")

where git >nul 2>&1
if errorlevel 1 (
  echo [HATA] git bulunamadi. https://git-scm.com/download/win adresinden kurun.
  exit /b 1
)

if not exist ".git" (
  git init -b %BRANCH% >nul
  echo [OK] Yeni git deposu olusturuldu.
)

git remote get-url origin >nul 2>&1
if errorlevel 1 (
  if "%JUZZIO_REMOTE%"=="" (git remote add origin %DEFAULT_REMOTE%) else (git remote add origin %JUZZIO_REMOTE%)
)

REM Eski betiklerin origin adresine gomdugu token'i temizle
for /f "usebackq delims=" %%U in (`git remote get-url origin`) do set "ORIGIN_URL=%%U"
echo !ORIGIN_URL! | findstr /R /C:"https://.*@github.com" >nul
if not errorlevel 1 (
  for /f "tokens=2 delims=@" %%A in ("!ORIGIN_URL!") do set "CLEAN_URL=https://%%A"
  git remote set-url origin !CLEAN_URL!
  echo [UYARI] origin adresindeki gomulu token kaldirildi: !CLEAN_URL!
)

for /f "usebackq delims=" %%N in (`git config user.name`) do set "GUSER=%%N"
if "!GUSER!"=="" git config user.name engiincr
for /f "usebackq delims=" %%E in (`git config user.email`) do set "GMAIL=%%E"
if "!GMAIL!"=="" git config user.email engiincr@users.noreply.github.com

REM gh kimlik yardimcisini yalnizca bir kez kur (her push'ta ag sorgusu yapmasin)
set "CRED="
for /f "usebackq delims=" %%C in (`git config --get credential.https://github.com.helper 2^>nul`) do set "CRED=%%C"
if "!CRED!"=="" (
  where gh >nul 2>&1
  if not errorlevel 1 (
    gh auth status >nul 2>&1 && gh auth setup-git >nul 2>&1
  )
)

REM Hassas dosyalari takipten cikar
for %%F in (.env .env.local .env.production android\key.properties android\app\google-services.json) do (
  git ls-files --error-unmatch "%%F" >nul 2>&1
  if not errorlevel 1 (
    git rm --cached -q "%%F"
    echo [UYARI] %%F Git takibinden cikarildi.
  )
)

REM v0.1.0'dan kalan eski/tehlikeli dosyalar (token iceren betik, eski is akisi vb.)
for %%O in (.github\workflows\supabase-sync.yml scripts\auto_setup_and_sync.sh fix_juzzio_build.py juzzio_sync.sh) do (
  if exist "%%O" (
    del /f /q "%%O"
    echo [UYARI] Eski dosya silindi: %%O
  )
)
if exist "android\app\src\main\kotlin\com\engiincr" rmdir /s /q "android\app\src\main\kotlin\com\engiincr"

echo [0/4] Kaynak butunlugu kontrol ediliyor...
set "PY="
where python >nul 2>nul && set "PY=python"
if "!PY!"=="" (where py >nul 2>nul && set "PY=py -3")
if "!PY!"=="" (
  echo [HATA] Python bulunamadi. https://www.python.org/downloads/ adresinden kurun ^(Add to PATH secili^).
  exit /b 1
)
!PY! scripts\verify_tree.py
if errorlevel 1 exit /b 1

echo [1/4] Dosyalar hazirlaniyor...
git add -A

echo [2/4] Gizli anahtar taramasi...
git grep --cached -nIE "(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sb_secret_[A-Za-z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Z2hwX[A-Za-z0-9+/=]{20,}|c2Jfc2VjcmV0[A-Za-z0-9+/=]{10,})" -- . ":!*.md" ":!.github/workflows/android-ci.yml" ":!scripts/push.sh" ":!scripts/push.bat"
if not errorlevel 1 (
  git reset -q
  echo [HATA] Gizli anahtar/token bulundu! Satirlari temizleyin ve anahtari yenileyin.
  exit /b 1
)
echo [OK] Gizli anahtar bulunmadi.

echo [3/4] Flutter analizi GitHub Actions'ta (yerelde istenirse: set ANALYZE=1)
if "%ANALYZE%"=="1" (
  where flutter >nul 2>&1
  if not errorlevel 1 (
    call flutter pub get >nul
    call flutter analyze --no-fatal-infos --no-fatal-warnings
    if errorlevel 1 (
      echo [HATA] flutter analyze hata verdi.
      exit /b 1
    )
  )
)

echo [4/4] Commit ve push...
!PY! scripts\check_secrets.py
if errorlevel 1 (
  echo [HATA] Hassas bilgi bulundu, gonderim durduruldu.
  exit /b 1
)
!PY! scripts\ci_guards.py
if errorlevel 1 (
  echo [HATA] CI koruma kapisi basarisiz, gonderim durduruldu.
  exit /b 1
)
set "MSG=%~1"
if "%MSG%"=="" set "MSG=Juzzio guncellemesi %DATE% %TIME:~0,5%"

REM Yarim kalmis rebase/merge veya eski kilit dosyasi push'u engellemesin
if exist ".git\rebase-merge" git rebase --abort >nul 2>&1
if exist ".git\rebase-apply" git rebase --abort >nul 2>&1
if exist ".git\MERGE_HEAD" git merge --abort >nul 2>&1
if exist ".git\index.lock" (
  tasklist /FI "IMAGENAME eq git.exe" 2>nul | find /I "git.exe" >nul
  if errorlevel 1 (
    del /f /q ".git\index.lock" >nul 2>&1
    echo [UYARI] Eski index.lock kaldirildi.
  )
)
git config http.postBuffer 524288000 >nul 2>&1

REM Ayrik HEAD ise hedef dala gec
set "CUR="
for /f "usebackq delims=" %%B in (`git symbolic-ref --quiet --short HEAD 2^>nul`) do set "CUR=%%B"
if "!CUR!"=="" (
  git checkout -q -B %BRANCH%
  set "CUR=%BRANCH%"
)

REM v0.9.0: VARSAYILAN olarak Git GECMISI KORUNUR (normal commit + normal push).
REM Eski surumler, etiketler, Release'ler ve diger dallar ASLA silinmez.
REM Istege bagli tek-commit kipi: set JUZZIO_SQUASH_HISTORY=1 (yalnizca bu dal,
REM --force-with-lease ile; baska hicbir sey silinmez).
if "%JUZZIO_SQUASH_HISTORY%"=="1" goto :squash

git diff --cached --quiet
if errorlevel 1 (
  git commit -q -m "%MSG%"
  if errorlevel 1 (
    echo [HATA] Commit olusturulamadi.
    exit /b 1
  )
  echo [OK] Commit: %MSG%
) else (
  echo [BILGI] Commit edilecek degisiklik yok; yalnizca push denenecek.
)

set /a TRY=0
:push_retry
set /a TRY+=1
git push -q -u origin !CUR! 2>"%TEMP%\juzzio_push_err.txt"
if not errorlevel 1 goto :done
findstr /I /C:"Authentication failed" /C:"could not read Username" /C:"403" /C:"denied" "%TEMP%\juzzio_push_err.txt" >nul
if not errorlevel 1 (
  type "%TEMP%\juzzio_push_err.txt"
  echo [HATA] GitHub kimlik dogrulamasi gerekli: gh auth login
  exit /b 1
)
if !TRY! GEQ 3 (
  type "%TEMP%\juzzio_push_err.txt"
  echo [HATA] Push 3 denemede basarisiz. Internet ve "gh auth status" ciktisini kontrol edin.
  exit /b 1
)
echo [BILGI] Uzakta yeni commit var; birlestiriliyor (deneme !TRY!/3)...
REM Rebase sirasinda "theirs" = yerel commit'ler: ayni satirda cakismada YEREL surum kazanir
git pull -q --rebase --autostash -X theirs origin !CUR!
if errorlevel 1 (
  git rebase --abort >nul 2>&1
  git pull -q --no-rebase --no-edit -X ours origin !CUR!
  if errorlevel 1 (
    git merge --abort >nul 2>&1
    echo [HATA] Uzak degisikliklerle cakisma cozulemedi. "git status" ile kontrol edin.
    exit /b 1
  )
)
goto :push_retry

:squash
echo [UYARI] JUZZIO_SQUASH_HISTORY=1: !CUR! dalinin gecmisi tek commit'e indiriliyor...
git branch -D juzzio_clean_tmp >nul 2>&1
git checkout -q --orphan juzzio_clean_tmp
if errorlevel 1 (
  echo [HATA] Gecici dal olusturulamadi.
  exit /b 1
)
git add -A
git commit -q -m "%MSG%"
if errorlevel 1 (
  echo [HATA] Commit olusturulamadi.
  exit /b 1
)
git branch -D !CUR! >nul 2>&1
git branch -m !CUR!
git fetch -q origin !CUR! >nul 2>&1
git push --force-with-lease -u origin !CUR!
if errorlevel 1 (
  echo [HATA] Push basarisiz. GitHub girisi: gh auth login
  exit /b 1
)

:done
echo.
echo [OK] Push tamamlandi.
echo Derleme durumu: https://github.com/engiincr/Juzzio-Chat/actions
echo APK (derleme bitince): https://github.com/engiincr/Juzzio-Chat/releases/latest
endlocal
exit /b 0
