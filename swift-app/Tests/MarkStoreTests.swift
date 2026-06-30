import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 02 — MarkStore algorithm versioning. Uses unique synthetic fingerprints
/// (nonexistent paths → deterministic size 0, UUID-distinct frameCount) so the tests
/// never collide with real app data or each other in the shared timeline-marks.json.
@Suite("Section 02 — MarkStore versioning")
struct MarkStoreTests {

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
}
