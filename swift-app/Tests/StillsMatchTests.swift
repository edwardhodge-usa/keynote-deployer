import Testing
@testable import KeynoteDeployer

/// Parity gate for the DP matcher. Every expected array below was captured by
/// running the SAME input through the TypeScript `matchStillsToFrames`
/// (`src/utils/stillsMatch.ts`) via `node`, then hard-coded here as the oracle.
@Suite("Section 2 — StillsMatch parity")
struct StillsMatchTests {

    // MARK: meanAbs

    @Test func meanAbsKnownValue() {
        // |1-4| + |2-2| + |3-0| = 3 + 0 + 3 = 6; 6 / 3 = 2
        #expect(StillsMatch.meanAbs([1, 2, 3], [4, 2, 0]) == 2)
    }

    @Test func meanAbsEmptyIsZero() {
        #expect(StillsMatch.meanAbs([], []) == 0)
    }

    // MARK: matchStillsToFrames — parity vs TS oracle

    @Test func matchCleanMonotonic() throws {
        // TS oracle: match([[0],[10],[20]], [[0],[5],[10],[15],[20]]) -> [0,2,4]
        let out = try StillsMatch.matchStillsToFrames(
            [[0], [10], [20]],
            [[0], [5], [10], [15], [20]]
        )
        #expect(out == [0, 2, 4])
    }

    @Test func matchTieBreakLargestPriorWins() throws {
        // The load-bearing tie-break: TS uses `<=` (largest prior frame index
        // wins on ties). Under `<` this fixture would yield [0,1,3]; the `<=`
        // oracle yields [1,2,3]. This test FAILS if the comparison is "cleaned up".
        // TS oracle: match([[0],[0],[10]], [[0],[0],[0],[10],[10]]) -> [1,2,3]
        let out = try StillsMatch.matchStillsToFrames(
            [[0], [0], [10]],
            [[0], [0], [0], [10], [10]]
        )
        #expect(out == [1, 2, 3])
    }

    @Test func matchStrictMonotonicity() throws {
        // Any valid M >= N assignment must be strictly increasing.
        let out = try StillsMatch.matchStillsToFrames(
            [[0], [10], [20]],
            [[0], [5], [10], [15], [20]]
        )
        for i in 1..<out.count {
            #expect(out[i] > out[i - 1])
        }
    }

    @Test func matchEmptyStills() throws {
        // N == 0 -> []
        let out = try StillsMatch.matchStillsToFrames([], [[0], [1]])
        #expect(out == [])
    }

    @Test func matchSingleStillPicksGloballyCheapestFrame() throws {
        // TS oracle: match([[7]], [[0],[5],[8],[20]]) -> [2] (|7-8|=1 is the min)
        let out = try StillsMatch.matchStillsToFrames([[7]], [[0], [5], [8], [20]])
        #expect(out == [2])
    }

    @Test func matchEqualCounts() throws {
        // TS oracle: match([[0],[10]], [[1],[11]]) -> [0,1]
        let out = try StillsMatch.matchStillsToFrames([[0], [10]], [[1], [11]])
        #expect(out == [0, 1])
    }

    @Test func matchAllEqualCostTie() throws {
        // TS oracle: match([[0],[0]], [[0],[0],[0]]) -> [0,1]
        let out = try StillsMatch.matchStillsToFrames([[0], [0]], [[0], [0], [0]])
        #expect(out == [0, 1])
    }

    @Test func matchTooFewFramesThrows() {
        // M < N: TS returns garbage ([null,null,-1]). The Swift port rejects
        // deterministically (documented behavior, test-locked).
        #expect(throws: StillsMatchError.tooFewFrames(stills: 3, frames: 2)) {
            try StillsMatch.matchStillsToFrames([[0], [10], [20]], [[0], [20]])
        }
    }

    // MARK: naturalSort — A10 parity vs TS

    @Test func naturalSortSmall() {
        // TS oracle: naturalSort(["x-010.jpeg","x-002.jpeg","x-001.jpeg"])
        //   -> ["x-001.jpeg","x-002.jpeg","x-010.jpeg"]
        let out = StillsMatch.naturalSort(["x-010.jpeg", "x-002.jpeg", "x-001.jpeg"])
        #expect(out == ["x-001.jpeg", "x-002.jpeg", "x-010.jpeg"])
    }

    @Test func naturalSortMatchesTSOnShuffledSet() {
        // Shuffled subset of slide-001..slide-039; TS naturalSort yields
        // ascending numeric order. Oracle captured via node.
        let input = [
            "slide-011.jpeg", "slide-002.jpeg", "slide-001.jpeg",
            "slide-039.jpeg", "slide-010.jpeg", "slide-021.jpeg", "slide-003.jpeg"
        ]
        let expected = [
            "slide-001.jpeg", "slide-002.jpeg", "slide-003.jpeg",
            "slide-010.jpeg", "slide-011.jpeg", "slide-021.jpeg", "slide-039.jpeg"
        ]
        #expect(StillsMatch.naturalSort(input) == expected)
    }

    @Test func naturalSortFull39AscendingNumeric() {
        // Build 001..039, reverse it, assert naturalSort restores ascending.
        let ascending = (1...39).map { "slide-\(String(format: "%03d", $0)).jpeg" }
        let shuffled = Array(ascending.reversed())
        #expect(StillsMatch.naturalSort(shuffled) == ascending)
    }
}
