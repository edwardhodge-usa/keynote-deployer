import Foundation

/// A detected transition between two slides, in VIDEO FRAME indices.
/// `start` (Fs) = where the outgoing transition begins (→ the previous slide's Go).
/// `end`   (Fe) = where the incoming slide has settled (→ the next slide's hold region).
struct TransitionSpan: Sendable, Equatable {
    let start: Int
    let end: Int
    let kind: Kind
    enum Kind: Sendable, Equatable { case cut, gradual }
}

/// Finds transition spans over a deck's diff signal + per-frame variances, so the hold
/// for slide i is the gap between transition i-1's end and transition i's start.
///
/// Three mechanisms (per the §04 division of labour):
///  1. **Hard cut** — `localRatio ≥ cutRatio` AND `diff ≥ hard` (a local spike on a real
///     cut). localRatios is a hard-cut detector; a sustained fade is a plateau (ratio ≈ 1),
///     so cuts and fades use different paths.
///  2. **Twin-comparison gradual** — a run of frames in `[gradual, hard)` whose accumulated
///     sum crosses `hard` is a gradual transition (the dark-fade path), with a small grace
///     for single-frame noise dropouts so one dissolve isn't split in two.
///  3. **Variance vote** — a SHORT monochrome dip (flanked by content) is a fade-through-black;
///     a SUSTAINED low-variance run (≥ minHold) is a held black SLIDE, NOT a transition.
///
/// IMPORTANT: this is deliberately a CANDIDATE detector. It cannot tell a within-slide build
/// from a slide-changing fade by pixels alone (both are sustained sub-hard motion) — so it may
/// over-detect on build-heavy decks. The final per-slide count is enforced by `HoldDetector`
/// (section 07) using the stills/anchor count as the authority; this module only says WHERE
/// candidate boundaries are. Pure; no I/O.
enum BoundaryDetector {

    /// Local-ratio multiple that marks a hard cut (unitless; ~3× the local baseline).
    static let cutRatio = 3.0
    /// Consecutive sub-`gradual` frames tolerated inside a gradual run before it ends
    /// (bridges a single noisy dropout so one dissolve isn't split in two).
    static let graceLimit = 2
    /// A frame is "near-monochrome" when its variance is below this fraction of the deck's
    /// median frame variance (the fade-through-black signal).
    static let lowVarianceFraction = 0.1
    /// Spans within this many frames of each other belong to the SAME transition and are
    /// MERGED (e.g. a variance dip confirming/extending a diff-based fade), as opposed to
    /// two distinct-but-too-close transitions (> mergeGap, < minHold → the later is dropped).
    static let mergeGap = 2

    static func transitions(diffSignal: [Double],
                            variances: [Double],
                            fps: Double,
                            minHoldSeconds: Double = 0.5) -> [TransitionSpan] {
        let frameCount = variances.count
        guard frameCount > 1, !diffSignal.isEmpty else { return [] }
        let minHoldFrames = Swift.max(1, Int((minHoldSeconds * fps).rounded()))
        let (hard, gradual) = AdaptiveThreshold.dualThreshold(diffSignal)
        let ratios = AdaptiveThreshold.localRatios(diffSignal, window: AdaptiveThreshold.window(forFps: fps))
        // Trim to the contractual length (diffSignal[i] = diff between frame i and i+1, so
        // valid diff indices are 0..<frameCount-1). A caller passing a mismatched length can't
        // then index past the frame range.
        let m = Swift.min(diffSignal.count, frameCount - 1)

        var raw: [TransitionSpan] = []

        // 1 + 2. Diff-based walk: hard cuts and twin-comparison gradual runs.
        var i = 0
        while i < m {
            // Hard cut: a LOCAL spike (ratio ≥ cutRatio) above the noise floor. The local
            // ratio is the discriminator; gating on the deck-wide `hard` would miss a real
            // smaller-magnitude cut that sits beside larger cuts (mixed-magnitude blind spot).
            if ratios[i] >= cutRatio && diffSignal[i] >= AdaptiveThreshold.hardFloor {
                raw.append(TransitionSpan(start: i, end: i + 1, kind: .cut))
                i += 1
                continue
            }
            // Gradual run: accumulate frames ≥ gradual (with grace) until the sum reaches hard.
            if diffSignal[i] >= gradual {
                var sum = 0.0, j = i, lastStrong = i, grace = 0
                while j < m {
                    if diffSignal[j] >= gradual { sum += diffSignal[j]; lastStrong = j; grace = 0; j += 1 }
                    else if grace < graceLimit { grace += 1; j += 1 }
                    else { break }
                }
                if sum >= hard {
                    let kind: TransitionSpan.Kind = lastStrong > i ? .gradual : .cut
                    raw.append(TransitionSpan(start: i, end: lastStrong + 1, kind: kind))
                }
                i = Swift.max(i + 1, lastStrong + 1)
                continue
            }
            i += 1
        }

        // 3. Variance vote: short monochrome dips → gradual transitions; sustained → holds.
        raw += varianceDipSpans(variances, minHoldFrames: minHoldFrames)

        return resolve(raw, frameCount: frameCount, minHoldFrames: minHoldFrames)
    }

