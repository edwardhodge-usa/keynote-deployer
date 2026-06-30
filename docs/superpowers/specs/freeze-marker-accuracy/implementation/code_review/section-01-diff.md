diff --git a/swift-app/HarnessCLI/main.swift b/swift-app/HarnessCLI/main.swift
new file mode 100644
index 0000000..0df9b1d
--- /dev/null
+++ b/swift-app/HarnessCLI/main.swift
@@ -0,0 +1,46 @@
+import Foundation
+
+// Thin CLI wrapper around SeedHarness with the live AVFoundation encoder, so the
+// harness can run on a real deck folder from the terminal:
+//   kd-seed-harness <deck-video> <stills-dir> <output-dir>
+// The stills dir is scanned for image files (jpg/jpeg/png), natural-sorted by the
+// harness. Writes <slug>-seed.json + <slug>-seed.html (+ thumbnails) to output-dir.
+
+func fail(_ msg: String) -> Never {
+    FileHandle.standardError.write(Data((msg + "\n").utf8))
+    exit(1)
+}
+
+let args = CommandLine.arguments
+guard args.count == 4 else {
+    fail("usage: kd-seed-harness <deck-video> <stills-dir> <output-dir>")
+}
+
+let videoURL = URL(fileURLWithPath: args[1])
+let stillsDir = URL(fileURLWithPath: args[2])
+let outputDir = URL(fileURLWithPath: args[3])
+
+let imageExts: Set<String> = ["jpg", "jpeg", "png"]
+let stillURLs: [URL]
+do {
+    stillURLs = try FileManager.default
+        .contentsOfDirectory(at: stillsDir, includingPropertiesForKeys: nil)
+        .filter { imageExts.contains($0.pathExtension.lowercased()) }
+} catch {
+    fail("could not read stills dir: \(error.localizedDescription)")
+}
+guard !stillURLs.isEmpty else { fail("no image stills found in \(stillsDir.path)") }
+
+let input = SeedHarnessInput(videoURL: videoURL, stillURLs: stillURLs, outputDir: outputDir)
+let encoder = AVFoundationVideoEncoder()
+
+do {
+    let report = try await SeedHarness.run(input, encoder: encoder)
+    try report.writeJSON(to: outputDir)
+    try report.writeVisualReport(to: outputDir)
+    let flag = report.markCount == report.slideCount ? "OK" : "MISMATCH"
+    print("seed report → \(outputDir.path)")
+    print("slides \(report.slideCount) · marks \(report.markCount) · count \(flag)")
+} catch {
+    fail("harness failed: \(error.localizedDescription)")
+}
diff --git a/swift-app/Sources/Diagnostics/HarnessReport.swift b/swift-app/Sources/Diagnostics/HarnessReport.swift
new file mode 100644
index 0000000..eaac2b8
--- /dev/null
+++ b/swift-app/Sources/Diagnostics/HarnessReport.swift
@@ -0,0 +1,209 @@
+import Foundation
+import CoreGraphics
+import ImageIO
+import UniformTypeIdentifiers
+
+/// One slide's seed diagnostic — the per-slide row the harness report surfaces so a
+/// human can eyeball "Rest settled? Go bracketing the transition?" and triage WHERE
+/// accuracy is lost (DP match vs Rest choice vs Go threshold vs count).
+struct PerSlideDiagnostic: Codable, Sendable, Equatable {
+    let slideIndex: Int
+    /// The DP-matched frame index for this slide (the anchor).
+    let matchedAnchorFrame: Int
+    /// Two stills matched to the SAME frame → the count-loss signal.
+    let anchorCollidedWithPrevious: Bool
+    /// Anchor far from any detected hold → StillsMatch (not the detector) is the suspect.
+    let lowConfidenceMatch: Bool
+    /// Produced Rest (holdStart) frame index.
+    let seededRest: Int
+    /// Produced Go (holdEnd) frame index.
+    let seededGo: Int
+    /// Consecutive grid diff for a ±window of frames around the anchor — eyeball the Go/Rest fit.
+    let diffProfileAroundAnchor: [Double]
+    /// On-disk path of the rendered Rest thumbnail (for the JSON dump).
+    let restFrameThumbnailPath: String
+    /// On-disk path of the rendered Go thumbnail.
+    let goFrameThumbnailPath: String
+}
+
+/// Diagnostic report for one deck's seed run. Emits a machine-readable JSON dump and
+/// a self-contained dark HTML montage (Rest/Go thumbnails + ASCII diff-profile bars).
+/// The visual report is the artifact a human eyeballs; the JSON backs it.
+struct HarnessReport: Sendable {
+    let deckName: String
+    /// Slide count == stillURLs.count — the COUNT authority.
+    let slideCount: Int
+    /// Produced marks.count — SHOULD equal slideCount.
+    let markCount: Int
+    let perSlide: [PerSlideDiagnostic]
+    /// Rest/Go thumbnail grids (32×18×3 raw RGB), parallel to `perSlide`, kept in
+    /// memory so the HTML montage can inline them as base64 without re-reading disk.
+    let restGrids: [[Double]]
+    let goGrids: [[Double]]
+
+    // MARK: Path safety
+
+    /// Reduce an arbitrary deck name to a filesystem-safe slug: strip path
+    /// separators and `..`, allow only [A-Za-z0-9-_], collapse empties to "deck".
+    /// Prevents a `deckName` like `../../etc` escaping the output directory.
+    static func safeSlug(_ raw: String) -> String {
+        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
+        let mapped = raw.map { allowed.contains($0) ? $0 : "-" }
+        let slug = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
+        return slug.isEmpty ? "deck" : slug
+    }
+
+    /// Build an output URL under `dir` for `name`, verifying the resolved path stays
+    /// inside `dir` (defense in depth on top of slug sanitizing). Throws on escape.
+    static func safeOutputURL(dir: URL, name: String) throws -> URL {
+        let base = dir.standardizedFileURL
+        let url = base.appendingPathComponent(name).standardizedFileURL
+        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else {
+            throw HarnessError.pathEscapesOutputDir(attempted: url.path, root: base.path)
+        }
+        return url
+    }
+
+    // MARK: JSON
+
+    /// Write the per-slide diagnostics as pretty JSON to `<slug>-seed.json` under `dir`.
+    func writeJSON(to dir: URL) throws {
+        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
+        let slug = Self.safeSlug(deckName)
+        let url = try Self.safeOutputURL(dir: dir, name: "\(slug)-seed.json")
+        let payload = JSONPayload(deckName: deckName, slideCount: slideCount,
+                                  markCount: markCount, perSlide: perSlide)
+        let enc = JSONEncoder()
+        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
+        try enc.encode(payload).write(to: url)
+    }
+
+    private struct JSONPayload: Codable {
+        let deckName: String
+        let slideCount: Int
+        let markCount: Int
+        let perSlide: [PerSlideDiagnostic]
+    }
+
+    // MARK: Visual report
+
+    /// Write a single self-contained dark HTML montage to `<slug>-seed.html` under `dir`.
+    /// Thumbnails are inlined as base64 `data:` URIs so the file needs no external assets.
+    func writeVisualReport(to dir: URL) throws {
+        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
+        let slug = Self.safeSlug(deckName)
+        let url = try Self.safeOutputURL(dir: dir, name: "\(slug)-seed.html")
+        try html().data(using: .utf8)!.write(to: url)
+    }
+
+    private func html() -> String {
+        let countFlag = markCount == slideCount
+            ? "<span class='ok'>count OK</span>"
+            : "<span class='bad'>COUNT MISMATCH \(markCount) ≠ \(slideCount)</span>"
+        var blocks = ""
+        for (i, d) in perSlide.enumerated() {
+            let restURI = Self.dataURI(restGrids[safe: i] ?? [])
+            let goURI = Self.dataURI(goGrids[safe: i] ?? [])
+            let flags = [
+                d.anchorCollidedWithPrevious ? "<span class='bad'>collision</span>" : "",
+                d.lowConfidenceMatch ? "<span class='warn'>low-confidence anchor</span>" : ""
+            ].filter { !$0.isEmpty }.joined(separator: " ")
+            blocks += """
+            <div class="slide">
+              <div class="hd">slide \(d.slideIndex) \(flags)</div>
+              <div class="thumbs">
+                <figure><img src="\(restURI)"><figcaption>Rest \(d.seededRest)</figcaption></figure>
+                <figure><img src="\(goURI)"><figcaption>Go \(d.seededGo)</figcaption></figure>
+              </div>
+              <div class="meta">anchor \(d.matchedAnchorFrame)</div>
+              <pre class="profile">\(Self.asciiBars(d.diffProfileAroundAnchor))</pre>
+            </div>
+            """
+        }
+        return """
+        <!DOCTYPE html><html><head><meta charset="utf-8">
+        <title>\(htmlEscape(deckName)) — seed report</title>
+        <style>
+          body{background:#0b0b0d;color:#e6e6ea;font:13px -apple-system,system-ui,sans-serif;margin:24px}
+          h1{font-size:18px;font-weight:600}
+          .ok{color:#34c759} .bad{color:#ff453a;font-weight:600} .warn{color:#ff9f0a}
+          .slide{border:1px solid #2a2a31;border-radius:10px;padding:12px;margin:10px 0;background:#141418}
+          .hd{font-weight:600;margin-bottom:6px}
+          .thumbs{display:flex;gap:14px}
+          figure{margin:0} img{width:160px;height:90px;image-rendering:pixelated;border:1px solid #2a2a31;border-radius:4px}
+          figcaption{color:#9a9aa2;font-size:11px;margin-top:3px}
+          .meta{color:#9a9aa2;font-size:11px;margin-top:6px}
+          .profile{color:#5e9cff;font:11px ui-monospace,monospace;margin:6px 0 0;white-space:pre}
+        </style></head><body>
+        <h1>\(htmlEscape(deckName)) — seed report &nbsp; slides \(slideCount) · marks \(markCount) &nbsp; \(countFlag)</h1>
+        \(blocks)
+        </body></html>
+        """
+    }
+
+    // MARK: Rendering helpers
+
+    /// ASCII-bar rendering of a diff profile (matches the house live-dashboard style;
+    /// unicode dies under nohup's C locale, so ASCII only).
+    static func asciiBars(_ values: [Double]) -> String {
+        guard let maxV = values.max(), maxV > 0 else {
+            return values.map { _ in "|" }.joined(separator: " ")
+        }
+        return values.map { v in
+            let n = Int((v / maxV) * 20)
+            return String(repeating: "#", count: max(0, n)).padding(toLength: 20, withPad: ".", startingAt: 0)
+        }.joined(separator: "\n")
+    }
+
+    /// Encode a 32×18×3 raw-RGB grid as a base64 PNG `data:` URI for inline HTML.
+    static func dataURI(_ grid: [Double]) -> String {
+        guard let png = pngData(from: grid) else { return "" }
+        return "data:image/png;base64,\(png.base64EncodedString())"
+    }
+
+    /// Build a small PNG from a 32×18×3 raw-RGB grid (honestly shows what the
+    /// detector "sees"; native-res extraction is deliberately out of scope here).
+    static func pngData(from grid: [Double]) -> Data? {
+        let w = GridSampler.width, h = GridSampler.height
+        guard grid.count == w * h * GridSampler.channels else { return nil }
+        var rgba = [UInt8](repeating: 255, count: w * h * 4)
+        for cell in 0..<(w * h) {
+            let s = cell * 3, d = cell * 4
+            rgba[d] = UInt8(max(0, min(255, grid[s])))
+            rgba[d + 1] = UInt8(max(0, min(255, grid[s + 1])))
+            rgba[d + 2] = UInt8(max(0, min(255, grid[s + 2])))
+            rgba[d + 3] = 255
+        }
+        let space = CGColorSpace(name: CGColorSpace.sRGB)!
+        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8,
+                                  bytesPerRow: w * 4, space: space,
+                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
+              let img = ctx.makeImage() else { return nil }
+        let data = NSMutableData()
+        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
+        else { return nil }
+        CGImageDestinationAddImage(dest, img, nil)
+        guard CGImageDestinationFinalize(dest) else { return nil }
+        return data as Data
+    }
+
+    private func htmlEscape(_ s: String) -> String {
+        s.replacingOccurrences(of: "&", with: "&amp;")
+            .replacingOccurrences(of: "<", with: "&lt;")
+            .replacingOccurrences(of: ">", with: "&gt;")
+    }
+}
+
+enum HarnessError: Error, LocalizedError, Equatable {
+    case pathEscapesOutputDir(attempted: String, root: String)
+    var errorDescription: String? {
+        switch self {
+        case let .pathEscapesOutputDir(attempted, root):
+            return "Refused to write outside the output directory (\(attempted) escapes \(root))."
+        }
+    }
+}
+
+private extension Array {
+    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
+}
diff --git a/swift-app/Sources/Diagnostics/SeedHarness.swift b/swift-app/Sources/Diagnostics/SeedHarness.swift
new file mode 100644
index 0000000..e247d94
--- /dev/null
+++ b/swift-app/Sources/Diagnostics/SeedHarness.swift
@@ -0,0 +1,157 @@
+import Foundation
+
+/// Input for one diagnostic run: a deck video + its per-slide stills + where to write.
+struct SeedHarnessInput: Sendable {
+    let videoURL: URL
+    let stillURLs: [URL]
+    let outputDir: URL
+}
+
+/// Headless seed-measurement harness. Runs the REAL seed pipeline
+/// (`GridSampler` → `StillsMatch` → `HoldDetector`) on a deck and produces a
+/// per-slide diagnostic report. It deliberately BYPASSES `MarkStore` so it always
+/// reports the FRESH seed — that is how MarkStore shadowing is detected in triage.
+///
+/// Pure orchestration over an injected `VideoEncoder` (tests inject a stub). It only
+/// OBSERVES the pipeline — it does not change detection behavior. Off-main, cancellable.
+enum SeedHarness {
+
+    /// Number of frames on each side of an anchor to include in the diff profile.
+    static let profileWindow = 10
+
+    static func run(_ input: SeedHarnessInput, encoder: VideoEncoder) async throws -> HarnessReport {
+        // 1. Natural-sort stills exactly as the real deriver does (numeric-aware).
+        let stills = input.stillURLs.sorted {
+            $0.path.compare($1.path, options: .numeric) == .orderedAscending
+        }
+
+        // 2. Sample the video frames, then each still (one grid per still).
+        try Task.checkCancellation()
+        let frameGrids = try await encoder.sampleGrids(url: input.videoURL)
+        let bound = frameGrids.count
+
+        var stillGrids: [[Double]] = []
+        stillGrids.reserveCapacity(stills.count)
+        for url in stills {
+            try Task.checkCancellation()
+            let grids = try await encoder.sampleGrids(url: url)
+            guard let first = grids.first else {
+                throw VideoEncoderError.readerFailed("still produced no grid: \(url.lastPathComponent)")
+            }
+            stillGrids.append(first)
+        }
+
+        // 3. DP-match stills → frames, then the CURRENT detector → marks (the seed
+        //    we are diagnosing). Derive collisions from the RAW anchors, since the
+        //    detector may dedup colliding anchors (the count bug we are measuring).
+        try Task.checkCancellation()
+        let anchors = try StillsMatch.matchStillsToFrames(stillGrids, frameGrids)
+        let marks = HoldDetector.detect(frameGrids: frameGrids, anchors: anchors, frameCount: bound)
+
+        // Map a (clamped) anchor frame → its produced mark. The current detector
+        // emits one mark per DISTINCT anchor with holdStart == the clamped anchor,
+        // so key marks by holdStart and fall back to the nearest.
+        var markByStart: [Int: SlideMark] = [:]
+        for m in marks { markByStart[m.holdStart] = m }
+
+        let prof = diffProfile(frameGrids)   // consecutive-frame diff, length bound-1
+
+        var perSlide: [PerSlideDiagnostic] = []
+        var restGrids: [[Double]] = []
+        var goGrids: [[Double]] = []
+        let thumbsDir = try HarnessReport.safeOutputURL(
+            dir: input.outputDir, name: "\(HarnessReport.safeSlug(deckName(input)))-thumbs")
+        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
+
+        for (i, anchor) in anchors.enumerated() {
+            try Task.checkCancellation()
+            let clamped = max(0, min(anchor, max(0, bound - 1)))
+            let mark = markByStart[clamped] ?? nearestMark(marks, to: clamped)
+                ?? SlideMark(holdStart: clamped, holdEnd: clamped)
+
+            let collided = i > 0 && anchors[i] == anchors[i - 1]
+            let profile = profileAround(clamped, prof: prof)
+            let lowConfidence = isLowConfidence(at: clamped, prof: prof)
+
+            let restGrid = frameGrids[safe: mark.holdStart] ?? []
+            let goGrid = frameGrids[safe: mark.holdEnd] ?? []
+            restGrids.append(restGrid)
+            goGrids.append(goGrid)
+
+            let restPath = try writeThumb(restGrid, dir: thumbsDir, name: "slide-\(i)-rest.png")
+            let goPath = try writeThumb(goGrid, dir: thumbsDir, name: "slide-\(i)-go.png")
+
+            perSlide.append(PerSlideDiagnostic(
+                slideIndex: i,
+                matchedAnchorFrame: anchor,
+                anchorCollidedWithPrevious: collided,
+                lowConfidenceMatch: lowConfidence,
+                seededRest: mark.holdStart,
+                seededGo: mark.holdEnd,
+                diffProfileAroundAnchor: profile,
+                restFrameThumbnailPath: restPath,
+                goFrameThumbnailPath: goPath))
+        }
+
+        return HarnessReport(
+            deckName: deckName(input),
+            slideCount: input.stillURLs.count,
+            markCount: marks.count,
+            perSlide: perSlide,
+            restGrids: restGrids,
+            goGrids: goGrids)
+    }
+
+    // MARK: helpers
+
+    private static func deckName(_ input: SeedHarnessInput) -> String {
+        input.videoURL.deletingPathExtension().lastPathComponent
+    }
+
+    /// Mean absolute per-component diff between two equal-length grids.
+    static func gridDiff(_ a: [Double], _ b: [Double]) -> Double {
+        guard a.count == b.count, !a.isEmpty else { return 0 }
+        var s = 0.0
+        for i in a.indices { s += abs(a[i] - b[i]) }
+        return s / Double(a.count)
+    }
+
+    /// Consecutive-frame diff signal over all frames (length frameGrids.count - 1).
+    static func diffProfile(_ frameGrids: [[Double]]) -> [Double] {
+        guard frameGrids.count > 1 else { return [] }
+        return (0..<(frameGrids.count - 1)).map { gridDiff(frameGrids[$0], frameGrids[$0 + 1]) }
+    }
+
+    /// The diff-profile slice in a ±profileWindow band around `anchor`.
+    private static func profileAround(_ anchor: Int, prof: [Double]) -> [Double] {
+        guard !prof.isEmpty else { return [] }
+        let lo = max(0, anchor - profileWindow)
+        let hi = min(prof.count - 1, anchor + profileWindow)
+        guard lo <= hi else { return [] }
+        return Array(prof[lo...hi])
+    }
+
+    /// Best-effort low-confidence heuristic: if the per-frame diff AT the anchor is a
+    /// large fraction of the local max, the anchor sits in motion (not a settled
+    /// frame) → flag StillsMatch as the suspect. A signal, never a drop.
+    private static func isLowConfidence(at anchor: Int, prof: [Double]) -> Bool {
+        guard anchor < prof.count, !prof.isEmpty else { return false }
+        let local = profileAround(anchor, prof: prof)
+        guard let localMax = local.max(), localMax > 1.0 else { return false }
+        return prof[anchor] >= 0.6 * localMax
+    }
+
+    private static func nearestMark(_ marks: [SlideMark], to frame: Int) -> SlideMark? {
+        marks.min { abs($0.holdStart - frame) < abs($1.holdStart - frame) }
+    }
+
+    private static func writeThumb(_ grid: [Double], dir: URL, name: String) throws -> String {
+        let url = try HarnessReport.safeOutputURL(dir: dir, name: name)
+        if let png = HarnessReport.pngData(from: grid) { try png.write(to: url) }
+        return url.path
+    }
+}
+
+private extension Array {
+    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
+}
diff --git a/swift-app/Tests/SeedHarnessTests.swift b/swift-app/Tests/SeedHarnessTests.swift
new file mode 100644
index 0000000..38a15ac
--- /dev/null
+++ b/swift-app/Tests/SeedHarnessTests.swift
@@ -0,0 +1,126 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Section 01 — SeedHarness + HarnessReport. Fully offline: a stub encoder returns
+/// canned grids so the real StillsMatch + HoldDetector run deterministically. The
+/// harness only OBSERVES the pipeline (it bypasses MarkStore → reports the fresh seed).
+@Suite("Section 01 — SeedHarness", .serialized)
+struct SeedHarnessTests {
+
+    /// Stub encoder: video URL → canned frameGrids; each still URL → one grid by path.
+    final class StubEncoder: VideoEncoder, @unchecked Sendable {
+        let videoURL: URL
+        let frameGrids: [[Double]]
+        let stillGridByPath: [String: [Double]]
+        init(videoURL: URL, frameGrids: [[Double]], stillGridByPath: [String: [Double]]) {
+            self.videoURL = videoURL; self.frameGrids = frameGrids; self.stillGridByPath = stillGridByPath
+        }
+        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) { (32, 18, 30) }
+        func sampleGrids(url: URL) async throws -> [[Double]] {
+            url == videoURL ? frameGrids : [stillGridByPath[url.path] ?? []]
+        }
+        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws {}
+    }
+
+    private static func tmpDir() -> URL {
+        let d = FileManager.default.temporaryDirectory
+            .appendingPathComponent("kd-harness-\(UUID().uuidString)")
+        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
+        return d
+    }
+
+    /// A full-size 1728-value grid filled with one value — matches real frame grids,
+    /// so thumbnail PNG rendering works (pngData requires GridSampler.valueCount).
+    private static func solid(_ v: Double) -> [Double] {
+        [Double](repeating: v, count: GridSampler.valueCount)
+    }
+
+    /// A well-separated 6-frame synthetic deck: still A on the dark frames, still B on
+    /// the bright frames → StillsMatch picks two distinct, well-separated anchors.
+    private static func cleanDeck(out: URL) -> (SeedHarnessInput, StubEncoder) {
+        let video = URL(fileURLWithPath: "/tmp/kd-h/deck.mov")
+        let a = URL(fileURLWithPath: "/tmp/kd-h/slide-1.png")
+        let b = URL(fileURLWithPath: "/tmp/kd-h/slide-2.png")
+        let frames: [[Double]] = [solid(0), solid(0), solid(0), solid(255), solid(255), solid(255)]
+        let enc = StubEncoder(videoURL: video, frameGrids: frames,
+                              stillGridByPath: [a.path: solid(0), b.path: solid(255)])
+        return (SeedHarnessInput(videoURL: video, stillURLs: [a, b], outputDir: out), enc)
+    }
+
+    @Test("one diagnostic per still")
+    func oneDiagnosticPerStill() async throws {
+        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
+        let (input, enc) = Self.cleanDeck(out: out)
+        let report = try await SeedHarness.run(input, encoder: enc)
+        #expect(report.perSlide.count == input.stillURLs.count)
+        #expect(report.slideCount == 2)
+    }
+
+    @Test("clean deck: markCount == slideCount")
+    func cleanDeckCountMatches() async throws {
+        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
+        let (input, enc) = Self.cleanDeck(out: out)
+        let report = try await SeedHarness.run(input, encoder: enc)
+        #expect(report.markCount == report.slideCount)
+        // StillsMatch forces strictly-increasing anchors, so same-frame collision is
+        // unreachable from the real pipeline → the flag is false on a normal deck.
+        #expect(report.perSlide.allSatisfy { !$0.anchorCollidedWithPrevious })
+    }
+
+    @Test("report exposes both counts so divergence is visible")
+    func reportExposesBothCounts() async throws {
+        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
+        let (input, enc) = Self.cleanDeck(out: out)
+        let report = try await SeedHarness.run(input, encoder: enc)
+        // The harness's job is to MEASURE: both the count authority (slides) and the
+        // produced marks are reported, so any future divergence is plainly visible.
+        #expect(report.slideCount == 2)
+        #expect(report.markCount >= 1)
+    }
+
+    @Test("writeJSON emits valid JSON with one entry per slide")
+    func jsonEmit() async throws {
+        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
+        let (input, enc) = Self.cleanDeck(out: out)
+        let report = try await SeedHarness.run(input, encoder: enc)
+        try report.writeJSON(to: out)
+        let url = out.appendingPathComponent("\(HarnessReport.safeSlug(report.deckName))-seed.json")
+        let data = try Data(contentsOf: url)
+        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
+        #expect(obj?["slideCount"] as? Int == 2)
+        let per = obj?["perSlide"] as? [[String: Any]]
+        #expect(per?.count == 2)
+    }
+
+    @Test("writeVisualReport emits a self-contained HTML referencing each slide")
+    func htmlEmit() async throws {
+        let out = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: out) }
+        let (input, enc) = Self.cleanDeck(out: out)
+        let report = try await SeedHarness.run(input, encoder: enc)
+        try report.writeVisualReport(to: out)
+        let url = out.appendingPathComponent("\(HarnessReport.safeSlug(report.deckName))-seed.html")
+        let html = try String(contentsOf: url, encoding: .utf8)
+        #expect(!html.isEmpty)
+        // Self-contained: inline base64 thumbnails, no external asset refs.
+        #expect(html.contains("data:image/png;base64,"))
+        // One block per slide.
+        let blocks = html.components(separatedBy: "class=\"slide\"").count - 1
+        #expect(blocks == 2)
+    }
+
+    @Test("path-traversal: a deckName with ../ cannot escape the output dir")
+    func pathTraversalGuard() throws {
+        // Slug strips separators and dots.
+        #expect(!HarnessReport.safeSlug("../../etc/passwd").contains("/"))
+        #expect(!HarnessReport.safeSlug("../../etc/passwd").contains(".."))
+        // safeOutputURL throws when a crafted name would escape the dir.
+        let dir = Self.tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
+        #expect(throws: HarnessError.self) {
+            _ = try HarnessReport.safeOutputURL(dir: dir, name: "../escape.json")
+        }
+        // A safe name resolves INSIDE the dir.
+        let ok = try HarnessReport.safeOutputURL(dir: dir, name: "deck-seed.json")
+        #expect(ok.path.hasPrefix(dir.standardizedFileURL.path))
+    }
+}
diff --git a/swift-app/project.yml b/swift-app/project.yml
index 2ceb9a8..2098576 100644
--- a/swift-app/project.yml
+++ b/swift-app/project.yml
@@ -60,6 +60,27 @@ targets:
           ENABLE_HARDENED_RUNTIME: "YES"
           CODE_SIGN_ENTITLEMENTS: "Sources/KeynoteDeployer.entitlements"
 
+  kd-seed-harness:
+    type: tool
+    platform: macOS
+    sources:
+      - path: HarnessCLI
+      - path: Sources/Diagnostics
+      - path: Sources/Services/VideoEncoding.swift
+      - path: Sources/Services/AVFoundationVideoEncoder.swift
+      - path: Sources/Services/GridSampler.swift
+      - path: Sources/Services/StillsMatch.swift
+      - path: Sources/Services/HoldDetector.swift
+      - path: Sources/Services/VideoTimestampDeriver.swift
+      - path: Sources/Models/SlideMark.swift
+      - path: Sources/Models/VideoAnalysis.swift
+    settings:
+      base:
+        PRODUCT_BUNDLE_IDENTIFIER: com.imaginelabstudios.kd-seed-harness
+        SWIFT_VERSION: "6.2"
+        MACOSX_DEPLOYMENT_TARGET: "15.0"
+        CODE_SIGN_STYLE: Automatic
+
   KeynoteDeployerTests:
     type: bundle.unit-test
     platform: macOS
