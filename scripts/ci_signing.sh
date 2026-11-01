#!/usr/bin/env bash
# =============================================================================
# CI: APK imza ayarı (android/key.properties) — GitHub Actions tarafından çağrılır.
#
# Okunan secret'lar: ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
#                    ANDROID_KEY_PASSWORD, ANDROID_KEY_ALIAS
# • Windows'ta "certutil -encode" ile üretilen base64 (BEGIN/END satırlı) da kabul edilir.
# • Şifrelerin başındaki/sonundaki boşluk, satır sonu ve tırnaklar temizlenir.
# • Secret'taki ve depodaki keystore, bilinen şifrelerle denenir; çalışan birleşim seçilir.
# • Şifreler hiçbir zaman yazdırılmaz; yalnızca uzunlukları ve sonuçlar gösterilir.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/../android/app"

LEGACY_PW='juzzio2026secure'

clean() {
  local v="$1"
  v="$(printf '%s' "$v" | tr -d '\r\n')"
  v="${v#"${v%%[![:space:]]*}"}"   # baştaki boşluk
  v="${v%"${v##*[![:space:]]}"}"   # sondaki boşluk
  if [[ ${#v} -ge 2 && ( ( "${v:0:1}" == '"' && "${v: -1}" == '"' ) || ( "${v:0:1}" == "'" && "${v: -1}" == "'" ) ) ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf '%s' "$v"
}

KS_PW="$(clean "${ANDROID_KEYSTORE_PASSWORD:-}")"
K_PW="$(clean "${ANDROID_KEY_PASSWORD:-}")"
K_ALIAS="$(clean "${ANDROID_KEY_ALIAS:-}")"

ks_type() {
  local magic
  magic="$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    feedfeed) echo "JKS" ;;
    cececece) echo "JCEKS" ;;
    30*) echo "PKCS12" ;;
    *) echo "BİLİNMİYOR($magic)" ;;
  esac
}

CANDS=()
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  # certutil başlık/son satırlarını ve tüm boşlukları at
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | tr -d '\r' | grep -v '^-----' | tr -d '[:space:]"' > secret-key.b64
  if base64 --decode secret-key.b64 > secret-key.jks 2>/dev/null && [ -s secret-key.jks ]; then
    t="$(ks_type secret-key.jks)"
    echo "ANDROID_KEYSTORE_BASE64 → $(stat -c%s secret-key.jks) bayt, tür: $t"
    if [[ "$t" == BİLİNMİYOR* ]]; then
      echo "::warning::ANDROID_KEYSTORE_BASE64 bir keystore değil (dosyanın kendisinin base64'ü olmalı, base64'ün base64'ü değil)."
    fi
    CANDS+=(secret-key.jks)
  else
    echo "::warning::ANDROID_KEYSTORE_BASE64 geçerli base64 değil. PowerShell: [Convert]::ToBase64String([IO.File]::ReadAllBytes('android\app\juzzio-release-key.jks')) | Set-Clipboard"
  fi
  rm -f secret-key.b64
fi
if [ -f juzzio-release-key.jks ]; then
  echo "Depodaki keystore → $(stat -c%s juzzio-release-key.jks) bayt, tür: $(ks_type juzzio-release-key.jks)"
  CANDS+=(juzzio-release-key.jks)
fi
if [ ${#CANDS[@]} -eq 0 ]; then
  echo "::error::İmza anahtarı yok. ANDROID_KEYSTORE_BASE64 secret'ını ekleyin."
  exit 1
fi

PWS=()
[ -n "$KS_PW" ] && PWS+=("$KS_PW")
[ -n "$K_PW" ] && [ "$K_PW" != "$KS_PW" ] && PWS+=("$K_PW")
PWS+=("$LEGACY_PW")
echo "Şifre secret'ları: ANDROID_KEYSTORE_PASSWORD ${#KS_PW} karakter, ANDROID_KEY_PASSWORD ${#K_PW} karakter, alias '${K_ALIAS:-<yok>}'"

FOUND=""
for ks in "${CANDS[@]}"; do
  label=$([ "$ks" = secret-key.jks ] && echo "Secret'taki keystore" || echo "Depodaki keystore")
  store_ok=""
  for i in "${!PWS[@]}"; do
    sp="${PWS[$i]}"
    keytool -list -keystore "$ks" -storepass "$sp" >/dev/null 2>&1 || continue
    store_ok=1
    which_pw=$([ "$sp" = "$LEGACY_PW" ] && echo "eski şifre" || ([ "$sp" = "$KS_PW" ] && echo "ANDROID_KEYSTORE_PASSWORD" || echo "ANDROID_KEY_PASSWORD"))
    echo "$label $which_pw ile açıldı."
    aliases="$(keytool -list -v -keystore "$ks" -storepass "$sp" 2>/dev/null | awk -F': ' '/^Alias name:/{print $2}')"
    echo "  Keystore'daki alias'lar: $(echo "$aliases" | tr '\n' ' ')"
    alias="$K_ALIAS"
    if [ -z "$alias" ] || ! grep -qxF "$alias" <<<"$aliases"; then
      [ -n "$alias" ] && echo "::warning::ANDROID_KEY_ALIAS '$alias' keystore'da yok; '$(head -n1 <<<"$aliases")' kullanılıyor."
      alias="$(head -n1 <<<"$aliases")"
    fi
    for kp in "${PWS[@]}"; do
      if keytool -certreq -alias "$alias" -keystore "$ks" -storepass "$sp" -keypass "$kp" -file /dev/null >/dev/null 2>&1; then
        FOUND="$ks"; STORE_PW="$sp"; KEY_PW="$kp"; KEY_AL="$alias"
        break 3
      fi
    done
    echo "::warning::$label açıldı ama '$alias' anahtarının şifresi (ANDROID_KEY_PASSWORD) uymadı."
  done
  [ -z "$store_ok" ] && echo "::warning::$label hiçbir şifreyle açılamadı (ANDROID_KEYSTORE_PASSWORD bu keystore'a ait değil)."
done

if [ -z "$FOUND" ]; then
  echo "::error::APK imzalanamadı. Yukarıdaki uyarılara bakın: keystore/şifre/alias eşleşmiyor."
  rm -f secret-key.jks
  exit 1
fi

if [ "$FOUND" != juzzio-release-key.jks ]; then mv -f "$FOUND" juzzio-release-key.jks; fi
rm -f secret-key.jks
[ "$STORE_PW" = "$LEGACY_PW" ] && echo "::warning::APK eski (sızmış) keystore şifresiyle imzalandı."
echo "İmza hazır: alias=$KEY_AL ✅"
{
  echo "storePassword=$STORE_PW"
  echo "keyPassword=$KEY_PW"
  echo "keyAlias=$KEY_AL"
  echo "storeFile=juzzio-release-key.jks"
} > ../key.properties
