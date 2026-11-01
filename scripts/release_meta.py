#!/usr/bin/env python3
"""Juzzio release metadata (version.json / README / release-notes) — CI tarafından çağrılır.

Komutlar:
  release_meta.py title                          → version.json'daki sürüm başlığını yazdırır
  release_meta.py update <sha256> <size> <date>  → version.json + README.md + release-notes.md günceller
  release_meta.py check                          → version.json'ı okur/onarır, sonucu yazdırır
  release_meta.py notes                          → yalnızca bu sürümün notlarını release-notes.md'ye yazar
  release_meta.py publish-sql                    → app_releases satırını (ayrıntılarla) ekleyen SQL'i yazdırır

v0.7.0: Sürüm notlarının TEK kaynağı version.json → "details" alanıdır
({"tr": {"reason", "features", "fixes", "security"}, "en": {...}}). GitHub sürüm
sayfası, uygulamadaki "Yenilikler" penceresi ve anlık güncelleme bildirimi buradan
otomatik üretilir; yöneticinin panelde elle not yazmasına gerek kalmaz.

Dayanıklılık kuralları (Windows/PowerShell kaynaklı bozulmalar dahil):
  • UTF-8 BOM, UTF-16 (BOM'lu/BOM'suz) ve araya karışmış NUL baytları temizlenir.
  • JSON'dan sonra gelen fazlalık ("Extra data") yok sayılır; ilk geçerli nesne alınır.
  • Hiç okunamazsa varsayılan yapıya dönülür (CI asla bu yüzden kırılmaz).
  • Sürüm ve build numarası her zaman pubspec.yaml'dan alınır (tek doğruluk kaynağı).
  • Yazma atomiktir (geçici dosya + os.replace), çıktı her zaman geçerli UTF-8 JSON'dur.
"""
import json
import os
import re
import sys
import tempfile

REPO = os.environ.get("GITHUB_REPOSITORY", "engiincr/Juzzio-Chat")
VERSION_FILE = "version.json"
PUBSPEC = "pubspec.yaml"
DEFAULT_TITLE = "Juzzio güncellemesi"


def _decode_text(raw: bytes) -> str:
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
        try:
            return raw.decode("utf-16")
        except UnicodeDecodeError:
            pass
    # BOM'suz UTF-16LE: baytların yarısı NUL ise
    if raw and raw.count(b"\x00") > len(raw) // 3:
        try:
            return raw.decode("utf-16-le")
        except UnicodeDecodeError:
            pass
    return raw.replace(b"\x00", b"").decode("utf-8", errors="replace")


def read_json_lenient(path: str) -> dict:
    try:
        with open(path, "rb") as f:
            txt = _decode_text(f.read())
    except FileNotFoundError:
        return {}
    txt = txt.replace("﻿", "").strip()
    if not txt:
        return {}
    start = txt.find("{")
    if start < 0:
        return {}
    try:
        obj, _end = json.JSONDecoder().raw_decode(txt[start:])
        return obj if isinstance(obj, dict) else {}
    except json.JSONDecodeError:
        # Son çare: son kapanan süslü paranteze kadar kes ve tekrar dene
        last = txt.rfind("}")
        if last > start:
            try:
                obj = json.loads(txt[start:last + 1])
                return obj if isinstance(obj, dict) else {}
            except json.JSONDecodeError:
                pass
    return {}


def read_pubspec_version(path: str = PUBSPEC):
    ver, build = "0.0.0", 1
    try:
        with open(path, "rb") as f:
            txt = _decode_text(f.read())
        m = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$", txt, re.M)
        if m:
            ver = m.group(1)
            build = int(m.group(2)) if m.group(2) else 1
    except FileNotFoundError:
        pass
    return ver, build


def write_text_atomic(path: str, text: str) -> None:
    d = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp = tempfile.mkstemp(prefix=".tmp_", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)


