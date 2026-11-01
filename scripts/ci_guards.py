#!/usr/bin/env python3
"""Juzzio v0.9.0 — CI/yayın koruma kapısı (denetim bulgusu F ve G).

Bu betik yeniden yıkıcı otomasyon eklenmesini engeller ve CI'da her push'ta çalışır:
  1. İş akışı ve push betikleri eski Release'leri, etiketleri veya dalları
     toplu SİLEMEZ (gh release delete, git push --delete, ":refs/tags/...").
  2. Push betikleri varsayılan olarak geçmişi yeniden yazamaz / zorla gönderemez;
     tek-commit (squash) yalnızca açık JUZZIO_SQUASH_HISTORY=1 ile mümkündür.
  3. supabase-sync işi tüm kalite kapılarına (quality, sql-tests, edge-check,
     build-android, secret-scan) bağlı olmalıdır.
  4. Üst düzey iş akışı izni contents:write olamaz (en az yetki).
  5. Üçüncü taraf eylemler tam commit SHA'sına sabitlenmelidir.

Kullanım: python3 scripts/ci_guards.py   (hata varsa çıkış kodu 1)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "android-ci.yml")
PUSH_SCRIPTS = [os.path.join(ROOT, "scripts", "push.sh"), os.path.join(ROOT, "scripts", "push.bat")]

DESTRUCTIVE = [
    (r"gh\s+release\s+delete", "GitHub Release silme"),
    (r"git\s+push\b[^\n]*--delete", "uzak dal/etiket silme (git push --delete)"),
    (r"git\s+push\b[^\n]*[\"' ]:refs/", "uzak ref silme (git push :refs/...)"),
    (r"git\s+push\b[^\n]*[\"' ]:!?\w*REF", "uzak ref silme (git push :REF)"),
    (r"--cleanup-tag", "etiket temizleme"),
    (r"git\s+tag\s+-d", "yerel etiket toplu silme"),
]
REQUIRED_DEPLOY_NEEDS = {"secret-scan", "quality", "sql-tests", "edge-check", "build-android"}


def read(path: str) -> str:
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def strip_comments(text: str, bat: bool) -> str:
    out = []
    for line in text.splitlines():
        s = line.strip()
        if bat and (s.upper().startswith("REM") or s.startswith("::")):
            continue
        if not bat and s.startswith("#"):
            continue
        out.append(line)
    return "\n".join(out)


def check_destructive(path: str, errors: list) -> None:
    text = strip_comments(read(path), path.endswith(".bat"))
    for rx, label in DESTRUCTIVE:
        for m in re.finditer(rx, text):
            line = text.count("\n", 0, m.start()) + 1
            errors.append(f"{os.path.relpath(path, ROOT)}:{line}: yasak yıkıcı işlem — {label}")


def check_push_force(path: str, errors: list) -> None:
    text = strip_comments(read(path), path.endswith(".bat"))
    for m in re.finditer(r"git\s+push\s+(-f|--force)\b", text):
        # Zorla gönderme yalnızca açık squash kipinin içinde olabilir
        window = text[max(0, m.start() - 2500):m.start()]
        if "JUZZIO_SQUASH_HISTORY" not in window:
            line = text.count("\n", 0, m.start()) + 1
            errors.append(f"{os.path.relpath(path, ROOT)}:{line}: force push yalnızca JUZZIO_SQUASH_HISTORY=1 ile olabilir")


def job_block(text: str, job: str) -> str:
    m = re.search(rf"^  {re.escape(job)}:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", text, re.M | re.S)
    return m.group(1) if m else ""


def check_workflow(errors: list) -> None:
    text = read(WORKFLOW)
    top = text.split("\njobs:", 1)[0]
    if re.search(r"^permissions:\s*\n\s+contents:\s*write", top, re.M):
        errors.append("android-ci.yml: üst düzey 'contents: write' yasak (yalnızca release işi)")
    deploy = job_block(text, "supabase-sync")
    if not deploy:
        errors.append("android-ci.yml: supabase-sync işi bulunamadı")
    else:
        m = re.search(r"needs:\s*\[([^\]]*)\]", deploy)
        needs = {n.strip() for n in m.group(1).split(",")} if m else set()
        missing = REQUIRED_DEPLOY_NEEDS - needs
        if missing:
            errors.append(f"android-ci.yml: supabase-sync şu kapılara bağlı değil: {', '.join(sorted(missing))}")
    for m in re.finditer(r"uses:\s*([^\s#]+)", text):
        ref = m.group(1)
        if ref.startswith("./") or ref.startswith("docker://"):
            continue
        if not re.search(r"@[0-9a-f]{40}$", ref):
            line = text.count("\n", 0, m.start()) + 1
            errors.append(f"android-ci.yml:{line}: '{ref}' tam commit SHA'sına sabitlenmemiş")


def main() -> int:
    errors: list = []
    wf_dir = os.path.dirname(WORKFLOW)
    for name in sorted(os.listdir(wf_dir)):
        if name.endswith((".yml", ".yaml")):
            check_destructive(os.path.join(wf_dir, name), errors)
    for p in PUSH_SCRIPTS:
        if os.path.exists(p):
            check_destructive(p, errors)
            check_push_force(p, errors)
    check_workflow(errors)
    if errors:
        for e in errors:
            print(f"::error::{e}")
        print(f"✖ CI koruma kapısı: {len(errors)} sorun")
        return 1
    print("✔ CI koruma kapısı temiz (yıkıcı silme yok, dağıtım kapılara bağlı, eylemler sabit)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
