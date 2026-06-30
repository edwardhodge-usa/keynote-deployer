import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 01 — SeedHarness + HarnessReport. Fully offline: a stub encoder returns
/// canned grids so the real StillsMatch + HoldDetector run deterministically. The
/// harness only OBSERVES the pipeline (it bypasses MarkStore → reports the fresh seed).
@Suite("Section 01 — SeedHarness", .serialized)
struct SeedHarnessTests {

    /// Stub encoder: video URL → canned frameGrids; each still URL → one grid by path.
    final class StubEncoder: VideoEncoder, @unchecked Sendable {
        let videoURL: URL
        let frameGrids: [[Double]]
        let stillGridByPath: [String: [Double]]
        init(videoURL: URL, frameGrids: [[Double]], stillGridByPath: [String: [Double]]) {
            self.videoURL = videoURL; self.frameGrids = frameGrids; self.stillGridByPath = stillGridByPath
        }
        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) { (32, 18, 30) }
        func sampleGrids(url: URL) async throws -> [[Double]] {
            url == videoURL ? frameGrids : [stillGridByPath[url.path] ?? []]
        }
        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws {}
    }

    private static func tmpDir() -> URL {
        let d = FileManager.default.temporaryDirectory
            .appendingPathComponent("kd-harness-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A full-size 1728-value grid filled with one value — matches real frame grids,
    /// so thumbnail PNG rendering works (pngData requires GridSampler.valueCount).
    private static func solid(_ v: Double) -> [Double] {
        [Double](repeating: v, count: GridSampler.valueCount)
    }

    /// A well-separated 6-frame synthetic deck: still A on the dark frames, still B on
    /// the bright frames → StillsMatch picks two distinct, well-separated anchors.
    private static func cleanDeck(out: URL) -> (SeedHarnessInput, StubEncoder) {
        let video = URL(fileURLWithPath: "/tmp/kd-h/deck.mov")
        let a = URL(fileURLWithPath: "/tmp/kd-h/slide-1.png")
        let b = URL(fileURLWithPath: "/tmp/kd-h/slide-2.png")
        let frames: [[Double]] = [solid(0), solid(0), solid(0), solid(255), solid(255), solid(255)]
        let enc = StubEncoder(videoURL: video, frameGrids: frames,
                              stillGridByPath: [a.path: solid(0), b.path: solid(255)])
        return (SeedHarnessInput(videoURL: video, stillURLs: [a, b], outputDir: out), enc)
    }

    @Test("one diagnostic per still")
    func oneDiagnosticPerStill() async throws {
        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
        let (input, enc) = Self.cleanDeck(out: out)
        let report = try await SeedHarness.run(input, encoder: enc)
        #expect(report.perSlide.count == input.stillURLs.count)
        #expect(report.slideCount == 2)
    }

    @Test("clean deck: markCount == slideCount")
    func cleanDeckCountMatches() async throws {
        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
        let (input, enc) = Self.cleanDeck(out: out)
        let report = try await SeedHarness.run(input, encoder: enc)
        #expect(report.markCount == report.slideCount)
        // StillsMatch forces strictly-increasing anchors, so same-frame collision is
        // unreachable from the real pipeline → the flag is false on a normal deck.
        #expect(report.perSlide.allSatisfy { !$0.anchorCollidedWithPrevious })
    }

    @Test("report exposes both counts so divergence is visible")
    func reportExposesBothCounts() async throws {
        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
        let (input, enc) = Self.cleanDeck(out: out)
        let report = try await SeedHarness.run(input, encoder: enc)
        // The harness's job is to MEASURE: both the count authority (slides) and the
        // produced marks are reported, so any future divergence is plainly visible.
        #expect(report.slideCount == 2)
        #expect(report.markCount >= 1)
    }

    @Test("writeJSON emits valid JSON with one entry per slide")
    func jsonEmit() async throws {
        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
        let (input, enc) = Self.cleanDeck(out: out)
        let report = try await SeedHarness.run(input, encoder: enc)
        try report.writeJSON(to: out)
        let url = out.appendingPathComponent("\(HarnessReport.safeSlug(report.deckName))-seed.json")
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["slideCount"] as? Int == 2)
        let per = obj?["perSlide"] as? [[String: Any]]
        #expect(per?.count == 2)
    }

    @Test("writeVisualReport emits a self-contained HTML referencing each slide")
    func htmlEmit() async throws {
        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
        let (input, enc) = Self.cleanDeck(out: out)
        let report = try await SeedHarness.run(input, encoder: enc)
        try report.writeVisualReport(to: out)
        let url = out.appendingPathComponent("\(HarnessReport.safeSlug(report.deckName))-seed.html")
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(!html.isEmpty)
        // Self-contained: inline base64 thumbnails, no external asset refs.
        #expect(html.contains("data:image/png;base64,"))
        // One block per slide.
        let blocks = html.components(separatedBy: "class=\"slide\"").count - 1
        #expect(blocks == 2)
    }

    @Test("path-traversal: a deckName with ../ cannot escape the output dir")
    func pathTraversalGuard() throws {
        // Slug strips separators and dots.
        #expect(!HarnessReport.safeSlug("../../etc/passwd").contains("/"))
        #expect(!HarnessReport.safeSlug("../../etc/passwd").contains(".."))
        // safeOutputURL throws when a crafted name would escape the dir.
        let dir = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: HarnessError.self) {
            _ = try HarnessReport.safeOutputURL(dir: dir, name: "../escape.json")
        }
        // A safe name resolves INSIDE the dir.
        let ok = try HarnessReport.safeOutputURL(dir: dir, name: "deck-seed.json")
        #expect(ok.path.hasPrefix(dir.standardizedFileURL.path))
    }
}
