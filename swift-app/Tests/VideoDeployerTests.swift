import Testing
import Foundation
@testable import KeynoteDeployer

/// Section 7 — VideoDeployer orchestration. Fully offline: a stub encoder (no real
/// probe/sample/encode) + a stub deploy seam (no network). `derive` runs for real
/// over the stub's canned grids, so frame matching is deterministic.
// Serialized: the A4 temp-dir tests observe the shared /tmp namespace, so they
// must not run concurrently with each other (or count snapshots race).
@Suite("Section 7 — VideoDeployer", .serialized)
struct VideoDeployerTests {

    /// Stub encoder. Distinguishes the video URL (→ frameGrids) from still URLs
    /// (→ one grid keyed by path) so `derive` yields a known monotonic match.
    /// Records call order (thread-safe; sampleGrids may run off the test executor).
    final class StubEncoder: VideoEncoder, @unchecked Sendable {
        let videoURL: URL
        let frameGrids: [[Double]]
        let stillGridByPath: [String: [Double]]
        var probeDims: (width: Int, height: Int, fps: Double) = (1920, 1080, 30)
        var encodeError: Error?

        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        private func record(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }

        init(videoURL: URL, frameGrids: [[Double]], stillGridByPath: [String: [Double]]) {
            self.videoURL = videoURL
            self.frameGrids = frameGrids
            self.stillGridByPath = stillGridByPath
        }

        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) {
            record("probe"); return probeDims
        }
        func sampleGrids(url: URL) async throws -> [[Double]] {
            record("sample")
            if url == videoURL { return frameGrids }
            return [stillGridByPath[url.path] ?? []]
        }
        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double], fps: Double) async throws {
            record("encode")
            if let e = encodeError { throw e }
            // Write a 0-byte deck.mp4 so the generate/write step proceeds.
            FileManager.default.createFile(atPath: output.path, contents: Data())
        }
    }

    /// Thread-safe flag recording whether the deploy seam was invoked.
    final class DeployFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _called = false
        var called: Bool { lock.lock(); defer { lock.unlock() }; return _called }
        func mark() { lock.lock(); _called = true; lock.unlock() }
    }

    // Fixture: video URL + 2 stills that match frames 0 and 2 of a 3-frame video.
    private static let videoURL = URL(fileURLWithPath: "/tmp/kd-sec7/deck.mov")
    private static func stillURL(_ n: String) -> URL { URL(fileURLWithPath: "/tmp/kd-sec7/\(n)") }

    private static func makeStub(encodeError: Error? = nil) -> StubEncoder {
        let s1 = stillURL("slide-1.jpeg"); let s2 = stillURL("slide-2.jpeg")
        let enc = StubEncoder(
            videoURL: videoURL,
            frameGrids: [[0], [10], [20]],
            stillGridByPath: [s1.path: [0.0], s2.path: [20.0]])
        if let encodeError { enc.encodeError = encodeError }
        return enc
    }

    private static func request(secureEmbed: Bool = false) -> VideoDeployRequest {
        VideoDeployRequest(
            videoPath: videoURL.path,
            stillPaths: [stillURL("slide-1.jpeg").path, stillURL("slide-2.jpeg").path],
            fps: 30,
            projectName: "my-deck",
            title: "My Deck",
            secureEmbed: secureEmbed)
    }

    private static func settings(token: String = "tok") -> AppSettings {
        var s = AppSettings.default
        s.vercelToken = token
        s.vercelTeamId = "team_x"
        return s
    }

    /// Set of this pipeline's temp dirs currently in /tmp. Set-difference (not a
    /// count) so a pre-existing dir from another test can't perturb the assertion.
    private static func tempDirs() -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: "/tmp")) ?? []
        return Set(contents.filter { $0.hasPrefix("keynote-deployer-video-") })
    }

    @Test("step order + result fields + exactly 4 completed progress steps")
    func deploy_happyPath() async throws {
        let enc = Self.makeStub()
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: enc) { folder, name, _, _ in
            flag.mark()
            // The deploy seam runs AFTER encode (verifies orchestration order).
            #expect(enc.calls.contains("encode"))
            #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("index.html").path))
            return "https://resolved-\(name).vercel.app"
        }

        let completed = CompletedSink()
        let onProgress: @Sendable (ProcessingStep) -> Void = { step in
            if step.status == .completed { completed.add(step.id) }
        }
        let (analysis, seedMarks) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: onProgress)
        let result = try await VideoDeployer.deploy(
            Self.request(), analysis: analysis, marks: seedMarks,
            settings: Self.settings(), seams: seams, onProgress: onProgress)

        // Step order: probe first, encode after all samples.
        #expect(enc.calls.first == "probe")
        let encodeIdx = enc.calls.firstIndex(of: "encode")
        let lastSampleIdx = enc.calls.lastIndex(of: "sample")
        #expect(encodeIdx != nil && lastSampleIdx != nil && encodeIdx! > lastSampleIdx!)
        #expect(flag.called)

        // Result fields.
        #expect(result.url == "https://resolved-my-deck.vercel.app")
        #expect(result.projectName == "my-deck")
        #expect(result.title == "My Deck")
        #expect(result.slideCount == 2)               // == analysis.slideCount (authority)
        #expect(result.countDiverged == false)        // marks and slides agree on a normal run
        #expect(result.width == 1920 && result.height == 1080) // probed dims (for the embed ratio)
        #expect(result.folderPath == Self.videoURL.path) // SOURCE video path, not temp dir

        // Exactly 4 distinct steps reached .completed (ids 1–4).
        #expect(completed.ids == [1, 2, 3, 4])
    }

    @Test("deploy reports analysis.slideCount (authority), not marks.count, and flags divergence")
    func deploy_reportsAuthoritativeCount() async throws {
        let enc = Self.makeStub()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in "https://\(name).vercel.app" }
        // analysis claims 5 slides, but we hand deploy only 4 (valid, non-empty) marks → divergence.
        let analysis = VideoAnalysis(
            frames: [0, 10, 20, 30, 40],
            timestamps: [0, 0.333, 0.667, 1.0, 1.333],
            slideCount: 5, width: 1920, height: 1080, fps: 30, frameCount: 100)
        let marks = [SlideMark(holdStart: 0, holdEnd: 5), SlideMark(holdStart: 10, holdEnd: 15),
                     SlideMark(holdStart: 20, holdEnd: 25), SlideMark(holdStart: 30, holdEnd: 35)]
        let result = try await VideoDeployer.deploy(
            Self.request(), analysis: analysis, marks: marks,
            settings: Self.settings(), seams: seams, onProgress: { _ in })
        #expect(result.slideCount == 5)        // the authority, NOT marks.count (4)
        #expect(result.countDiverged == true)  // divergence recorded (non-fatal)
    }

    @Test("missing vercelToken throws BEFORE the deploy seam is called")
    func deploy_missingToken() async throws {
        let enc = Self.makeStub()
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in
            flag.mark(); return "https://\(name).vercel.app"
        }

        let (analysis, seedMarks) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        await #expect(throws: VideoDeployError.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), analysis: analysis, marks: seedMarks,
                settings: Self.settings(token: ""), seams: seams,
                onProgress: { _ in })
        }
        #expect(flag.called == false)
    }

    @Test("A4: temp dir removed on success")
    func deploy_cleansTempOnSuccess() async throws {
        let before = Self.tempDirs()
        let enc = Self.makeStub()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in "https://\(name).vercel.app" }
        let (analysis, seedMarks) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        _ = try await VideoDeployer.deploy(
            Self.request(), analysis: analysis, marks: seedMarks,
            settings: Self.settings(), seams: seams, onProgress: { _ in })
        // No NEW pipeline temp dir survives.
        #expect(Self.tempDirs().subtracting(before).isEmpty)
    }

    @Test("A4: temp dir removed even when encode throws")
    func deploy_cleansTempOnThrow() async throws {
        let before = Self.tempDirs()
        struct Boom: Error {}
        let enc = Self.makeStub(encodeError: Boom())
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in "https://\(name).vercel.app" }

        let (analysis, seedMarks) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        await #expect(throws: Boom.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), analysis: analysis, marks: seedMarks,
                settings: Self.settings(), seams: seams, onProgress: { _ in })
        }
        #expect(Self.tempDirs().subtracting(before).isEmpty)
    }

    @Test("A4 + error state: deploy-seam throw cleans temp dir and emits Step 4 .error")
    func deploy_cleansTempOnDeployThrow() async throws {
        let before = Self.tempDirs()
        struct Boom: Error {}
        let enc = Self.makeStub()
        let seams = VideoDeployerSeams(encoder: enc) { _, _, _, _ in throw Boom() }
        let errored = DeployFlag()

        let (analysis, seedMarks) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        await #expect(throws: Boom.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), analysis: analysis, marks: seedMarks,
                settings: Self.settings(), seams: seams,
                onProgress: { s in if s.id == 4 && s.status == .error { errored.mark() } })
        }
        #expect(Self.tempDirs().subtracting(before).isEmpty)  // defer cleaned the late-throw path
        #expect(errored.called)                               // Step 4 surfaced .error, not stuck .active
    }

    @Test(".live prefers the ffmpeg (CRF16) encoder when ffmpeg is installed")
    func live_encoderSelection() {
        let key = "useFfmpegEncoder"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        // Forcing the flag always selects ffmpeg.
        UserDefaults.standard.set(true, forKey: key)
        #expect(VideoDeployerSeams.live(settings: Self.settings()).encoder is FFmpegVideoEncoder)

        // With the flag OFF, the encoder is now availability-driven: ffmpeg when it's
        // installed (the new default — constant-quality CRF16), AVFoundation only as
        // the no-ffmpeg fallback. (The fallback branch isn't unit-tested here: there's
        // no seam to simulate an absent ffmpeg without a real PATH/binary change.)
        UserDefaults.standard.set(false, forKey: key)
        let encoder = VideoDeployerSeams.live(settings: Self.settings()).encoder
        if FFmpegVideoEncoder.isAvailable() {
            #expect(encoder is FFmpegVideoEncoder)
        } else {
            #expect(encoder is AVFoundationVideoEncoder)
        }
    }

    @Test("empty marks → invalidMarkers before seam or encode")
    func deploy_emptyMarksThrows() async throws {
        let enc = Self.makeStub()
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in flag.mark(); return "https://\(name).vercel.app" }
        let (analysis, _) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        await #expect(throws: VideoDeployError.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), analysis: analysis, marks: [],
                settings: Self.settings(), seams: seams, onProgress: { _ in })
        }
        #expect(flag.called == false)
        #expect(enc.calls.filter { $0 == "encode" }.isEmpty)
    }

    @Test("overlapping/invalid marks → invalidMarkers")
    func deploy_invalidMarksThrows() async throws {
        let enc = Self.makeStub()
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in flag.mark(); return "https://\(name).vercel.app" }
        let (analysis, _) = try await VideoDeployer.analyze(Self.request(), seams: seams, onProgress: { _ in })
        // Mark 0 holdEnd=2 overlaps mark 1 holdStart=1 (out of order / overlapping).
        let bad = [SlideMark(holdStart: 0, holdEnd: 2), SlideMark(holdStart: 1, holdEnd: 2)]
        await #expect(throws: VideoDeployError.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), analysis: analysis, marks: bad,
                settings: Self.settings(), seams: seams, onProgress: { _ in })
        }
        #expect(flag.called == false)
        #expect(enc.calls.filter { $0 == "encode" }.isEmpty)
    }

    @Test("forcedKeyframeSeconds is the sorted-unique union of holdStart+holdEnd in seconds")
    func keyframeUnion() {
        let marks = [SlideMark(holdStart: 0, holdEnd: 3), SlideMark(holdStart: 6, holdEnd: 9)]
        // fps 30 → 0/0.1/0.2/0.3 frames; expect [0, 0.1, 0.2, 0.3]
        #expect(VideoDeployer.forcedKeyframeSeconds(marks: marks, fps: 30) == [0.0, 0.1, 0.2, 0.3])
    }

    @Test("viewerSpans maps each hold to [startSec, endSec]")
    func spans() {
        let marks = [SlideMark(holdStart: 0, holdEnd: 3), SlideMark(holdStart: 6, holdEnd: 9)]
        #expect(VideoDeployer.viewerSpans(marks: marks, fps: 30) == [[0.0, 0.1], [0.2, 0.3]])
    }

    @Test("analyze returns marks; deploy honors edited marks but reports analysis.slideCount (authority)")
    func analyzeThenDeployUsesMarks() async throws {
        let encoder = StubEncoder(
            videoURL: Self.videoURL,
            frameGrids: [[0], [1], [0]],
            stillGridByPath: [Self.stillURL("a.png").path: [0],
                              Self.stillURL("b.png").path: [0]])
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: encoder) { _, name, _, _ in flag.mark(); return "https://\(name).vercel.app" }
        let request = VideoDeployRequest(
            videoPath: Self.videoURL.path,
            stillPaths: [Self.stillURL("a.png").path, Self.stillURL("b.png").path],
            fps: 30, projectName: "kd-sec7", title: "deck", secureEmbed: false)

        let (analysis, seedMarks) = try await VideoDeployer.analyze(request, seams: seams) { _ in }
        #expect(seedMarks.count == analysis.slideCount)

        let edited = [SlideMark(holdStart: 0, holdEnd: 0), SlideMark(holdStart: 1, holdEnd: 1), SlideMark(holdStart: 2, holdEnd: 2)]
        var settings = AppSettings.default; settings.vercelToken = "tok"
        let result = try await VideoDeployer.deploy(request, analysis: analysis, marks: edited, settings: settings, seams: seams) { _ in }
        #expect(flag.called)
        // Section 02: deploy reports the AUTHORITATIVE slide count (analysis.slideCount == 2),
        // not the edited marks count (3); the marks/slides divergence is flagged (non-fatal).
        #expect(result.slideCount == 2)
        #expect(result.countDiverged == true)
    }
}

/// Thread-safe collector of distinct completed step ids in first-seen order.
private final class CompletedSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _ids: [Int] = []
    var ids: [Int] { lock.lock(); defer { lock.unlock() }; return _ids }
    func add(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        if !_ids.contains(id) { _ids.append(id) }
    }
}
