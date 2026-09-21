#!/usr/bin/env bash
# sounds/master.sh — REPRODUCIBLE SFX mastering (spotter table /tmp/shooter/audio_table.md).
# Reads pristine CC0 originals from sounds/raw/, overwrites the game-ready
# files in sounds/. Re-run any time: `bash sounds/master.sh` (needs ffmpeg).
# Measurements that drove each op (ffprobe + ebur128 + volumedetect +
# silencedetect -50dB/0.3s) are in the table; probe echoes below mirror them.
set -euo pipefail
cd "$(dirname "$0")"
FF="${FF:-ffmpeg}"

# -- rifle blast: 15.5s continuous Bedarfsaufnahme; first shot attacks 0.347s,
#    second shot 2.29s. Single-shot window 0.30-1.80s + 0.15s fade-out.
$FF -hide_banner -loglevel error -y -i raw/sfx_rifle_blast.wav -af \
  "atrim=start=0.30:end=1.80,asetpts=PTS-STARTPTS,afade=t=out:st=1.65:d=0.15" \
  -c:a pcm_s16le sfx_rifle_blast.wav

# -- rifle mech: 0.493s leading silence breaks the 0ms layer; content to 1.40s.
#    Strip + declip (true peak was +4.9 dBTP).
$FF -hide_banner -loglevel error -y -i raw/sfx_rifle_mech.mp3 -af \
  "atrim=start=0.45:end=1.45,asetpts=PTS-STARTPTS,alimiter=limit=0.891:attack=5:release=50" \
  -c:a libmp3lame -b:a 128k sfx_rifle_mech.mp3

# -- rifle tail: silence gap 2.615-2.945s; keep attack+decay, 96k -> 48k.
$FF -hide_banner -loglevel error -y -i raw/sfx_rifle_tail.wav -af \
  "atrim=end=2.62,asetpts=PTS-STARTPTS,afade=t=out:st=2.40:d=0.22,aresample=48000" \
  -c:a pcm_s16le -ar 48000 sfx_rifle_tail.wav

# -- mag out: content ends 0.91s, 3.2s trailing silence. Trim + declip (+2.6 dBTP).
$FF -hide_banner -loglevel error -y -i raw/sfx_reload_mag_out.mp3 -af \
  "atrim=end=1.00,asetpts=PTS-STARTPTS,alimiter=limit=0.891:attack=5:release=50" \
  -c:a libmp3lame -b:a 128k sfx_reload_mag_out.mp3

# -- mag in: content 0.1-1.32s. Trim dead air both ends + declip (+2.3 dBTP).
$FF -hide_banner -loglevel error -y -i raw/sfx_reload_mag_in.mp3 -af \
  "atrim=start=0.08:end=1.42,asetpts=PTS-STARTPTS,alimiter=limit=0.891:attack=5:release=50" \
  -c:a libmp3lame -b:a 128k sfx_reload_mag_in.mp3

# -- charging: HOT (+6.4 dBTP, worst clip). -6dB + safety limiter (-1dB ceiling).
$FF -hide_banner -loglevel error -y -i raw/sfx_reload_charging.mp3 -af \
  "volume=-6dB,alimiter=limit=0.891:attack=5:release=50" \
  -c:a libmp3lame -b:a 128k sfx_reload_charging.mp3

# -- steps: too quiet (concrete max -22.0, dirt -16.6 dBFS). +8 / +6 dB.
$FF -hide_banner -loglevel error -y -i raw/sfx_step_concrete.ogg -af \
  "volume=8dB" -c:a libvorbis -q:a 4 sfx_step_concrete.ogg
$FF -hide_banner -loglevel error -y -i raw/sfx_step_dirt.ogg -af \
  "volume=6dB" -c:a libvorbis -q:a 4 sfx_step_dirt.ogg

# -- wind: 81.8s, trailing 1.7s below -50dB = loop seam risk. Cut + 0.5s fade-out.
$FF -hide_banner -loglevel error -y -i raw/amb_wind_loop.mp3 -af \
  "atrim=end=80.10,asetpts=PTS-STARTPTS,afade=t=out:st=79.60:d=0.50" \
  -c:a libmp3lame -b:a 128k amb_wind_loop.mp3

# -- flesh / steel / ui: spotter-clean, keep bit-identical.
cp raw/sfx_impact_flesh.ogg sfx_impact_flesh.ogg
cp raw/sfx_impact_steel.wav sfx_impact_steel.wav
cp raw/sfx_ui_click.wav sfx_ui_click.wav

echo "master.sh OK: $(ls -1 *.wav *.mp3 *.ogg | wc -l) game files from raw/"
