#!/usr/bin/env bash
# Juzzio v0.9.9 — tüm el sprite setini üretir (assets/cloth/).
#   hand_c0..c7 : yumruk kıvrılma kareleri (swing 0)
#   hand_s<idx> : sarkaç pozları, açı = -15 + 5*idx (idx 0..8), parmak yelpazesi açıyla artar
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../assets/cloth
mkdir -p "$OUT"
jobs_n=${JOBS:-2}
run() { python3 hand.py "$@"; }
export -f run 2>/dev/null || true
cmds=()
for i in 0 1 2 3 4 5 6 7; do
  c=$(python3 -c "print(round($i/7,4))")
  cmds+=("$OUT/hand_c$i.png --curl $c")
done
for i in 0 1 2 3 4 5 6 7 8; do
  a=$(( -15 + 5*i ))
  s=$(python3 -c "a=$a; print(round(max(0,a)/25 + 0.25*max(0,-a)/15,4))")
  cmds+=("$OUT/hand_s$i.png --curl 0 --swing $a --spread $s")
done
printf '%s\n' "${cmds[@]}" | xargs -P "$jobs_n" -I{} sh -c 'python3 hand.py {}'
