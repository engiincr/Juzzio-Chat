#!/usr/bin/env python3
"""flutter test JSON raporundaki başarısız testleri GitHub annotation olarak yazar.

Neden: CI özetinde yalnız "N passed, 2 failed" görünüyordu; hata nedeni (Expected/Actual,
istisna, yığın) yalnız oturum açılarak okunabilen ham günlükteydi. Annotation'lar herkese
açık depolarda API'den de okunabildiği için başarısız testin nedeni doğrudan görünür olur.

Kullanım: python3 scripts/test_failures_annotate.py build/test-report.json
"""
import json
import sys


def esc(s: str) -> str:
    return s.replace('%', '%25').replace('\r', '').replace('\n', '%0A')


def main(path: str) -> int:
    tests, suites, errors = {}, {}, {}
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except OSError:
        print(f'::warning::Test raporu bulunamadı: {path}')
        return 0
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t = e.get('type')
        if t == 'suite':
            suites[e['suite']['id']] = e['suite'].get('path') or ''
        elif t == 'testStart':
            tt = e['test']
            tests[tt['id']] = (tt.get('name', ''), suites.get(tt.get('suiteID'), ''), tt.get('line'))
        elif t == 'error':
            errors.setdefault(e['testID'], []).append((e.get('error', ''), e.get('stackTrace', '')))
    shown = 0
    for tid, errs in errors.items():
        name, path_, line = tests.get(tid, ('(bilinmeyen test)', '', None))
        msg = '\n\n'.join(f'{err.strip()}\n{(st or "").strip()[:1500]}' for err, st in errs)[:6000]
        rel = path_[path_.rfind('/test/') + 1:] if '/test/' in path_ else path_
        loc = f' file={rel}' + (f',line={line}' if line else '') if path_ else ''
        print(f'::error{loc},title={esc("Test başarısız: " + name)}::{esc(msg)}')
        print(f'--- {name} ---\n{msg}\n')
        shown += 1
    if not shown:
        print('Başarısız test bulunamadı (rapor temiz).')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'build/test-report.json'))