def normalized(data: dict) -> dict:
    ver, build = read_pubspec_version()
    # CI her derlemede artan bir sürüm kodu kullanır (JUZZIO_BUILD_NUMBER); uygulamaya
    # derlenen sayı ile version.json'daki sayı böylece birebir aynı olur.
    env_build = os.environ.get("JUZZIO_BUILD_NUMBER", "").strip()
    if env_build.isdigit() and int(env_build) > 0:
        build = int(env_build)
    out = dict(data) if isinstance(data, dict) else {}
    changelog = out.get("changelog") if isinstance(out.get("changelog"), dict) else {}
    out["version"] = ver
    # Aynı sayı birden çok isimle yazılır: eski ve yeni uygulama sürümleri hangisini okursa okusun.
    out["build"] = build
    out["buildNumber"] = build
    out["versionCode"] = build
    out.setdefault("releaseTitle", DEFAULT_TITLE)
    if not str(out.get("releaseTitle") or "").strip():
        out["releaseTitle"] = DEFAULT_TITLE
    out["url"] = f"https://github.com/{REPO}/releases/latest/download/Juzzio-latest.apk"
    out["apkUrl"] = out["url"]
    out["versionedApkUrl"] = f"https://github.com/{REPO}/releases/download/v{ver}/juzzio-v{ver}-release.apk"
    out["changelog"] = {k: str(v) for k, v in changelog.items() if isinstance(k, str)}
    out["changelog_tr"] = out["changelog"].get("tr", "")
    out["changelog_en"] = out["changelog"].get("en", "")
    out["changelog_de"] = out["changelog"].get("de", "")
    out.setdefault("mandatory", False)
    out.setdefault("minSupportedVersion", "0.1.0")
    return out


def dump(data: dict) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2) + "\n"


def cmd_title() -> None:
    data = read_json_lenient(VERSION_FILE)
    title = str(data.get("releaseTitle") or DEFAULT_TITLE).strip() or DEFAULT_TITLE
    print(title.replace("\n", " "))


def cmd_check() -> None:
    data = normalized(read_json_lenient(VERSION_FILE))
    write_text_atomic(VERSION_FILE, dump(data))
    json.loads(open(VERSION_FILE, encoding="utf-8").read())  # doğrulama
    print(f"version.json OK → v{data['version']} (+{data['build']})")


def cmd_update(sha256: str, size: str, build_date: str) -> None:
    data = normalized(read_json_lenient(VERSION_FILE))
    data["apkSha256"] = sha256
    data["apkSize"] = size
    data["verifiedBuild"] = bool(re.fullmatch(r"[0-9a-f]{64}", sha256 or ""))
    data["verifiedAt"] = build_date
    data["releaseDate"] = build_date.split(" ")[0] if build_date else data.get("releaseDate", "")
    write_text_atomic(VERSION_FILE, dump(data))
    json.loads(open(VERSION_FILE, encoding="utf-8").read())

    ver, build, title = data["version"], data["build"], data["releaseTitle"]
    if os.path.exists("README.md"):
        with open("README.md", "rb") as f:
            readme = _decode_text(f.read())
        block = (
            "<!-- JUZZIO_VERIFIED_APK_START -->\n"
            "| Sürüm | APK | Boyut | SHA-256 | Derleme |\n"
            "| :-- | :-- | :-- | :-- | :-- |\n"
            f"| v{ver} (+{build}) | [Juzzio-latest.apk](https://github.com/{REPO}/releases/latest/download/Juzzio-latest.apk) "
            f"| {size} | `{sha256}` | {build_date} |\n"
            "<!-- JUZZIO_VERIFIED_APK_END -->"
        )
        if "<!-- JUZZIO_VERIFIED_APK_START -->" in readme and "<!-- JUZZIO_VERIFIED_APK_END -->" in readme:
            readme = re.sub(
                r"<!-- JUZZIO_VERIFIED_APK_START -->.*?<!-- JUZZIO_VERIFIED_APK_END -->",
                lambda _m: block, readme, flags=re.S,
            )
        write_text_atomic("README.md", readme.replace("\r\n", "\n"))

    notes = (
        render_notes_body(data) +
        "## İndirme\n\n"
        f"- Son sürüm: [Juzzio-latest.apk](https://github.com/{REPO}/releases/latest/download/Juzzio-latest.apk)\n"
        f"- Bu sürüm: `juzzio-v{ver}-release.apk` ({size})\n\n"
        "## APK doğrulama\n\n"
        "```bash\nsha256sum Juzzio-latest.apk\n"
        f"# {sha256}  Juzzio-latest.apk\n```\n\n"
        f"Derleme zamanı: {build_date} — GitHub Actions\n"
    )
    write_text_atomic("release-notes.md", notes)
    print(f"Metadata güncellendi → v{ver} (+{build})")


