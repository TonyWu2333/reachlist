# Promo video

A 34-second promo for Reach List (1920×1080, English UI), cut to the beat of its soundtrack. Scenes are an HTML page animated with GSAP and rendered frame by frame with Playwright; app screens are real screenshots of the app with demo data.

```bash
cd promo && npm install
cp ~/Downloads/<track>.mp3 build/music/track.mp3   # the soundtrack is not in the repo
npm run music     # one continuous stretch of the track → build/audio-fit.wav, beat timeline → timing.js
npm run shots     # English app screens + tap positions → build/shots/ (needs `npm run dev` in the repo root, port 5173)
npm run check     # no element may change with seek order or show outside its scene
npm run render    # frames → build/frames/
npm run encode    # → out/reach-list-promo.mp4   (`sh encode.sh` without AUDIO gives a silent cut)
```

Chinese version: the same cut with Chinese copy and Chinese app screens (`index.html?lang=zh`). After `npm run music`, run `npm run shots:zh`, `check:zh`, `render:zh` and `encode:zh` → `out/reach-list-promo-zh.mp4`. All scripts read `PROMO_LANG=zh`.

Covers: `node cover.mjs` renders `cover.html` (English and `?lang=zh`) with the app screens from `npm run shots` / `shots:zh` → `out/cover-en.png`, `out/cover-zh.png`, plus the README thumbnails with a play button in `docs/promo/`.

How the sync works:

- `script.json` gives the tempo and each scene's length in bars. `fit_music.py` turns that into `timing.js` (bar k starts at k × bar) and cuts the track so it plays without any splice, starting at the bar that makes the track's own final chord land on the first bar of the outro. The first bar fades in.
- In `index.html` every event is placed with `b(bar, beat)`: pops, taps and screen changes start on a beat, slides start on the beat and snap in, headline letters step every 1/8 beat, typing every 1/16, and the phone floats once per bar.
- `fit_music.py` defaults are for the current track (126 BPM, first beat at 0.064 s, final chord on bar 114). For another track, set `BEAT0` / `END_BAR` and `bpm` in `script.json`.

Other notes:

- Open `index.html` in a browser and click to preview with sound; `node preview.mjs 3.5 12` renders single frames to `build/preview/`.
- Needs `uv` (numpy and imageio-ffmpeg) and a Chromium for Playwright. To use a Chromium that doesn't match the installed Playwright version, set `EXE=/path/to/headless_shell`.

Music: "Upbeat Corporate Technology Background" by Roman Senyk (Pixabay, track 126137), used under the Pixabay Content License.
