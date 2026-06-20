#!/usr/bin/env bash
# Build a deployable video deck viewer from a Keynote video export + per-slide stills.
#
#   Keynote -> Export -> Movie (H.264 .m4v, 1080p, CONSTANT 30fps, Self-Playing)
#   Keynote -> Export -> Images (one JPEG per slide)  [= the slide-count source]
#
# Output: a folder with deck.mp4 + index.html, ready to `vercel deploy`.
set -euo pipefail

VIDEO="$1"        # path to the Keynote video export (.m4v/.mov, H.264 or HEVC)
STILLS_DIR="$2"   # folder of per-slide JPEGs (one per slide, naturally sortable)
OUT="${3:-./video-deck-out}"
FPS="${4:-30}"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
mkdir -p "$OUT"

echo "[1/4] extracting downscaled frames for matching"
mkdir -p "$WORK/frames"
ffmpeg -y -i "$VIDEO" -vf scale=32:18 "$WORK/frames/%05d.png" >/dev/null 2>&1

echo "[2/4] DP-matching stills -> video frames -> timestamps"
python3 "$HERE/derive-timestamps.py" "$WORK/frames" "$STILLS_DIR" "$FPS" > "$WORK/boundaries.json"
KF=$(python3 -c "import json;print(','.join(str(t) for t in json.load(open('$WORK/boundaries.json'))['timestamps']))")
echo "    $(python3 -c "import json;print(json.load(open('$WORK/boundaries.json'))['slideCount'])") slides"

echo "[3/4] re-encode H.264 with a forced keyframe at each slide (crisp paused frames + accurate seek)"
# Always re-encode (even from H.264) so each slide's settled frame is an I-frame.
ffmpeg -y -i "$VIDEO" -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p \
  -force_key_frames "$KF" -movflags +faststart -an "$OUT/deck.mp4" >/dev/null 2>&1

echo "[4/4] generate viewer HTML"
cp "$WORK/boundaries.json" "$HERE/boundaries_video.json"   # gen reads this fixed path
node "$HERE/gen-video-viewer.mjs"
cp "$HERE/index.html" "$OUT/index.html"
rm -f "$HERE/boundaries_video.json" "$HERE/index.html"

echo "{}" > "$OUT/vercel.json"
echo "DONE -> $OUT  (cd $OUT && vercel deploy --prod --yes)"
rm -rf "$WORK"
