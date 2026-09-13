#!/bin/zsh
# screenshots.html sayfasını App Store boyutunda PNG'ye basar.
# Kullanım: ./render.sh [çıktı-dizini]   (varsayılan: out/tr)
set -e
here=${0:A:h}
out=${1:-$here/out/tr}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
mkdir -p "$out"
for n in 01 02 03 04 05; do
  "$chrome" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size=1320,2868 \
    --allow-file-access-from-files --virtual-time-budget=4000 \
    --screenshot="$out/$n-1320x2868.png" \
    "file://$here/screenshots.html?slide=$n" >/dev/null 2>&1
  echo "$out/$n-1320x2868.png"
done
