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
where python >nul 2>nul && (
  python scripts\check_secrets.py
  if errorlevel 1 (
    echo [HATA] Hassas bilgi bulundu, gonderim durduruldu.
    exit /b 1
  )
)
set "MSG=%~1"
if "%MSG%"=="" set "MSG=Juzzio guncellemesi %DATE% %TIME:~0,5%"

REM v0.8.0: VARSAYILAN olarak tum gecmis silinir -> tek temiz commit (yalnizca sizin
REM adinizla), eski etiketler, Release'ler ve main disindaki dallar silinir.
REM Gecmisi korumak icin: set JUZZIO_KEEP_HISTORY=1
if "%JUZZIO_KEEP_HISTORY%"=="1" goto :keep_history

echo [4/6] Gecmis temizleniyor (tek commit)...
git rebase --abort >nul 2>&1
git merge --abort >nul 2>&1
git branch -D juzzio_clean_tmp >nul 2>&1
git checkout -q --orphan juzzio_clean_tmp
if errorlevel 1 (
  echo [HATA] Gecici dal olusturulamadi. "git status" ciktisini kontrol edin.
  exit /b 1
)
git add -A
git commit -q -m "%MSG%"
if errorlevel 1 (
  echo [HATA] Commit olusturulamadi.
  exit /b 1
)
git branch -D %BRANCH% >nul 2>&1
git branch -m %BRANCH%
git reflog expire --expire=now --all >nul 2>&1
git gc -q --prune=now >nul 2>&1

echo [5/6] Zorla gonderiliyor (force push)...
git push -f -u origin %BRANCH%
if errorlevel 1 (
  echo [HATA] Push basarisiz. GitHub girisi: gh auth login
  echo        Ayarlar ^> Branches ^> main kurali "force push" engelliyorsa kapatin.
  exit /b 1
)

echo [6/6] Eski etiketler, Release'ler ve dallar siliniyor...
where gh >nul 2>&1
if not errorlevel 1 (
  for /f "usebackq delims=" %%T in (`gh release list --limit 300 --json tagName -q ".[].tagName" 2^>nul`) do (
    gh release delete "%%T" --cleanup-tag -y >nul 2>&1
  )
)
for /f "usebackq tokens=2" %%R in (`git ls-remote --tags origin 2^>nul`) do (
  set "REF=%%R"
  set "REF=!REF:^{}=!"
  git push -q origin ":!REF!" >nul 2>&1
)
for /f "usebackq tokens=2" %%R in (`git ls-remote --heads origin 2^>nul`) do (
  set "REF=%%R"
  set "BR=!REF:refs/heads/=!"
  if /I not "!BR!"=="%BRANCH%" git push -q origin --delete "!BR!" >nul 2>&1
)
for /f "usebackq delims=" %%T in (`git tag -l`) do git tag -d "%%T" >nul 2>&1
goto :done

:keep_history
git diff --cached --quiet
if errorlevel 1 (
  git commit -q -m "%MSG%"
  echo [OK] Commit: %MSG%
) else (
  echo [BILGI] Commit edilecek degisiklik yok.
)
git push -q -u origin %BRANCH% 2>nul
if errorlevel 1 (
  git pull -q --rebase -X theirs origin %BRANCH%
  git push -q -u origin %BRANCH%
  if errorlevel 1 (
    echo [HATA] Push basarisiz. GitHub girisi icin: gh auth login
    exit /b 1
  )
)

:done
echo.
echo [OK] Push tamamlandi.
echo Derleme durumu: https://github.com/engiincr/Juzzio-Chat/actions
echo APK (derleme bitince): https://github.com/engiincr/Juzzio-Chat/releases/latest
endlocal
