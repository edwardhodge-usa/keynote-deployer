swift-app/Sources/Services/GridSampler.swift |  61 ++++++++++++++
 swift-app/Sources/Services/StillsMatch.swift |  92 +++++++++++++++++++++
 swift-app/Tests/GridSamplerTests.swift       |  73 +++++++++++++++++
 swift-app/Tests/StillsMatchTests.swift       | 116 +++++++++++++++++++++++++++
 4 files changed, 342 insertions(+)

--- Changes ---

swift-app/Sources/Services/GridSampler.swift
  @@ -0,0 +1,61 @@
  +import CoreGraphics
  +
  +/// Downscales a `CGImage` (a decoded still, or a decoded video frame) to a fixed
  +/// 32×18 sRGB-normalized RGB grid and returns a flat `[Double]` in `0...255`,
  +/// row-major R,G,B per pixel. Used by both the stills path and the encoder's
  +/// frame sampler so cross-engine comparison happens in one color space (A3).
  +enum GridSampler {
  +    /// Grid width in cells.
  +    static let width = 32
  +    /// Grid height in cells.
  +    static let height = 18
  +    /// Channels emitted per cell (R,G,B — alpha skipped).
  +    static let channels = 3
  +    /// Flat output length: 32 × 18 × 3 = 1728.
  +    static let valueCount = width * height * channels
  +
  +    /// Downscale a CGImage to a 32×18 RGB grid -> 1728 Doubles in 0...255.
  +    /// A3: draws the source into an explicit sRGB context before sampling so
  +    /// stills (often Display P3) and frames (sRGB) compare in one color space.
  +    static func sample(_ image: CGImage) -> [Double] {
  +        let bytesPerPixel = 4
  +        let bytesPerRow = width * bytesPerPixel
  +        let space = CGColorSpace(name: CGColorSpace.sRGB)!
  +        // RGBA, alpha last. Drawing into an sRGB context converts a Display-P3
  +        // (or any tagged) source into sRGB — this is amendment A3.
  +        guard let ctx = CGContext(
  +            data: nil,
  +            width: width,
  +            height: height,
  +            bitsPerComponent: 8,
  +            bytesPerRow: bytesPerRow,
  +            space: space,
  +            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  +        ) else {
  +            return [Double](repeating: 0, count: valueCount)
  +        }
  +
  +        // .high so downscaling averages source pixels (a solid-color image must
  +        // yield a near-uniform grid rather than a single nearest-neighbor sample).
  +        ctx.interpolationQuality = .high
  +        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  +
  +        guard let data = ctx.data else {
  +            return [Double](repeating: 0, count: valueCount)
  +        }
  +        let ptr = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
  +
  +        var out = [Double]()
  +        out.reserveCapacity(valueCount)
  +        for y in 0..<height {
  +            let row = y * bytesPerRow
  +            for x in 0..<width {
  +                let p = row + x * bytesPerPixel
  +                out.append(Double(ptr[p]))     // R
  +                out.append(Double(ptr[p + 1])) // G
  +                out.append(Double(ptr[p + 2])) // B
  +            }
  +        }
  +        return out
  +    }
  +}
  +61 -0

