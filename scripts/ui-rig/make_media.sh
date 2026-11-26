#!/bin/bash
# Makes the rig's sample videos (Linux runner, ffmpeg + espeak-ng): drawn pictures with a running clock and
# a computer voice that says the time every ten seconds. Nothing recorded from a person or a real phone.
# Usage: make_media.sh small|long|big OUT_DIR
set -euo pipefail
PACK="$1"; OUT="$2"; TMP=$(mktemp -d); mkdir -p "$OUT"
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

voice() { # seconds: makes $TMP/voice-N.wav
  local n="$1" i m s list="$TMP/list-$1.txt"; : > "$list"
  for ((i = 0; i < n; i += 10)); do
    m=$((i / 60)); s=$((i % 60))
    if [ ! -f "$TMP/v-$i.wav" ]; then
      espeak-ng -s 150 -w "$TMP/raw.wav" "We are at $m minutes and $s seconds. Here is the next part of the sample."
      ffmpeg -v error -y -i "$TMP/raw.wav" -af apad -t 10 -ar 44100 -ac 1 "$TMP/v-$i.wav"
    fi
    echo "file '$TMP/v-$i.wav'" >> "$list"
  done
  ffmpeg -v error -y -f concat -safe 0 -i "$list" -t "$n" -c copy "$TMP/voice-$n.wav"
}

clip() { # name size fps seconds colour extra-video-options...
  local name="$1" size="$2" fps="$3" n="$4" colour="$5"; shift 5
  local w="${size%x*}" h="${size#*x}" f box
  f=$((w / 9)); if [ "$w" -gt "$h" ]; then f=$((h / 6)); fi
  box=$((w / 8 / 2 * 2))
  [ -f "$TMP/voice-$n.wav" ] || voice "$n"
  ffmpeg -v error -y -f lavfi -i "color=c=$colour:s=$size:r=$fps:d=$n" \
    -f lavfi -i "color=c=0xFFC247:s=${box}x${box}:r=$fps:d=$n" -i "$TMP/voice-$n.wav" \
    -filter_complex "[0][1]overlay=x='mod(t*$((w / 6)),W-w)':y='H*0.72+sin(t*2)*H*0.06'[a];[a]drawbox=x=iw*0.06:y=ih*0.08:w=iw*0.88:h=ih*0.16:color=white@0.92:t=fill,drawtext=fontfile=$FONT:text='Sample $name':fontsize=$((f / 2)):fontcolor=0x222222:x=(w-text_w)/2:y=h*0.13,drawtext=fontfile=$FONT:text='%{pts\:hms}':fontsize=$f:fontcolor=white:x=(w-text_w)/2:y=h*0.42,drawtext=fontfile=$FONT:text='frame %{n}':fontsize=$((f / 3)):fontcolor=white:x=(w-text_w)/2:y=h*0.58[v]" \
    -map "[v]" -map 2:a -c:v libx264 -preset veryfast -crf 24 -pix_fmt yuv420p -c:a aac -b:a 96k \
    -movflags +faststart -shortest "$@" "$OUT/$name.mp4"
  ls -la "$OUT/$name.mp4"
}

case "$PACK" in
  small)
    clip short 886x1920 30 12 0x1E3A5F
    clip landscape 1920x1080 30 20 0x7A2E3A
    clip square 1080x1080 30 10 0x2F5D50
    clip silent 886x1920 30 15 0x4B3F72 -an
    clip hevc60 1920x1080 60 15 0x3B3B98 -c:v libx265 -preset fast -tag:v hvc1 -x265-params log-level=error
    clip upright 1280x720 30 12 0x8C4A1F
    ffmpeg -v error -y -display_rotation 90 -i "$OUT/upright.mp4" -c copy "$OUT/turned.mp4"; rm "$OUT/upright.mp4"
    ffmpeg -v error -y -f lavfi -i "color=c=0x2F5D50:s=1600x1200,drawtext=fontfile=$FONT:text='A picture':fontsize=160:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
      -frames:v 1 "$OUT/picture.jpg"
    clip 4min 886x1920 30 253 0x1E3A5F
    clip 9min 1920x1080 30 540 0x274046
    ;;
  long) clip 30min 1280x720 24 1800 0x3A2C4D ;;
  big) clip big 1920x1080 30 600 0x12343B -b:v 17M -minrate 17M -maxrate 17M -bufsize 34M -x264-params nal-hrd=cbr ;;
esac
rm -rf "$TMP"
