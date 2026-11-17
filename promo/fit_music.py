"""Cut the soundtrack for the promo and write the beat-synced timeline.

  uv run --with numpy --with imageio-ffmpeg python fit_music.py <track.mp3>

The video is laid out in bars (script.json). We play ONE continuous stretch of the track — no splices —
chosen so the track's own final chord lands on the first bar of the outro, and fade in over the first bar.

Writes build/audio-fit.wav and timing.js:
  window.TIMING = { bpm, beat, bar, total, scenes: [{ id, bar, start, end }] }   (video time; bar k = k * bar)

Defaults are for "Upbeat Corporate Technology Background" (Roman Senyk, Pixabay, 126 BPM):
first beat at 0.064 s, final chord on bar 114 (217.21 s). Override with BEAT0 / END_BAR.
"""
import json, os, subprocess, sys, wave
import numpy as np
import imageio_ffmpeg

ROOT = os.path.dirname(os.path.abspath(__file__))
cfg = json.load(open(f'{ROOT}/script.json'))
BPM = cfg['bpm']
BEAT = 60 / BPM
BAR = 4 * BEAT
BEAT0 = float(os.environ.get('BEAT0', 0.064))     # track time of beat 0 (a downbeat)
END_BAR = int(os.environ.get('END_BAR', 114))    # track bar of the final chord

scenes, b = [], 0
for s in cfg['scenes']:
    scenes.append({'id': s['id'], 'bar': b, 'start': round(b * BAR, 4), 'end': round((b + s['bars']) * BAR, 4)})
    b += s['bars']
total = b * BAR
outro_bar = next(s['bar'] for s in scenes if s['id'] == 'outro')
start_bar = END_BAR - outro_bar                   # track bar playing at video time 0
t0 = BEAT0 + start_bar * BAR
print(f'{b} bars = {total:.2f}s; track from bar {start_bar} ({t0:.2f}s), final chord at video {outro_bar * BAR:.2f}s')

if len(sys.argv) > 1:
    SR = 44100
    raw = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-loglevel', 'error', '-ss', f'{t0:.4f}', '-i', sys.argv[1],
                          '-t', f'{total:.4f}', '-ac', '2', '-ar', str(SR), '-f', 's16le', '-'], capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.int16).astype(np.float32).reshape(-1, 2) / 32768
    n = int(total * SR)
    x = np.pad(x, ((0, max(0, n - len(x))), (0, 0)))[:n]
    t = np.arange(n) / SR
    fade_in = np.sin(np.clip(t / BAR, 0, 1) * np.pi / 2) ** 2      # one bar, starts silent
    fade_out = np.clip((total - t) / 0.8, 0, 1)
    out = x * (fade_in * fade_out)[:, None] * 10 ** (-2 / 20)
    with wave.open(f'{ROOT}/build/audio-fit.wav', 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes((out.clip(-1, 1) * 32767).astype(np.int16).tobytes())
    print('wrote build/audio-fit.wav')

with open(f'{ROOT}/timing.js', 'w') as f:
    f.write('window.TIMING = ' + json.dumps({'bpm': BPM, 'beat': BEAT, 'bar': BAR, 'total': round(total, 4), 'scenes': scenes}, indent=1) + ';\n')
print('wrote timing.js')
