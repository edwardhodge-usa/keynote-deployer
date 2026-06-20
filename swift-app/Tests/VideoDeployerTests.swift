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
        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
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
        let result = try await VideoDeployer.deploy(
            Self.request(), settings: Self.settings(), seams: seams,
            onProgress: { step in if step.status == .completed { completed.add(step.id) } })

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
        #expect(result.slideCount == 2)               // == stillPaths.count
        #expect(result.width == 1920 && result.height == 1080) // probed dims (for the embed ratio)
        #expect(result.folderPath == Self.videoURL.path) // SOURCE video path, not temp dir

        // Exactly 4 distinct steps reached .completed (ids 1–4).
        #expect(completed.ids == [1, 2, 3, 4])
    }

    @Test("missing vercelToken throws BEFORE the deploy seam is called")
    func deploy_missingToken() async throws {
        let enc = Self.makeStub()
        let flag = DeployFlag()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in
            flag.mark(); return "https://\(name).vercel.app"
        }

        await #expect(throws: VideoDeployError.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), settings: Self.settings(token: ""), seams: seams,
                onProgress: { _ in })
        }
        #expect(flag.called == false)
    }

    @Test("A4: temp dir removed on success")
    func deploy_cleansTempOnSuccess() async throws {
        let before = Self.tempDirs()
        let enc = Self.makeStub()
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in "https://\(name).vercel.app" }
        _ = try await VideoDeployer.deploy(
            Self.request(), settings: Self.settings(), seams: seams, onProgress: { _ in })
        // No NEW pipeline temp dir survives.
        #expect(Self.tempDirs().subtracting(before).isEmpty)
    }

    @Test("A4: temp dir removed even when encode throws")
    func deploy_cleansTempOnThrow() async throws {
        let before = Self.tempDirs()
        struct Boom: Error {}
        let enc = Self.makeStub(encodeError: Boom())
        let seams = VideoDeployerSeams(encoder: enc) { _, name, _, _ in "https://\(name).vercel.app" }

        await #expect(throws: Boom.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), settings: Self.settings(), seams: seams, onProgress: { _ in })
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

        await #expect(throws: Boom.self) {
            _ = try await VideoDeployer.deploy(
                Self.request(), settings: Self.settings(), seams: seams,
                onProgress: { s in if s.id == 4 && s.status == .error { errored.mark() } })
        }
        #expect(Self.tempDirs().subtracting(before).isEmpty)  // defer cleaned the late-throw path
        #expect(errored.called)                               // Step 4 surfaced .error, not stuck .active
    }

    @Test("A6: useFfmpegEncoder UserDefaults flag selects the encoder in .live")
    func live_encoderSelection() {
        let key = "useFfmpegEncoder"
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set(true, forKey: key)
        #expect(VideoDeployerSeams.live(settings: Self.settings()).encoder is FFmpegVideoEncoder)

        UserDefaults.standard.set(false, forKey: key)
        #expect(VideoDeployerSeams.live(settings: Self.settings()).encoder is AVFoundationVideoEncoder)
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