swift-app/Sources/Services/StillsMatch.swift
  @@ -0,0 +1,92 @@
  +import Foundation
  +
  +/// Error thrown by ``StillsMatch/matchStillsToFrames(_:_:)`` for inputs that
  +/// cannot yield a valid strictly-increasing assignment.
  +enum StillsMatchError: Error, Equatable {
  +    /// Fewer frames than stills (`M < N`): no strictly-increasing frame index
  +    /// per still exists. The TS oracle silently returns garbage (`null`/`-1`)
  +    /// in this case; the Swift port rejects it deterministically instead.
  +    case tooFewFrames(stills: Int, frames: Int)
  +}
  +
  +/// Pure, offline DP matcher aligning per-slide stills to video frames.
  +/// Faithful port of `src/utils/stillsMatch.ts` — the highest-value parity gate:
  +/// the matched indices become per-slide timestamps baked into the deployed viewer,
  +/// so they must agree byte-for-byte with the TypeScript oracle.
  +enum StillsMatch {
  +
  +    /// Mean absolute difference of two equal-length grids. Empty -> 0.
  +    /// Mirrors the TS `meanAbs`: assumes equal lengths, divides by `a.count`.
  +    static func meanAbs(_ a: [Double], _ b: [Double]) -> Double {
  +        if a.isEmpty { return 0 }
  +        var s = 0.0
  +        for i in a.indices { s += abs(a[i] - b[i]) }
  +        return s / Double(a.count)
  +    }
  +
  +    /// Natural (numeric-aware) sort of file names/paths.
  +    /// A10: implemented via `String.compare(options: .numeric)` rather than the
  +    /// TS `padStart(10)` key hand-port. The parity tests confirm this orders the
  +    /// slide-name set identically to the TS `naturalSort`. If `.numeric` ever
  +    /// diverges from the TS key order, fall back to a direct port of the TS key
  +    /// (split on digit runs, zero-pad numeric runs to width 10, join, compare).
  +    static func naturalSort(_ names: [String]) -> [String] {
  +        return names.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
  +    }
  +
  +    /// DP-match N stills to M frames with strictly-increasing frame indices.
  +    /// Returns one matched frame index per still (length N), monotonic by
  +    /// construction. Faithful port of `matchStillsToFrames` in `stillsMatch.ts`
  +    /// — the two parity-load-bearing comparisons are preserved verbatim:
  +    ///   - prior-frame sweep uses `<=` so the LARGEST prior frame index wins on ties;
  +    ///   - the end-state scan uses strict `<` so the FIRST minimal end frame wins.
  +    /// Edge cases: empty stills -> `[]`; single still -> globally-cheapest frame.
  +    /// `M < N`: throws ``StillsMatchError/tooFewFrames(stills:frames:)`` (the TS
  +    /// oracle silently returns garbage here; the port rejects deterministically).
  +    static func matchStillsToFrames(_ stills: [[Double]], _ frames: [[Double]]) throws -> [Int] {
  +        let N = stills.count
  +        let M = frames.count
  +        if N == 0 { return [] }
  +        guard M >= N else {
  +            throw StillsMatchError.tooFewFrames(stills: N, frames: M)
  +        }
  +
  +        let INF = Double.infinity
  +        let cost: [[Double]] = stills.map { s in frames.map { f in meanAbs(s, f) } }
  +        var dp = [[Double]](repeating: [Double](repeating: INF, count: M), count: N)
  +        var back = [[Int]](repeating: [Int](repeating: -1, count: M), count: N)
  +
  +        for f in 0..<M { dp[0][f] = cost[0][f] }
  +        if N > 1 {
  +            for i in 1..<N {
  +                var bestPrev = INF
  +                var bestPrevIdx = -1
  +                for f in 0..<M {
  +                    if f - 1 >= 0 && dp[i - 1][f - 1] <= bestPrev {
  +                        bestPrev = dp[i - 1][f - 1]
  +                        bestPrevIdx = f - 1
  +                    }
  +                    if bestPrev != INF {
  +                        dp[i][f] = bestPrev + cost[i][f]
  +                        back[i][f] = bestPrevIdx
  +                    }
  +                }
  +            }
  +        }
  +
  +        var endF = -1
  +        var best = INF
  +        for f in 0..<M where dp[N - 1][f] < best {
  +            best = dp[N - 1][f]
  +            endF = f
  +        }
  +
  +        var out = [Int](repeating: 0, count: N)
  +        var f = endF
  +        for i in stride(from: N - 1, through: 0, by: -1) {
  +            out[i] = f
  +            f = back[i][f]
  +        }
  +        return out
  +    }
  +}
  +92 -0

