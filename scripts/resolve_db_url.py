#!/usr/bin/env python3
"""CI yardımcı betiği: SUPABASE_DB_URL secret'ından GitHub Actions'ın gerçekten
bağlanabildiği bir Postgres adresi bulur ve stdout'a yazar.

Neden gerekli?
  • Supabase'in "Direct connection" adresi (db.<ref>.supabase.co) yalnızca IPv6'dır;
    GitHub Actions sunucularında IPv6 yoktur → "Network is unreachable".
  • Bu durumda aynı şifreyle IPv4 destekli Session pooler adresi
    (aws-0/aws-1-<bölge>.pooler.supabase.com:5432, kullanıcı postgres.<ref>)
    bölge bölge denenir ve çalışan ilk adres kullanılır.
  • Şifrede @ # / : ? gibi karakterler varsa otomatik URL-encode edilir.

Şifre hiçbir zaman ekrana yazılmaz (yalnızca stdout'a, CI maskelenmiş değişkene).
"""
import os
import re
import subprocess
import sys
from urllib.parse import quote, unquote

REGIONS = [
    "eu-central-1", "eu-central-2", "eu-west-1", "eu-west-2", "eu-west-3", "eu-north-1",
    "us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1", "sa-east-1",
    "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2", "ap-south-1",
    "me-central-1", "af-south-1",
]


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def parse(url: str):
    url = url.strip()
    m = re.match(r"^(postgres(?:ql)?)://(.*)$", url)
    if not m:
        return None
    rest = m.group(2)
    at = rest.rfind("@")
    if at < 0:
        return None
    userinfo, hostpart = rest[:at], rest[at + 1:]
    if ":" in userinfo:
        user, pw = userinfo.split(":", 1)
    else:
        user, pw = userinfo, ""
    pw = unquote(pw)
    path = ""
    query = ""
    if "/" in hostpart:
        hostport, path = hostpart.split("/", 1)
    else:
        hostport = hostpart
    if "?" in path:
        path, query = path.split("?", 1)
    if ":" in hostport:
        host, port = hostport.rsplit(":", 1)
    else:
        host, port = hostport, "5432"
    return {
        "user": unquote(user),
        "pw": pw,
        "host": host,
        "port": port,
        "db": path or "postgres",
        "query": query,
    }


def build(user, pw, host, port, db, query=""):
    q = query
    if "sslmode=" not in q:
        q = (q + "&" if q else "") + "sslmode=require"
    return f"postgresql://{quote(user, safe='.')}:{quote(pw, safe='')}@{host}:{port}/{db}?{q}"


def works(url: str, timeout: int = 8) -> bool:
    env = dict(os.environ, PGCONNECT_TIMEOUT=str(timeout))
    try:
        r = subprocess.run(
            ["psql", url, "-X", "-tAc", "SELECT 1"],
            env=env, capture_output=True, text=True, timeout=timeout + 5,
        )
    except Exception:
        return False
    return r.returncode == 0 and r.stdout.strip() == "1"


def main() -> int:
    raw = os.environ.get("SUPABASE_DB_URL", "")
    p = parse(raw)
    if not p:
        log("::error::SUPABASE_DB_URL 'postgresql://kullanici:sifre@sunucu:port/postgres' biçiminde olmalı.")
        return 2

    ref = os.environ.get("SUPABASE_PROJECT_REF", "").strip()
    m = re.match(r"^db\.([a-z0-9]+)\.supabase\.co$", p["host"])
    if m:
        ref = m.group(1)
    if not ref and p["user"].startswith("postgres."):
        ref = p["user"].split(".", 1)[1]

    # 1) Verilen adres (pooler adresi verildiyse doğrudan çalışır)
    given = build(p["user"], p["pw"], p["host"], p["port"], p["db"], p["query"])
    if not m:
        log(f"Verilen adres deneniyor: {p['host']}:{p['port']}")
        if works(given, 15):
            print(given)
            return 0
        if "pooler.supabase.com" in p["host"]:
            log("::error::Pooler adresine bağlanılamadı. Şifre yanlış olabilir (Supabase → Settings → Database → Reset password).")
            return 1

    if not ref:
        log("::error::Proje kimliği bulunamadı; Session pooler adresini kullanın.")
        return 1

    # 2) IPv6-only direct adres → IPv4 Session pooler'ı bölge bölge dene
    log("Doğrudan adres (db.<ref>.supabase.co) GitHub Actions'tan erişilemez (yalnızca IPv6). "
        "Aynı şifreyle Session pooler adresi aranıyor...")
    for prefix in ("aws-0", "aws-1"):
        for region in REGIONS:
            host = f"{prefix}-{region}.pooler.supabase.com"
            url = build(f"postgres.{ref}", p["pw"], host, "5432", "postgres")
            if works(url, 6):
                log(f"✅ Bağlantı bulundu: {host}:5432 (SUPABASE_DB_URL secret'ını bu adresle güncellemeniz önerilir)")
                print(url)
                return 0
    log("::error::Hiçbir Session pooler adresine bağlanılamadı. Şifre yanlış olabilir. "
        "Supabase → Connect → Session pooler adresini kopyalayıp SUPABASE_DB_URL secret'ına yapıştırın.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
