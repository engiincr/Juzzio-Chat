#!/usr/bin/env python3
"""Juzzio yerelleştirme aracı (CI kapısı).

  python3 scripts/l10n_tools.py generate   → lib/l10n/juzzio_inline_catalog.dart üretir
  python3 scripts/l10n_tools.py check      → eksik/eskimiş çeviri varsa çıkış kodu 1

Kontroller:
  1. trEn/loc/_l3/_tx/_l/_al çağrıları ve JuzzioGlassCharacter(en:) açıklamalarındaki tüm İngilizce metinler katalogda mı?
     (Katalog, TR/EN/DE dışındaki 140+ dil için dil paketlerinin kaynağıdır.)
  2. trEn(...) çağrılarında İngilizce argüman boş değil mi?
  3. kJuzzioV030Strings anahtarlarında tr ve en var mı?
  4. Desteklenen dil sayısı >= 139 ve RTL dilleri tanımlı mı?
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, 'lib', 'l10n', 'juzzio_inline_catalog.dart')
CALL_RE = re.compile(r'\b(trEn|loc|_l3|_tx|_l|_al|_t|_tr)\s*\(')

def scan_string(src, i):
    """src[i] is a quote (or r prefix). Return end index (exclusive) of literal."""
    raw = False
    if src[i] == 'r':
        raw = True; i += 1
    q = src[i]
    triple = src.startswith(q*3, i)
    i += 3 if triple else 1
    n = len(src)
    while i < n:
        if not raw and src[i] == '\\':
            i += 2; continue
        if not raw and src.startswith('${', i):
            d = 1; i += 2
            while i < n and d:
                c = src[i]
                if c in '\'"':
                    i = scan_string(src, i); continue
                if c == '{': d += 1
                elif c == '}': d -= 1
                i += 1
            continue
        if triple and src.startswith(q*3, i):
            return i + 3
        if not triple and src[i] == q:
            return i + 1
        i += 1
    return n

def parse_args(src, open_paren):
    """Return list of args: (start, end) spans at top level, and close paren index."""
    i = open_paren + 1; n = len(src); depth = 0
    args = []; start = i
    while i < n:
        c = src[i]
        if c in '\'"' or (c == 'r' and i+1 < n and src[i+1] in '\'"' and not (src[i-1].isalnum() or src[i-1]=='_')):
            i = scan_string(src, i); continue
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i); i = n if j < 0 else j + 2; continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                if src[start:i].strip():
                    args.append((start, i))
                return args, i
            depth -= 1
        elif c == ',' and depth == 0:
            args.append((start, i)); start = i + 1
        i += 1
    return args, n

def literal_value(src, s, e):
    """If arg span is one or more adjacent string literals, return (dart_literal_text, value_text_without_quotes)."""
    txt = src[s:e].strip()
    if not txt: return None
    i = 0; parts = []
    while i < len(txt):
        while i < len(txt) and txt[i].isspace(): i += 1
        if i >= len(txt): break
        if txt[i] in '\'"' or (txt[i] == 'r' and i+1 < len(txt) and txt[i+1] in '\'"'):
            j = scan_string(txt, i)
            parts.append(txt[i:j]); i = j
        else:
            return None
    if not parts: return None
    vals = []
    for p in parts:
        raw = p.startswith('r')
        body = p[1:] if raw else p
        q = body[0]
        if body.startswith(q*3): vals.append(body[3:-3])
        else: vals.append(body[1:-1])
    return txt, ''.join(vals)

def is_skippable_context(src, pos):
    # skip method definitions: "String trEn(String trText"
    before = src[max(0,pos-30):pos]
    return bool(re.search(r'(String|void|Future<[^>]*>)\s+$', before))


def collect():
    seen = {}; order = []; problems = []
    for f in sorted(glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True)):
        if os.sep + 'l10n' + os.sep in f:
            continue
        src = open(f, encoding='utf-8').read()
        for m in CALL_RE.finditer(src):
            if is_skippable_context(src, m.start()):
                continue
            ls = src.rfind('\n', 0, m.start()) + 1
            if src[ls:m.start()].lstrip().startswith('//'):
                continue
            if re.match(r'\s*\(\s*String\b', src[m.end() - 1:m.end() + 12]):
                continue
            args, _ = parse_args(src, m.end() - 1)
            if m.group(1) == 'trEn' and len(args) >= 2:
                lit = literal_value(src, *args[1])
                if lit and not lit[1].strip():
                    problems.append('%s:%d trEn İngilizce metin boş' % (os.path.relpath(f, ROOT), src.count('\n', 0, m.start()) + 1))
            if len(args) < 2:
                continue
            lit = literal_value(src, *args[1])
            if not lit:
                continue
            txt, val = lit
            if re.search(r'(?<!\\)\$', val) or txt.startswith('r'):
                continue
            if val in seen:
                continue
            seen[val] = txt
            order.append(txt)
        # v0.8.4: tema karakter açıklamaları (JuzzioGlassCharacter(en: '...')) da dil paketine girer
        for m in re.finditer(r'\bJuzzioGlassCharacter\s*\(', src):
            args, _ = parse_args(src, m.end() - 1)
            for s_, e_ in args:
                a = src[s_:e_].strip()
                if not a.startswith('en:'):
                    continue
                off = s_ + src[s_:e_].index('en:') + 3
                lit = literal_value(src, off, e_)
                if lit and lit[1] not in seen and '$' not in lit[1]:
                    seen[lit[1]] = lit[0]
                    order.append(lit[0])
    return order, problems


def render(order):
    out = ['// GENERATED by tools — do not edit by hand.',
           '// Uygulama içindeki satır içi (trEn/loc) İngilizce metinler: yerleşik olmayan diller',
           '// seçildiğinde dil paketiyle önceden çevrilir, böylece ekranlarda karışık dil görünmez.',
           '', 'const List<String> kJuzzioInlineEnglishCatalog = [']
    for t in order:
        out.append('  ' + re.sub(r'\s*\n\s*', ' ', t) + ',')
    out.append('];')
    return '\n'.join(out) + '\n'


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'check'
    order, problems = collect()
    if cmd == 'generate':
        open(CATALOG, 'w', encoding='utf-8').write(render(order))
        print('katalog: %d metin' % len(order))
        return 0
    errors = list(problems)
    current = open(CATALOG, encoding='utf-8').read() if os.path.exists(CATALOG) else ''
    if current != render(order):
        cur_set = set(re.findall(r"^  (.*),$", current, re.M))
        missing = [t for t in order if re.sub(r'\s*\n\s*', ' ', t) not in cur_set]
        errors.append('Çeviri kataloğu eski: %d yeni metin kataloğa eklenmemiş. Çalıştırın: python3 scripts/l10n_tools.py generate' % len(missing))
        for t in missing[:20]:
            errors.append('   + ' + t[:90])
    core = open(os.path.join(ROOT, 'lib', 'core', 'app_theme_and_locale.dart'), encoding='utf-8').read()
    n_lang = core[core.index('kJuzzioSupportedLanguages = ['):].split('];')[0].count('JuzzioLanguageOption(')
    if n_lang < 139:
        errors.append('Desteklenen dil sayısı %d (< 139)' % n_lang)
    main_src = open(os.path.join(ROOT, 'lib', 'main.dart'), encoding='utf-8').read()
    for rtl in ('ar', 'he', 'fa', 'ur'):
        if "'%s'" % rtl not in main_src[main_src.find('_kRtlLangs'):main_src.find('_kRtlLangs') + 400]:
            errors.append('RTL dili tanımlı değil: ' + rtl)
    v030 = open(os.path.join(ROOT, 'lib', 'l10n', 'juzzio_strings_v030.dart'), encoding='utf-8').read()
    # her anahtar tek satırda: 'key': {'tr': ..., 'en': ..., 'de': ...},
    for key, body in re.findall(r"^\s*'([\w.]+)':\s*\{(.*)\},?\s*$", v030, re.M):
        if "'tr':" not in body or "'en':" not in body:
            errors.append('v030 anahtarında tr/en eksik: ' + key)
    if errors:
        print('YERELLEŞTİRME KONTROLÜ BAŞARISIZ')
        for e in errors:
            print(' - ' + e)
        return 1
    print('Yerelleştirme kontrolü temiz: %d katalog metni, %d dil' % (len(order), n_lang))
    return 0


if __name__ == '__main__':
    sys.exit(main())