swift-app/Tests/GridSamplerTests.swift
  @@ -0,0 +1,73 @@
  +import Testing
  +import CoreGraphics
  +@testable import KeynoteDeployer
  +
  +@Suite("Section 2 — GridSampler shape + sRGB normalization")
  +struct GridSamplerTests {
  +
  +    /// Build a solid-color `CGImage` of the given size in the given color space.
  +    /// `comps` are raw channel bytes (0...255) interpreted in `space`.
  +    private func solidImage(
  +        r: UInt8, g: UInt8, b: UInt8,
  +        space: CGColorSpace,
  +        width: Int = 64, height: Int = 36
  +    ) -> CGImage {
  +        let bitsPerComponent = 8
  +        let bytesPerRow = width * 4
  +        let info = CGImageAlphaInfo.premultipliedLast.rawValue
  +        let ctx = CGContext(
  +            data: nil, width: width, height: height,
  +            bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
  +            space: space, bitmapInfo: info
  +        )!
  +        ctx.setFillColor(
  +            red: CGFloat(r) / 255, green: CGFloat(g) / 255,
  +            blue: CGFloat(b) / 255, alpha: 1
  +        )
  +        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  +        return ctx.makeImage()!
  +    }
  +
  +    private var sRGB: CGColorSpace { CGColorSpace(name: CGColorSpace.sRGB)! }
  +    private var p3: CGColorSpace { CGColorSpace(name: CGColorSpace.displayP3)! }
  +
  +    @Test func sampleReturnsExactly1728Values() {
  +        let img = solidImage(r: 10, g: 20, b: 30, space: sRGB)
  +        let grid = GridSampler.sample(img)
  +        #expect(grid.count == GridSampler.valueCount)
  +        #expect(grid.count == 1728)
  +    }
  +
  +    @Test func allValuesInRange() {
  +        let img = solidImage(r: 200, g: 100, b: 50, space: sRGB)
  +        let grid = GridSampler.sample(img)
  +        #expect(grid.allSatisfy { $0 >= 0 && $0 <= 255 })
  +    }
  +
  +    @Test func solidColorYieldsNearUniformGrid() {
  +        // Pure red in sRGB -> every cell ~ (255, 0, 0).
  +        let img = solidImage(r: 255, g: 0, b: 0, space: sRGB)
  +        let grid = GridSampler.sample(img)
  +        // Row-major R,G,B triples.
  +        for i in stride(from: 0, to: grid.count, by: 3) {
  +            #expect(abs(grid[i] - 255) <= 2)      // R
  +            #expect(abs(grid[i + 1] - 0) <= 2)    // G
  +            #expect(abs(grid[i + 2] - 0) <= 2)    // B
  +        }
  +    }
  +
  +    @Test func a3NeutralGrayIsColorSpaceStable() {
  +        // A3: a still (often Display P3) and a frame (sRGB) of the SAME visual
  +        // color must produce near-equal grids after sRGB normalization. Neutral
  +        // gray shares the gray axis + D65 white point across sRGB and P3, so a
  +        // correct sRGB normalization yields near-equal grids; per-channel diffs
  +        // must stay within a small tolerance.
  +        let gray: UInt8 = 128
  +        let sRGBGrid = GridSampler.sample(solidImage(r: gray, g: gray, b: gray, space: sRGB))
  +        let p3Grid = GridSampler.sample(solidImage(r: gray, g: gray, b: gray, space: p3))
  +        #expect(sRGBGrid.count == p3Grid.count)
  +        for i in 0..<sRGBGrid.count {
  +            #expect(abs(sRGBGrid[i] - p3Grid[i]) <= 3)
  +        }
  +    }
  +}
  +73 -0

