#!/bin/zsh
# screenshots.html sayfasını App Store boyutlarında PNG'ye basar.
# Kullanım: ./render.sh            → out/tr/iphone ve out/tr/ipad
set -e
here=${0:A:h}
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

shoot() {  # $1 cihaz  $2 genişlik  $3 yükseklik
  local dev=$1 w=$2 h=$3
  local out="$here/out/tr/$dev"
  mkdir -p "$out"
  for n in 01 02 03 04 05; do
    local url="file://$here/screenshots.html?slide=$n"
    [ "$dev" = "ipad" ] && url="$url&device=ipad"
    "$chrome" --headless --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=1 --window-size=$w,$h \
      --allow-file-access-from-files --virtual-time-budget=5000 \
      --screenshot="$out/$n.png" "$url" >/dev/null 2>&1
    echo "$out/$n.png"
  done
}

shoot iphone 1320 2868
shoot ipad   2064 2752
