import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 02 — MarkStore algorithm versioning. Each test runs against a fresh temp
/// store dir (via `MarkStore.storeDirectoryOverride`) so it never touches real app
/// data or races another test on the shared timeline-marks.json. `.serialized` keeps
/// the process-global override race-free across the suite.
@Suite("Section 02 — MarkStore versioning", .serialized)
struct MarkStoreTests {

    /// Fresh instance per test → point the store at a unique temp dir before each.
    init() {
        MarkStore.storeDirectoryOverride = FileManager.default.temporaryDirectory
            .appendingPathComponent("markstore-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func uniqueFrameCount() -> Int { abs(UUID().uuidString.hashValue % 1_000_000) + 1 }
    private static let marks = [SlideMark(holdStart: 0, holdEnd: 5), SlideMark(holdStart: 10, holdEnd: 15)]

    @Test("different algorithm versions produce different fingerprints")
    func differentVersionsDifferentKeys() {
        let path = "/nonexistent-\(UUID().uuidString)"
        let fc = Self.uniqueFrameCount()
        let v1 = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 1)
        let v2 = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 2)
        #expect(v1 != v2)
        // Same args + same version → identical key (stable).
        let v2b = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 2)
        #expect(v2 == v2b)
    }

    @Test("a version bump re-seeds but preserves old edits on disk")
    func versionBumpReseedsPreservesOld() {
        let path = "/nonexistent-\(UUID().uuidString)"
        let fc = Self.uniqueFrameCount()
        let v1 = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 1)
        let v2 = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 2)
        MarkStore.save(Self.marks, for: v1)            // hand-tuned under the OLD algorithm
        #expect(MarkStore.load(v2) == nil)             // new algorithm → fresh seed (no match)
        #expect(MarkStore.load(v1) == Self.marks)      // old edits still on disk under their key
    }

    @Test("same-version round-trip returns the saved marks")
    func sameVersionRoundTrip() {
        let path = "/nonexistent-\(UUID().uuidString)"
        let fc = Self.uniqueFrameCount()
        let v2 = MarkStore.fingerprint(path: path, frameCount: fc, fps: 30, algorithmVersion: 2)
        MarkStore.save(Self.marks, for: v2)
        #expect(MarkStore.load(v2) == Self.marks)      // hand-edits persist within a version
    }

    @Test("deckIdentity strips only explicit -v# version tokens (years kept)")
    func deckIdentityStripsVersion() {
        #expect(MarkStore.deckIdentity("ilsquals-2026-v3") == "ilsquals-2026")
        #expect(MarkStore.deckIdentity("ilsquals-2026-v16") == "ilsquals-2026")
        #expect(MarkStore.deckIdentity("nash-quals-2026") == "nash-quals-2026")  // no -v → unchanged
        #expect(MarkStore.deckIdentity("deck") == "deck")
    }

    @Test("remap converts marks by TIME across fps/length and stays valid")
    func remapByTime() {
        // Saved at fps 10: frames [0,10] and [20,30] → seconds [0,1] and [2,3].
        let named = MarkStore.NamedMarks(marks: [SlideMark(holdStart: 0, holdEnd: 10),
                                                 SlideMark(holdStart: 20, holdEnd: 30)],
                                         fps: 10, frameCount: 40, savedAt: 0)
        // Re-map to fps 20, longer deck → seconds preserved: [0,20] and [40,60].
        let out = MarkStore.remap(named, toFps: 20, toFrameCount: 200)
        #expect(out.count == 2)
        #expect(out[0].holdStart == 0 && out[0].holdEnd == 20)
        #expect(out[1].holdStart == 40 && out[1].holdEnd == 60)
        // Clamped onto a SHORT deck → still strictly-increasing + in range (valid).
        let short = MarkStore.remap(named, toFps: 20, toFrameCount: 8)
        #expect(short.allSatisfy { $0.holdStart >= 0 && $0.holdEnd < 8 && $0.holdStart <= $0.holdEnd })
        for i in 1..<short.count { #expect(short[i - 1].holdEnd < short[i].holdStart) }
    }
}
