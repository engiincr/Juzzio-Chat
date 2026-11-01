#!/usr/bin/env python3
"""Juzzio — Dart sözcük düzeyi denetimi (Flutter SDK olmayan ortamlar için ön kapı).

Gerçek derleyicinin (flutter analyze) YERİNE GEÇMEZ; yalnızca yapısal hataları erken
yakalar: kapanmamış/eşleşmeyen parantez-köşeli-süslü parantez, kapanmamış dize veya
yorum, dize içi ${...} enterpolasyon dengesi. Dizeler (tek/çift tırnak, üçlü, raw) ve
yorumlar (//, /* */ iç içe) doğru atlanır.

Kullanım: python3 scripts/dart_lexcheck.py [dosya ...]   (varsayılan: lib/ ve test/)
"""
import glob
import os
import sys

PAIRS = {')': '(', ']': '[', '}': '{'}


def check(src: str):
    stack = []  # (char, line)
    i, n, line = 0, len(src), 1

    def err(msg, ln):
        return f"{ln}: {msg}"

    def skip_string(i, line):
        raw = False
        if src[i] in 'rR':
            raw = True
            i += 1
        q = src[i]
        triple = src.startswith(q * 3, i)
        start_line = line
        i += 3 if triple else 1
        while i < n:
            c = src[i]
            if c == '\n':
                if not triple:
                    return None, line, err('dize satır sonunda kapanmadı', start_line)
                line += 1
            if not raw and c == '\\':
                i += 2
                continue
            if not raw and c == '$' and i + 1 < n and src[i + 1] == '{':
                # enterpolasyon: içeride kod var — iç içe dizeleri ve süslüleri izle
                i += 2
                depth = 1
                while i < n and depth:
                    d = src[i]
                    if d == '\n':
                        line += 1
                    if d in '\'"' or (d in 'rR' and i + 1 < n and src[i + 1] in '\'"'):
                        r = skip_string(i, line)
                        if r[0] is None:
                            return r
                        i, line = r[0], r[1]
                        continue
                    if d == '{':
                        depth += 1
                    elif d == '}':
                        depth -= 1
                    i += 1
                if depth:
                    return None, line, err('enterpolasyon kapanmadı', start_line)
                continue
            if triple and src.startswith(q * 3, i):
                return i + 3, line, None
            if not triple and c == q:
                return i + 1, line, None
            i += 1
        return None, line, err('dize dosya sonuna kadar kapanmadı', start_line)

    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            depth, j, start = 1, i + 2, line
            while j < n and depth:
                if src.startswith('/*', j):
                    depth += 1
                    j += 2
                    continue
                if src.startswith('*/', j):
                    depth -= 1
                    j += 2
                    continue
                if src[j] == '\n':
                    line += 1
                j += 1
            if depth:
                return err('blok yorum kapanmadı', start)
            i = j
            continue
        is_raw = c in 'rR' and i + 1 < n and src[i + 1] in '\'"' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_'))
        if c in '\'"' or is_raw:
            r = skip_string(i, line)
            if r[0] is None:
                return r[2]
            i, line = r[0], r[1]
            continue
        if c in '([{':
            stack.append((c, line))
        elif c in ')]}':
            if not stack:
                return err(f"fazla '{c}'", line)
            o, ol = stack.pop()
            if o != PAIRS[c]:
                return err(f"'{o}' ({ol}. satır) '{c}' ile kapatıldı", line)
        i += 1
    if stack:
        o, ol = stack[-1]
        return err(f"'{o}' kapanmadı", ol)
    return None


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = argv or sorted(glob.glob(os.path.join(root, 'lib', '**', '*.dart'), recursive=True)
                           + glob.glob(os.path.join(root, 'test', '**', '*.dart'), recursive=True))
    bad = 0
    for f in files:
        with open(f, encoding='utf-8') as fh:
            problem = check(fh.read())
        if problem:
            bad += 1
            print(f"::error file={os.path.relpath(f, root)}::{problem}")
    print(f"{'✖' if bad else '✔'} Dart sözcük denetimi: {len(files)} dosya, {bad} sorun")
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
