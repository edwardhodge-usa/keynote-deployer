# Section 05 — Code Review (self-review; pure module, hand-verified)

RestSelector: argmin local-diff (calmest) over the hold interior, near-ties (within
calmTieBand=0.5) broken by max variance-of-Laplacian on luma (sharper wins). Degenerate-safe.
Verified: calm-interior pick, sharper-wins-tie (returns the sharp calm frame not the flat one),
margin excludes edges, empty/single-frame safe. VoL computed on interior cells only (border skipped).
calmTieBand named for §08 tuning. No issues. 114/114 green.
