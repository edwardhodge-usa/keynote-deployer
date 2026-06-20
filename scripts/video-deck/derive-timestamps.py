#!/usr/bin/env python3
"""
Derive per-slide settled TIMESTAMPS for a deck video by DP-matching the deck's
per-slide still exports to the video's frames. This is the ONLY reliable way to
find slide boundaries on held-build / constant-background decks (frame-diff Auto
detection fails — see VIDEO_DECK_VIEWER.md).

  N stills  ->  N monotonic frame matches  ->  N timestamps (frame_index / fps)

Re-run this PER VIDEO EXPORT — a fresh Keynote render gives different frame
indices even at the same duration/framecount.

Usage:
  # 1) extract downscaled frames from the video (CFR, e.g. 30fps):
  ffmpeg -y -i deck.m4v -vf scale=32:18 frames/%05d.png
  # 2) match:
  python3 derive-timestamps.py <frames_dir> <stills_dir> <fps> > boundaries.json
"""
import sys, glob, json
from PIL import Image

frames_dir, stills_dir, fps = sys.argv[1], sys.argv[2], float(sys.argv[3])
SW, SH = 32, 18

def grid(p):
    return [v for px in Image.open(p).convert("RGB").resize((SW, SH)).getdata() for v in px]

F = [grid(p) for p in sorted(glob.glob(frames_dir + "/*.png"))]
S = [grid(p) for p in sorted(glob.glob(stills_dir + "/*.jp*g") + glob.glob(stills_dir + "/*.png"))]
M, N = len(F), len(S)

def mad(a, b):
    return sum(abs(a[i] - b[i]) for i in range(len(a))) / len(a)

# Monotonic DP alignment of N stills onto M frames (matchStillsToFrames).
INF = float("inf")
cost = [[mad(S[i], F[f]) for f in range(M)] for i in range(N)]
dp = [[INF] * M for _ in range(N)]
back = [[-1] * M for _ in range(N)]
for f in range(M):
    dp[0][f] = cost[0][f]
for i in range(1, N):
    bestPrev, bestIdx = INF, -1
    for f in range(M):
        if f - 1 >= 0 and dp[i-1][f-1] <= bestPrev:
            bestPrev, bestIdx = dp[i-1][f-1], f - 1
        if bestPrev != INF:
            dp[i][f] = bestPrev + cost[i][f]
            back[i][f] = bestIdx
endF = min(range(M), key=lambda f: dp[N-1][f])
out = [0] * N
f = endF
for i in range(N - 1, -1, -1):
    out[i] = f
    f = back[i][f]

assert all(out[i] < out[i+1] for i in range(N-1)), "matched frames not monotonic"
print(json.dumps({
    "frames": out,
    "timestamps": [round(fr / fps, 3) for fr in out],
    "fps": fps,
    "slideCount": N,
}))
