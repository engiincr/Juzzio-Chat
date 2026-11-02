#!/usr/bin/env bash
# Edge Function saf yardımcılarının birim testleri (Deno gerekmez: tsc + node).
# Her test scripts/edge_unit/<ad>.test.ts → supabase/functions/_shared/<ad>.ts dosyasını "./<ad>.js" olarak içe aktarır.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
for t in "$ROOT"/scripts/edge_unit/*.test.ts; do
  name="$(basename "$t" .test.ts)"
  rm -rf "$TMP"/*
  cp "$ROOT/supabase/functions/_shared/$name.ts" "$TMP/$name.ts"
  cp "$t" "$TMP/$name.test.ts"
  (cd "$TMP" && tsc --target ES2022 --module ES2022 --moduleResolution bundler --outDir out --skipLibCheck "$name.ts" "$name.test.ts")
  echo '{"type":"module"}' > "$TMP/out/package.json"
  node "$TMP/out/$name.test.js" || fail=1
done
exit $fail
