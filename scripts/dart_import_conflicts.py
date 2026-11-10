#!/usr/bin/env python3
"""Belirsiz içe aktarma (ambiguous import) denetimi — Flutter SDK olmadan.

Her lib/ ve test/ dosyası için içe aktardığı proje kütüphanelerinin (export zinciri dahil)
üst düzey adlarını toplar; aynı ad iki FARKLI kütüphaneden geliyor VE dosyada kullanılıyorsa
hata verir (Dart: "X is imported from both ..."). show/hide/as önekleri dikkate alınır.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = 'juzzio'
DECL = re.compile(
    r'^(?:abstract\s+|sealed\s+|base\s+|final\s+|interface\s+|mixin\s+)*(?:class|enum|mixin|typedef|extension\s+type|extension)\s+([A-Za-z][A-Za-z0-9_]*)'
    r'|^(?:const|final|var|late\s+final)\s+(?:[A-Za-z0-9_<>?,\s\.]+\s+)?([A-Za-z][A-Za-z0-9_]*)\s*='
    r'|^(?:[A-Za-z_][A-Za-z0-9_<>?,\s\.\(\)]*\s+)?([a-zA-Z][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\([^;]*$',
    re.M)
DIRECTIVE = re.compile(r"^(import|export)\s+'([^']+)'\s*([^;]*);", re.M)
KEYWORDS = {'if', 'for', 'while', 'switch', 'return', 'main', 'class', 'get', 'set', 'operator', 'factory', 'void'}
_cache_decl = {}
_cache_exp = {}


def resolve(src_file, uri):
    if uri.startswith('dart:') or uri.startswith('package:') and not uri.startswith(f'package:{PKG}/'):
        return None
    if uri.startswith(f'package:{PKG}/'):
        return os.path.normpath(os.path.join(ROOT, 'lib', uri[len(PKG) + 10:]))
    return os.path.normpath(os.path.join(os.path.dirname(src_file), uri))


def strip(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r"'''.*?'''|\"\"\".*?\"\"\"", "''", text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def own_decls(path):
    if path in _cache_decl:
        return _cache_decl[path]
    names = set()
    try:
        text = strip(open(path, encoding='utf-8').read())
    except OSError:
        _cache_decl[path] = names
        return names
    depth = 0
    for line in text.split('\n'):
        if depth == 0:
            m = DECL.match(line)
            if m:
                n = m.group(1) or m.group(2) or m.group(3)
                if n and not n.startswith('_') and n not in KEYWORDS:
                    names.add(n)
        depth += line.count('{') - line.count('}')
        depth = max(depth, 0)
    _cache_decl[path] = names
    return names


def combinators(rest):
    show = re.search(r'\bshow\s+([\w\s,]+?)(?:\s+hide|$)', rest)
    hide = re.search(r'\bhide\s+([\w\s,]+?)(?:\s+show|$)', rest)
    pref = re.search(r'\bas\s+(\w+)', rest)
    s = {x.strip() for x in show.group(1).split(',')} if show else None
    h = {x.strip() for x in hide.group(1).split(',')} if hide else set()
    return s, h, pref.group(1) if pref else None


def exported(path, seen=None):
    """{ad: tanımlandığı dosya} — dosyanın kendi adları + export ettikleri"""
    if path in _cache_exp:
        return _cache_exp[path]
    seen = seen or set()
    if path in seen:
        return {}
    seen.add(path)
    out = {n: path for n in own_decls(path)}
    try:
        text = strip(open(path, encoding='utf-8').read())
    except OSError:
        return out
    for kind, uri, rest in DIRECTIVE.findall(text):
        if kind != 'export':
            continue
        tgt = resolve(path, uri)
        if not tgt:
            continue
        s, h, _ = combinators(rest)
        for n, origin in exported(tgt, seen).items():
            if (s is None or n in s) and n not in h:
                out.setdefault(n, origin)
    _cache_exp[path] = out
    return out


def check(path):
    text = strip(open(path, encoding='utf-8').read())
    body = DIRECTIVE.sub('', text)
    words = set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b', body))
    origin_of = {}
    errors = []
    local = own_decls(path)
    for kind, uri, rest in DIRECTIVE.findall(text):
        if kind != 'import':
            continue
        tgt = resolve(path, uri)
        if not tgt:
            continue
        s, h, pref = combinators(rest)
        if pref:
            continue
        for n, origin in exported(tgt).items():
            if (s is not None and n not in s) or n in h or n in local:
                continue
            prev = origin_of.get(n)
            if prev and prev != origin and n in words:
                errors.append(f'{os.path.relpath(path, ROOT)}: "{n}" hem {os.path.relpath(prev, ROOT)} hem {os.path.relpath(origin, ROOT)} içinden geliyor')
            origin_of.setdefault(n, origin)
    return errors


def main():
    errs = []
    for base in ('lib', 'test'):
        for dp, _, fs in os.walk(os.path.join(ROOT, base)):
            for f in fs:
                if f.endswith('.dart'):
                    errs += check(os.path.join(dp, f))
    for e in errs:
        print('::error::' + e)
    if errs:
        print(f'✖ Belirsiz içe aktarma: {len(errs)} sorun')
        return 1
    print('✔ Belirsiz içe aktarma yok')
    return 0


if __name__ == '__main__':
    sys.exit(main())
