#!/usr/bin/env bash
# Juzzio v1.1.0 — logo PNG'lerini SVG kaynaklarından üretir (rsvg-convert gerekir).
#   bash tools/brand/render_logo.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
B=tools/brand
R=android/app/src/main/res
r() { rsvg-convert -w "$2" -h "$2" "$B/$1" -o "$3"; }
r juzzio_logo.svg 1024 assets/logo/juzzio_logo.png
declare -A LEG=([mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192)
declare -A ADA=([mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432)
declare -A LAU=([mdpi]=120 [hdpi]=180 [xhdpi]=240 [xxhdpi]=360 [xxxhdpi]=480)
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p "$R/mipmap-$d" "$R/drawable-$d"
  r juzzio_logo.svg "${LEG[$d]}" "$R/mipmap-$d/ic_launcher.png"
  r juzzio_foreground.svg "${ADA[$d]}" "$R/mipmap-$d/ic_launcher_foreground.png"
  r juzzio_background.svg "${ADA[$d]}" "$R/mipmap-$d/ic_launcher_background.png"
  r juzzio_monochrome.svg "${ADA[$d]}" "$R/mipmap-$d/ic_launcher_monochrome.png"
  r juzzio_logo.svg "${LAU[$d]}" "$R/drawable-$d/juzzio_launch_logo.png"
done
r juzzio_splash.svg 864 "$R/drawable-xxhdpi/juzzio_splash_icon.png"
echo "logo PNG'leri üretildi"
