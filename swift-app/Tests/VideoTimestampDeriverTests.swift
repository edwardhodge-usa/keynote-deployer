import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 6 — VideoTimestampDeriver. Fully offline: a fake VideoEncoder returns
/// canned 1-value grids (same shape StillsMatch's own tests use) so expected
/// matched frame indices are known.
@Suite("Section 6 — VideoTimestampDeriver")
struct VideoTimestampDeriverTests {

    /// Fake encoder: video URL → canned frame grids; any other URL → that still's
    /// single grid (keyed by path). encodeWithKeyframes is never called by derive.
    struct FakeEncoder: VideoEncoder {
        let videoURL: URL
        let frameGrids: [[Double]]
        let stillGridByPath: [String: [Double]]
        let dims: (width: Int, height: Int, fps: Double)

        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) { dims }
        func sampleGrids(url: URL) async throws -> [[Double]] {
            if url == videoURL { return frameGrids }
            return [stillGridByPath[url.path] ?? []]
        }
        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws {
            fatalError("encodeWithKeyframes is not used by derive()")
        }
    }

    /// Thread-safe progress collector (onProgress is @Sendable, may be called off
    /// the test's executor).
    final class ProgressSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Double] = []
        func record(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private static func stillURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/kd-sec6/\(name)")
    }
    private static let video = URL(fileURLWithPath: "/tmp/kd-sec6/deck.mp4")

    @Test("derive returns slideCount, monotonic frames, and 3dp timestamps")
    func derive_basic() async throws {
        // 10 frames: grids [0],[1],...,[9]. Stills key to frames 0, 3, 7.
        let frameGrids = (0..<10).map { [Double($0)] }
        let stills = ["s1.jpeg", "s2.jpeg", "s3.jpeg"].map(Self.stillURL)
        let gridByPath = [
            stills[0].path: [0.0],
            stills[1].path: [3.0],
            stills[2].path: [7.0],
        ]
        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
                              stillGridByPath: gridByPath, dims: (1920, 1080, 30))

        let result = try await VideoTimestampDeriver.derive(
            encoder: enc, videoURL: Self.video, stillURLs: stills, fps: 30)

        #expect(result.slideCount == 3)
        #expect(result.frames == [0, 3, 7])
        #expect(zip(result.frames, result.frames.dropFirst()).allSatisfy { $0 < $1 })  // strictly monotonic
        #expect(result.timestamps == result.frames.map { round((Double($0) / 30.0) * 1000) / 1000 })
        #expect(result.timestamps == [0.0, 0.1, 0.233])
        #expect(result.width == 1920)
        #expect(result.height == 1080)
        #expect(result.fps == 30)
    }

    @Test("A5: progress handler fires during sampling and finishes ~1.0")
    func derive_reportsProgress() async throws {
        let frameGrids = (0..<6).map { [Double($0)] }
        let stills = ["a.jpeg", "b.jpeg"].map(Self.stillURL)
        let gridByPath = [stills[0].path: [0.0], stills[1].path: [4.0]]
        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
                              stillGridByPath: gridByPath, dims: (1280, 720, 24))
        let sink = ProgressSink()

        _ = try await VideoTimestampDeriver.derive(
            encoder: enc, videoURL: Self.video, stillURLs: stills, fps: 24,
            onProgress: { sink.record($0) })

        let v = sink.values
        #expect(v.count >= 1)
        #expect(abs((v.last ?? 0) - 1.0) < 0.0001)
        #expect(v.allSatisfy { $0 >= 0 && $0 <= 1.0001 })
    }

    @Test("stills are natural-sorted before matching")
    func derive_naturalSortsStills() async throws {
        let frameGrids = (0..<10).map { [Double($0)] }
        // Slides keyed to increasing frames; supplied OUT OF natural order.
        let s010 = Self.stillURL("slide-010.jpeg")
        let s001 = Self.stillURL("slide-001.jpeg")
        let s002 = Self.stillURL("slide-002.jpeg")
        let gridByPath = [
            s001.path: [0.0],
            s002.path: [4.0],
            s010.path: [9.0],
        ]
        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
                              stillGridByPath: gridByPath, dims: (1920, 1080, 30))

        // Input order is 010, 001, 002 — only natural-sorting yields increasing frames.
        let result = try await VideoTimestampDeriver.derive(
            encoder: enc, videoURL: Self.video, stillURLs: [s010, s001, s002], fps: 30)

        #expect(result.frames == [0, 4, 9])
        #expect(zip(result.frames, result.frames.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("empty stills → empty analysis")
    func derive_emptyStills() async throws {
        let enc = FakeEncoder(videoURL: Self.video, frameGrids: [[0.0], [1.0]],
                              stillGridByPath: [:], dims: (1920, 1080, 30))
        let result = try await VideoTimestampDeriver.derive(
            encoder: enc, videoURL: Self.video, stillURLs: [], fps: 30)
        #expect(result.slideCount == 0)
        #expect(result.frames == [])
        #expect(result.timestamps == [])
    }
}