    // MARK: variance vote

    /// Spans where a SHORT near-monochrome dip (flanked by content) marks a fade-through-black.
    /// A low-variance run lasting ≥ minHoldFrames is a held black SLIDE → NOT a transition.
    static func varianceDipSpans(_ variances: [Double], minHoldFrames: Int) -> [TransitionSpan] {
        let n = variances.count
        guard n > 2 else { return [] }
        // Center on the NON-ZERO variances so a deck dominated by black/monochrome slides
        // (≥50% zero-variance) still has a meaningful "low" threshold; fall back to the
        // overall median when everything is flat.
        let nonZero = variances.filter { $0 > 0 }
        let med = nonZero.isEmpty ? AdaptiveThreshold.median(variances) : AdaptiveThreshold.median(nonZero)
        guard med > 0 else { return [] }               // an all-flat deck has no fade-dip signal
        let lowThr = lowVarianceFraction * med
        var spans: [TransitionSpan] = []
        var i = 0
        while i < n {
            guard variances[i] < lowThr else { i += 1; continue }
            var j = i
            while j < n && variances[j] < lowThr { j += 1 }
            let runLen = j - i
            let flanked = i > 0 && j < n               // content on both sides (not clip start/end)
            if runLen < minHoldFrames && flanked {
                // end = j (one past the dip) so a 1-frame dip is still a non-zero-width span
                // (Fe > Fs per the contract). Clamped in resolve().
                spans.append(TransitionSpan(start: i, end: Swift.min(n - 1, j), kind: .gradual))
            }
            // runLen >= minHoldFrames → a held monochrome slide: emit nothing (it's a HOLD).
            i = j
        }
        return spans
    }

    // MARK: resolve

    /// Sort, clamp, then either MERGE (same transition) or DROP (distinct but too close).
    /// MERGE is load-bearing: a variance-dip span and a diff-based fade span for the SAME
    /// transition must union into the full fade, never compete — otherwise an early short dip
    /// would truncate the real fade and the next slide's Rest would land mid-transition (the
    /// exact defect this whole feature exists to remove).
    static func resolve(_ spans: [TransitionSpan], frameCount: Int, minHoldFrames: Int) -> [TransitionSpan] {
        let hi = frameCount - 1
        let clamped: [TransitionSpan] = spans.map { s in
            let cs = Swift.max(0, Swift.min(s.start, hi))
            let ce = Swift.max(0, Swift.min(s.end, hi))
            return TransitionSpan(start: cs, end: ce, kind: s.kind)
        }
        let valid: [TransitionSpan] = clamped.filter { $0.start <= $0.end }
        let sorted: [TransitionSpan] = valid.sorted { (a: TransitionSpan, b: TransitionSpan) -> Bool in
            a.start != b.start ? a.start < b.start : a.end < b.end
        }
        var kept: [TransitionSpan] = []
        for s in sorted {
            guard let last = kept.last else { kept.append(s); continue }
            if s.start <= last.end + mergeGap {
                // Same transition → union; keep the kind of the LONGER contributor (a real
                // fade outweighs a short confirming dip).
                let newEnd = Swift.max(last.end, s.end)
                let kind: TransitionSpan.Kind = (last.end - last.start) >= (s.end - s.start) ? last.kind : s.kind
                kept[kept.count - 1] = TransitionSpan(start: last.start, end: newEnd, kind: kind)
            } else if s.start < last.end + minHoldFrames {
                continue            // distinct but too close → min-hold drops the later one
            } else {
                kept.append(s)
            }
        }
        return kept
    }
}
