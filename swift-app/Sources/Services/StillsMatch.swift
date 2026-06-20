import Foundation

/// Error thrown by ``StillsMatch/matchStillsToFrames(_:_:)`` for inputs that
/// cannot yield a valid strictly-increasing assignment.
enum StillsMatchError: Error, Equatable, LocalizedError {
    /// Fewer frames than stills (`M < N`): no strictly-increasing frame index
    /// per still exists. The TS oracle silently returns garbage (`null`/`-1`)
    /// in this case; the Swift port rejects it deterministically instead.
    case tooFewFrames(stills: Int, frames: Int)

    /// Defensive: the backtrack hit an invalid (`-1`) pointer before reaching
    /// row 0, despite `M >= N`. Structurally unreachable (a finite `dp[N-1][endF]`
    /// guarantees an all-≥0 back-chain), but guarded so a future refactor can
    /// never trap on a negative array index where the TS oracle would merely
    /// surface a non-monotonic warning.
    case noValidAssignment(stills: Int, frames: Int)

    /// Actionable, user-facing messages — these surface in the deploy `.error`
    /// phase, so they must read as guidance, not as a raw enum dump.
    var errorDescription: String? {
        switch self {
        case let .tooFewFrames(stills, frames):
            return "You picked \(stills) slide stills but the video only has \(frames) frames. "
                + "Pick the matching stills folder, or re-export the video at a higher frame rate."
        case let .noValidAssignment(stills, frames):
            return "Couldn't align \(stills) stills to the \(frames) video frames in slide order. "
                + "Make sure the stills are one-per-slide, in order, and match this deck."
        }
    }
}

/// Pure, offline DP matcher aligning per-slide stills to video frames.
/// Faithful port of `src/utils/stillsMatch.ts` — the highest-value parity gate:
/// the matched indices become per-slide timestamps baked into the deployed viewer,
/// so they must agree byte-for-byte with the TypeScript oracle.
enum StillsMatch {

    /// Mean absolute difference of two equal-length grids. Empty -> 0.
    /// Mirrors the TS `meanAbs`: assumes equal lengths, divides by `a.count`.
    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double {
        if a.isEmpty { return 0 }
        var s = 0.0
        for i in a.indices { s += abs(a[i] - b[i]) }
        return s / Double(a.count)
    }

    /// Natural (numeric-aware) sort of file names/paths.
    /// A10: implemented via `String.compare(options: .numeric)` rather than the
    /// TS `padStart(10)` key hand-port. The parity tests confirm this orders the
    /// slide-name set identically to the TS `naturalSort`. If `.numeric` ever
    /// diverges from the TS key order, fall back to a direct port of the TS key
    /// (split on digit runs, zero-pad numeric runs to width 10, join, compare).
    static func naturalSort(_ names: [String]) -> [String] {
        return names.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// DP-match N stills to M frames with strictly-increasing frame indices.
    /// Returns one matched frame index per still (length N), monotonic by
    /// construction. Faithful port of `matchStillsToFrames` in `stillsMatch.ts`
    /// — the two parity-load-bearing comparisons are preserved verbatim:
    ///   - prior-frame sweep uses `<=` so the LARGEST prior frame index wins on ties;
    ///   - the end-state scan uses strict `<` so the FIRST minimal end frame wins.
    /// Edge cases: empty stills -> `[]`; single still -> globally-cheapest frame.
    /// `M < N`: throws ``StillsMatchError/tooFewFrames(stills:frames:)`` (the TS
    /// oracle silently returns garbage here; the port rejects deterministically).
    ///
    /// - Important: Callers (e.g. Section 06 `VideoTimestampDeriver`) must CATCH
    ///   the thrown errors and degrade gracefully — the live TS consumer
    ///   (`src/components/GifViewer.tsx`, the non-monotonic fallback) treats a
    ///   bad match as a soft warning that clears slides and falls back to the
    ///   `auto` boundary source, NOT as a hard failure. Propagating the throw to
    ///   the user would be an integration-level parity regression.
    static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) throws -> [Int] {
        let N = stills.count
        let M = frames.count
        if N == 0 { return [] }
        guard M >= N else {
            throw StillsMatchError.tooFewFrames(stills: N, frames: M)
        }

        let INF = Double.infinity
        let cost: [[Double]] = stills.map { s in frames.map { f in meanAbs(s, f) } }
        var dp = [[Double]](repeating: [Double](repeating: INF, count: M), count: N)
        var back = [[Int]](repeating: [Int](repeating: -1, count: M), count: N)

        for f in 0..<M { dp[0][f] = cost[0][f] }
        if N > 1 {
            for i in 1..<N {
                var bestPrev = INF
                var bestPrevIdx = -1
                for f in 0..<M {
                    if f - 1 >= 0 && dp[i - 1][f - 1] <= bestPrev {
                        bestPrev = dp[i - 1][f - 1]
                        bestPrevIdx = f - 1
                    }
                    if bestPrev != INF {
                        dp[i][f] = bestPrev + cost[i][f]
                        back[i][f] = bestPrevIdx
                    }
                }
            }
        }

        var endF = -1
        var best = INF
        for f in 0..<M where dp[N - 1][f] < best {
            best = dp[N - 1][f]
            endF = f
        }

        var out = [Int](repeating: 0, count: N)
        var f = endF
        for i in stride(from: N - 1, through: 0, by: -1) {
            // `f` is a valid (>= 0) column on every iteration for valid input:
            // a finite dp entry always carries a >= 0 back-pointer (row 0 is the
            // only -1, assigned last and discarded after the loop). Guard so a
            // hypothetical -1 mid-chain throws instead of trapping on back[i][-1].
            guard f >= 0 else {
                throw StillsMatchError.noValidAssignment(stills: N, frames: M)
            }
            out[i] = f
            f = back[i][f]
        }
        return out
    }
}