swift-app/Tests/StillsMatchTests.swift
  @@ -0,0 +1,116 @@
  +import Testing
  +@testable import KeynoteDeployer
  +
  +/// Parity gate for the DP matcher. Every expected array below was captured by
  +/// running the SAME input through the TypeScript `matchStillsToFrames`
  +/// (`src/utils/stillsMatch.ts`) via `node`, then hard-coded here as the oracle.
  +@Suite("Section 2 — StillsMatch parity")
  +struct StillsMatchTests {
  +
  +    // MARK: meanAbs
  +
  +    @Test func meanAbsKnownValue() {
  +        // |1-4| + |2-2| + |3-0| = 3 + 0 + 3 = 6; 6 / 3 = 2
  +        #expect(StillsMatch.meanAbs([1, 2, 3], [4, 2, 0]) == 2)
  +    }
  +
  +    @Test func meanAbsEmptyIsZero() {
  +        #expect(StillsMatch.meanAbs([], []) == 0)
  +    }
  +
  +    // MARK: matchStillsToFrames — parity vs TS oracle
  +
  +    @Test func matchCleanMonotonic() throws {
  +        // TS oracle: match([[0],[10],[20]], [[0],[5],[10],[15],[20]]) -> [0,2,4]
  +        let out = try StillsMatch.matchStillsToFrames(
  +            [[0], [10], [20]],
  +            [[0], [5], [10], [15], [20]]
  +        )
  +        #expect(out == [0, 2, 4])
  +    }
  +
  +    @Test func matchTieBreakLargestPriorWins() throws {
  +        // The load-bearing tie-break: TS uses `<=` (largest prior frame index
  +        // wins on ties). Under `<` this fixture would yield [0,1,3]; the `<=`
  +        // oracle yields [1,2,3]. This test FAILS if the comparison is "cleaned up".
  +        // TS oracle: match([[0],[0],[10]], [[0],[0],[0],[10],[10]]) -> [1,2,3]
  +        let out = try StillsMatch.matchStillsToFrames(
  +            [[0], [0], [10]],
  +            [[0], [0], [0], [10], [10]]
  +        )
  +        #expect(out == [1, 2, 3])
  +    }
  +
  +    @Test func matchStrictMonotonicity() throws {
  +        // Any valid M >= N assignment must be strictly increasing.
  +        let out = try StillsMatch.matchStillsToFrames(
  +            [[0], [10], [20]],
  +            [[0], [5], [10], [15], [20]]
  +        )
  +        for i in 1..<out.count {
  +            #expect(out[i] > out[i - 1])
  +        }
  +    }
  +
  +    @Test func matchEmptyStills() throws {
  +        // N == 0 -> []
  +        let out = try StillsMatch.matchStillsToFrames([], [[0], [1]])
  +        #expect(out == [])
  +    }
  +
  +    @Test func matchSingleStillPicksGloballyCheapestFrame() throws {
  +        // TS oracle: match([[7]], [[0],[5],[8],[20]]) -> [2] (|7-8|=1 is the min)
  +        let out = try StillsMatch.matchStillsToFrames([[7]], [[0], [5], [8], [20]])
  +        #expect(out == [2])
  +    }
  +
  +    @Test func matchEqualCounts() throws {
  +        // TS oracle: match([[0],[10]], [[1],[11]]) -> [0,1]
  +        let out = try StillsMatch.matchStillsToFrames([[0], [10]], [[1], [11]])
  +        #expect(out == [0, 1])
  +    }
  +
  +    @Test func matchAllEqualCostTie() throws {
  +        // TS oracle: match([[0],[0]], [[0],[0],[0]]) -> [0,1]
  +        let out = try StillsMatch.matchStillsToFrames([[0], [0]], [[0], [0], [0]])
  +        #expect(out == [0, 1])
  +    }
  +
  +    @Test func matchTooFewFramesThrows() {
  +        // M < N: TS returns garbage ([null,null,-1]). The Swift port rejects
  +        // deterministically (documented behavior, test-locked).
  +        #expect(throws: StillsMatchError.tooFewFrames(stills: 3, frames: 2)) {
  +            try StillsMatch.matchStillsToFrames([[0], [10], [20]], [[0], [20]])
  +        }
  +    }
  +
  +    // MARK: naturalSort — A10 parity vs TS
  +
  +    @Test func naturalSortSmall() {
  +        // TS oracle: naturalSort(["x-010.jpeg","x-002.jpeg","x-001.jpeg"])
  +        //   -> ["x-001.jpeg","x-002.jpeg","x-010.jpeg"]
  +        let out = StillsMatch.naturalSort(["x-010.jpeg", "x-002.jpeg", "x-001.jpeg"])
  +        #expect(out == ["x-001.jpeg", "x-002.jpeg", "x-010.jpeg"])
  +    }
  +
  +    @Test func naturalSortMatchesTSOnShuffledSet() {
  +        // Shuffled subset of slide-001..slide-039; TS naturalSort yields
  +        // ascending numeric order. Oracle captured via node.
  +        let input = [
  +            "slide-011.jpeg", "slide-002.jpeg", "slide-001.jpeg",
  ... (16 lines truncated)
  +116 -0
[full diff: rtk git diff --no-compact]
