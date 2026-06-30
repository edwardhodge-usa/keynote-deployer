# Section 03 — Code Review (self-review; pure module, hand-verified oracles)

FrameSignal: channels (luma/sat/chroma), diffSignal (normalized weighted), frameVariance.
All tests use hand-computed expected values (luma 59.8, sat 200, chroma 100 for (200,0,0)).

FINDING carried to §04/§06: multi-channel diff is NOT a clear win over raw RGB mean-abs for
all dark fades — e.g. a blue↔red hue swap leaves sat+chroma invariant, so multi-channel can
UNDER-report vs raw. The genuine dark-fade fix is ADAPTIVE thresholding (small absolute per-step
diff → relative detection) + twin-comparison accumulation, NOT multi-channel superiority. Tests
assert this honestly (the fade registers but as a small absolute value). Weights stay (1,1,1).
No issues. 102/102 green.