SECTION_TITLES = {
    "tr": ("Neden bu güncelleme?", "✨ Yeni özellikler", "🛠️ Düzeltilen hatalar", "🔒 Güvenlik ve gizlilik"),
    "en": ("Why this update?", "✨ New features", "🛠️ Fixed bugs", "🔒 Security and privacy"),
}


def _lines(v) -> list:
    if isinstance(v, list):
        return [str(x).strip() for x in v if str(x).strip()]
    if isinstance(v, str):
        return [x.strip(" -•*\t") for x in v.splitlines() if x.strip(" -•*\t")]
    return []


def render_notes_body(data: dict) -> str:
    ver, title = data.get("version", ""), data.get("releaseTitle", DEFAULT_TITLE)
    details = data.get("details") if isinstance(data.get("details"), dict) else {}
    out = [f"# Juzzio v{ver} — {title}\n"]
    rendered = False
    for lang in ("tr", "en"):
        sec = details.get(lang)
        if not isinstance(sec, dict):
            continue
        t = SECTION_TITLES[lang]
        if lang == "en":
            out.append("\n---\n\n<details><summary>English</summary>\n")
        reason = str(sec.get("reason", "")).strip()
        if reason:
            out.append(f"\n## {t[0]}\n\n{reason}\n")
        for key, head in (("features", t[1]), ("fixes", t[2]), ("security", t[3])):
            items = _lines(sec.get(key))
            if items:
                out.append(f"\n## {head}\n\n" + "\n".join(f"- {i}" for i in items) + "\n")
        if lang == "en":
            out.append("\n</details>\n")
        rendered = True
    if not rendered:
        out.append("\n" + str((data.get("changelog") or {}).get("tr", "")) + "\n")
    return "".join(out) + "\n"


def cmd_notes() -> None:
    data = normalized(read_json_lenient(VERSION_FILE))
    write_text_atomic("release-notes.md", render_notes_body(data))
    print("release-notes.md yazıldı")


def _sql_str(v: str) -> str:
    return "'" + str(v).replace("'", "''") + "'"


def cmd_publish_sql() -> None:
    """CI: GitHub sürümü yayınlanınca app_releases'e satır ekler → realtime ile tüm
    kullanıcılara anında güncelleme bildirimi gider (OTA denetimi beklenmez)."""
    data = normalized(read_json_lenient(VERSION_FILE))
    details = data.get("details") if isinstance(data.get("details"), dict) else {}
    tr = details.get("tr") if isinstance(details.get("tr"), dict) else {}
    reason = str(tr.get("reason", "")).strip() or str((data.get("changelog") or {}).get("tr", ""))[:600]
    if not str(tr.get("reason", "")).strip():
        details = dict(details)
        details["tr"] = dict(tr, reason=reason)
    apk = f"https://github.com/{REPO}/releases/download/v{data['version']}/juzzio-v{data['version']}-release.apk"
    ch = data.get("changelog") or {}
    print(
        "INSERT INTO public.app_releases (version_name, version_code, apk_url, notes_tr, notes_en, notes_de, is_mandatory, details, published_at) VALUES ("
        f"{_sql_str(data['version'])}, {int(data['build'])}, {_sql_str(apk)}, {_sql_str(reason)}, "
        f"{_sql_str(ch.get('en', ''))}, {_sql_str(ch.get('de', ''))}, {'true' if data.get('mandatory') else 'false'}, "
        f"{_sql_str(json.dumps(details, ensure_ascii=False))}::jsonb, NOW()) "
        "ON CONFLICT (version_name) DO UPDATE SET version_code = EXCLUDED.version_code, apk_url = EXCLUDED.apk_url, "
        "notes_tr = EXCLUDED.notes_tr, notes_en = EXCLUDED.notes_en, notes_de = EXCLUDED.notes_de, "
        "is_mandatory = EXCLUDED.is_mandatory, details = EXCLUDED.details, published_at = NOW();"
    )


def main(argv) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "title":
        cmd_title()
    elif cmd == "check":
        cmd_check()
    elif cmd == "notes":
        cmd_notes()
    elif cmd == "publish-sql":
        cmd_publish_sql()
    elif cmd == "update" and len(argv) >= 5:
        cmd_update(argv[2], argv[3], argv[4])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
