{ lib, pkgs }:
with pkgs;
pkgs.writeShellScriptBin "macshot" ''
  file=/tmp/xxx.png
  ${lib.getExe local.grimshot} --notify save area /tmp/src.png >> /dev/null 2>&1

  ${imagemagick}/bin/convert /tmp/src.png \
    \( +clone -alpha extract \
    -draw 'fill black polygon 0,0 0,8 8,0 fill white circle 8,8 8,0' \
    \( +clone -flip \) -compose Multiply -composite \
    \( +clone -flop \) -compose Multiply -composite \
    \) -alpha off -compose CopyOpacity -composite /tmp/output.png

  ${imagemagick}/bin/convert /tmp/output.png -bordercolor none -border 20 \
  \( +clone -background black -shadow 80x8+15+15 \) \
    +swap -background transparent -layers merge +repage $file

  ${wl-clipboard}/bin/wl-copy -t image/png < $file
  ${libnotify}/bin/notify-send "macshot copied"
  rm /tmp/src.png /tmp/output.png
''
