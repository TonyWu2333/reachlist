#!/bin/sh
# usage: sh encode.sh [frames_dir] -> out/reach-list-promo.mp4 (PROMO_LANG=zh -> out/reach-list-promo-zh.mp4)
# Silent by default. AUDIO=1 adds build/audio.wav (npm run audio); AUDIO=<file> adds that file
# (e.g. AUDIO=build/audio-fit.wav from fit_music.py).
set -e
OUT="out/reach-list-promo${PROMO_LANG:+-$PROMO_LANG}.mp4"
cd "$(dirname "$0")"
FF=$(uv run -q --with imageio-ffmpeg python -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")
mkdir -p out
if [ "$AUDIO" = 1 ]; then AUDIO=build/audio.wav; fi
if [ -n "$AUDIO" ]; then
  "$FF" -y -loglevel error -framerate 30 -i "${1:-build/frames}/%05d.jpg" -i "$AUDIO" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart \
    -c:a aac -b:a 192k -ar 44100 -shortest "$OUT"
else
  "$FF" -y -loglevel error -framerate 30 -i "${1:-build/frames}/%05d.jpg" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart "$OUT"
fi
ls -lh out
