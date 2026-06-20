diff --git a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
index c3a5007..4e14ec8 100644
--- a/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
+++ b/swift-app/KeynoteDeployer.xcodeproj/project.pbxproj
@@ -12,6 +12,7 @@
 		0F265C03C5A0D733EB35550F /* VideoEncoding.swift in Sources */ = {isa = PBXBuildFile; fileRef = 06A48F26B10DD642AD5B6464 /* VideoEncoding.swift */; };
 		13F48A1926D584294516EEE0 /* SidebarView.swift in Sources */ = {isa = PBXBuildFile; fileRef = E3C9945227E19D94B300923C /* SidebarView.swift */; };
 		15125B060EAC0C268F273761 /* ProjectsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A857D151061C711E9B9957C8 /* ProjectsView.swift */; };
+		1EA6EDF68274954358561E02 /* VideoTimestampDeriver.swift in Sources */ = {isa = PBXBuildFile; fileRef = AC9556AE330C0F37CAC5751F /* VideoTimestampDeriver.swift */; };
 		22CAA3C6B137E1DD00364127 /* video-viewer-golden-plain.html in Resources */ = {isa = PBXBuildFile; fileRef = 0A7E4D56A5BFA32DA7B9285F /* video-viewer-golden-plain.html */; };
 		2D5BD33951D0A7FF662C0A3F /* IndexHtmlGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */; };
 		32E92AFC106BE6E110B3B5BA /* HistoryEntry.swift in Sources */ = {isa = PBXBuildFile; fileRef = 6014F6E3BFFA0FEA826D475F /* HistoryEntry.swift */; };
@@ -43,6 +44,7 @@
 		C1320156DDC609C7483B1F6A /* GridSampler.swift in Sources */ = {isa = PBXBuildFile; fileRef = 38B3998DF7B225F311525034 /* GridSampler.swift */; };
 		C4E54C86FF711C684113EACE /* HistoryView.swift in Sources */ = {isa = PBXBuildFile; fileRef = B55FB9E316B645CFD0C08B4F /* HistoryView.swift */; };
 		C6F91B76D51C9A06A0354265 /* FFmpegVideoEncoder.swift in Sources */ = {isa = PBXBuildFile; fileRef = 62962D07AF83802E42A4D632 /* FFmpegVideoEncoder.swift */; };
+		CE796BD76C505B8CFE155F1A /* VideoTimestampDeriverTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 235D9E8F90EF404DE587C849 /* VideoTimestampDeriverTests.swift */; };
 		CF38C9DBAC8AFF2AF62781ED /* VideoViewerGeneratorTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */; };
 		D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */ = {isa = PBXBuildFile; fileRef = CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */; };
 		EA8F1C902A8D2AD7D8A93A30 /* AppConfig.swift in Sources */ = {isa = PBXBuildFile; fileRef = 390DDF13A88F1C59BE62D165 /* AppConfig.swift */; };
@@ -69,6 +71,7 @@
 		17A85902F080898C86352154 /* VercelAPI.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelAPI.swift; sourceTree = "<group>"; };
 		1C1AE82499CE26C6968F8AA7 /* UpdaterService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UpdaterService.swift; sourceTree = "<group>"; };
 		21BB4E825DF33B80AB6A0E9C /* FFmpegVideoEncoderTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FFmpegVideoEncoderTests.swift; sourceTree = "<group>"; };
+		235D9E8F90EF404DE587C849 /* VideoTimestampDeriverTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoTimestampDeriverTests.swift; sourceTree = "<group>"; };
 		23F61A6BE61C1CDC6237ADF6 /* VercelProject.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VercelProject.swift; sourceTree = "<group>"; };
 		25181D8CAB9909769D352295 /* DeploymentVerifier.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeploymentVerifier.swift; sourceTree = "<group>"; };
 		252E013E7FB809AC24354D6C /* DeployProgressView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DeployProgressView.swift; sourceTree = "<group>"; };
@@ -97,6 +100,7 @@
 		A80FCBDC9C1ECDDA55886B5A /* IndexHtmlGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IndexHtmlGenerator.swift; sourceTree = "<group>"; };
 		A857D151061C711E9B9957C8 /* ProjectsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ProjectsView.swift; sourceTree = "<group>"; };
 		AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ModelsAndProjectTests.swift; sourceTree = "<group>"; };
+		AC9556AE330C0F37CAC5751F /* VideoTimestampDeriver.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoTimestampDeriver.swift; sourceTree = "<group>"; };
 		B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoViewerGeneratorTests.swift; sourceTree = "<group>"; };
 		B55FB9E316B645CFD0C08B4F /* HistoryView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HistoryView.swift; sourceTree = "<group>"; };
 		CBCFD1B404C9D887FD5FA7B0 /* VideoDeployRequest.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = VideoDeployRequest.swift; sourceTree = "<group>"; };
@@ -136,6 +140,7 @@
 				17A85902F080898C86352154 /* VercelAPI.swift */,
 				282B4D114C60E28D56418FAE /* VercelDeployer.swift */,
 				06A48F26B10DD642AD5B6464 /* VideoEncoding.swift */,
+				AC9556AE330C0F37CAC5751F /* VideoTimestampDeriver.swift */,
 				42ABCE72BEC351859554D951 /* VideoViewerGenerator.swift */,
 			);
 			path = Services;
@@ -221,6 +226,7 @@
 				403D899438A463CD2A362774 /* GridSamplerTests.swift */,
 				AA065551FEEAB39DDEAC9B60 /* ModelsAndProjectTests.swift */,
 				E0A6C88075BDCE7E6E5AF0C9 /* StillsMatchTests.swift */,
+				235D9E8F90EF404DE587C849 /* VideoTimestampDeriverTests.swift */,
 				B13D91BAAE5426D7EB676719 /* VideoViewerGeneratorTests.swift */,
 				94CAE77E1E83C3297FBB1B45 /* Fixtures */,
 			);
@@ -375,6 +381,7 @@
 				A14416E992CD0B244FFA16A1 /* GridSamplerTests.swift in Sources */,
 				419F05D5433E94752E999ED6 /* ModelsAndProjectTests.swift in Sources */,
 				4B289C6795B7E64A9625F96D /* StillsMatchTests.swift in Sources */,
+				CE796BD76C505B8CFE155F1A /* VideoTimestampDeriverTests.swift in Sources */,
 				CF38C9DBAC8AFF2AF62781ED /* VideoViewerGeneratorTests.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
@@ -413,6 +420,7 @@
 				8D642D0B7DE7423F33970CAC /* VideoAnalysis.swift in Sources */,
 				D11E662E9329C958E5FD05BE /* VideoDeployRequest.swift in Sources */,
 				0F265C03C5A0D733EB35550F /* VideoEncoding.swift in Sources */,
+				1EA6EDF68274954358561E02 /* VideoTimestampDeriver.swift in Sources */,
 				4A2E1C7FE7EE01DC8EB9F111 /* VideoViewerGenerator.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
diff --git a/swift-app/Sources/Services/VideoTimestampDeriver.swift b/swift-app/Sources/Services/VideoTimestampDeriver.swift
new file mode 100644
index 0000000..e5ede4e
--- /dev/null
+++ b/swift-app/Sources/Services/VideoTimestampDeriver.swift
@@ -0,0 +1,68 @@
+import Foundation
+
+/// Derives per-slide timestamps for a video deck by DP-matching the user's
+/// per-slide still images to the video's frames.
+///
+/// Slide boundaries can't be recovered from video pixels alone (a build/fade step
+/// looks identical to a real slide on a constant background), so the user exports
+/// one still per slide: the *count* of stills IS the slide count, and each still
+/// is matched to the frame it appears on to derive that slide's timestamp. Stills
+/// are a build-time input only — never inserted into the video, never deployed.
+///
+/// Pure orchestration over an injected `VideoEncoder` (the concrete encoder is
+/// supplied by Section 07; tests inject a fake). Off-main, cancellable, and
+/// reports fractional progress (A5).
+enum VideoTimestampDeriver {
+
+    static func derive(encoder: VideoEncoder,
+                       videoURL: URL,
+                       stillURLs: [URL],
+                       fps: Double,
+                       onProgress: @Sendable (Double) -> Void = { _ in }) async throws -> VideoAnalysis {
+        // 1. Natural-sort the stills (numeric-aware: slide-010 after slide-002).
+        // The matcher requires stills in true slide order; do NOT reorder frames.
+        let sortedPaths = StillsMatch.naturalSort(stillURLs.map(\.path))
+        let byPath = Dictionary(stillURLs.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
+        let stills = sortedPaths.compactMap { byPath[$0] }
+
+        // 2. Probe dimensions (width/height only; the supplied fps drives timestamp math).
+        try Task.checkCancellation()
+        let (width, height, _) = try await encoder.probe(url: videoURL)
+
+        // 3. Sample the video frames → many 1728-value grids in frame order.
+        try Task.checkCancellation()
+        let frameGrids = try await encoder.sampleGrids(url: videoURL)
+        onProgress(stills.isEmpty ? 1.0 : 0.5)
+
+        // 4. Sample each still → one grid each (in natural-sorted order).
+        var stillGrids: [[Double]] = []
+        stillGrids.reserveCapacity(stills.count)
+        for (i, url) in stills.enumerated() {
+            try Task.checkCancellation()
+            let grids = try await encoder.sampleGrids(url: url)
+            if let first = grids.first { stillGrids.append(first) }
+            onProgress(0.5 + 0.45 * (Double(i + 1) / Double(stills.count)))
+        }
+
+        // 5. DP-match stills → video frames (one monotonic frame index per slide).
+        try Task.checkCancellation()
+        let frames = try StillsMatch.matchStillsToFrames(stillGrids, frameGrids)
+
+        // 6. Frame indices → 3-decimal (ms) timestamps. EXACT rounding — the viewer's
+        // {{TS}} JSON (Section 03) and the encoder's -force_key_frames (Sections 04/05)
+        // re-derive from these same values, so the rounding must be identical.
+        let timestamps = frames.map { round((Double($0) / fps) * 1000) / 1000 }
+        onProgress(1.0)
+
+        // 7. slideCount is the stills count — the slide-count truth (== frames.count
+        // by construction).
+        return VideoAnalysis(
+            frames: frames,
+            timestamps: timestamps,
+            slideCount: stillURLs.count,
+            width: width,
+            height: height,
+            fps: fps
+        )
+    }
+}
diff --git a/swift-app/Tests/VideoTimestampDeriverTests.swift b/swift-app/Tests/VideoTimestampDeriverTests.swift
new file mode 100644
index 0000000..78e2702
--- /dev/null
+++ b/swift-app/Tests/VideoTimestampDeriverTests.swift
@@ -0,0 +1,121 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+/// Section 6 — VideoTimestampDeriver. Fully offline: a fake VideoEncoder returns
+/// canned 1-value grids (same shape StillsMatch's own tests use) so expected
+/// matched frame indices are known.
+@Suite("Section 6 — VideoTimestampDeriver")
+struct VideoTimestampDeriverTests {
+
+    /// Fake encoder: video URL → canned frame grids; any other URL → that still's
+    /// single grid (keyed by path). encodeWithKeyframes is never called by derive.
+    struct FakeEncoder: VideoEncoder {
+        let videoURL: URL
+        let frameGrids: [[Double]]
+        let stillGridByPath: [String: [Double]]
+        let dims: (width: Int, height: Int, fps: Double)
+
+        func probe(url: URL) async throws -> (width: Int, height: Int, fps: Double) { dims }
+        func sampleGrids(url: URL) async throws -> [[Double]] {
+            if url == videoURL { return frameGrids }
+            return [stillGridByPath[url.path] ?? []]
+        }
+        func encodeWithKeyframes(input: URL, output: URL, timestamps: [Double]) async throws {
+            fatalError("encodeWithKeyframes is not used by derive()")
+        }
+    }
+
+    /// Thread-safe progress collector (onProgress is @Sendable, may be called off
+    /// the test's executor).
+    final class ProgressSink: @unchecked Sendable {
+        private let lock = NSLock()
+        private var storage: [Double] = []
+        func record(_ v: Double) { lock.lock(); storage.append(v); lock.unlock() }
+        var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
+    }
+
+    private static func stillURL(_ name: String) -> URL {
+        URL(fileURLWithPath: "/tmp/kd-sec6/\(name)")
+    }
+    private static let video = URL(fileURLWithPath: "/tmp/kd-sec6/deck.mp4")
+
+    @Test("derive returns slideCount, monotonic frames, and 3dp timestamps")
+    func derive_basic() async throws {
+        // 10 frames: grids [0],[1],...,[9]. Stills key to frames 0, 3, 7.
+        let frameGrids = (0..<10).map { [Double($0)] }
+        let stills = ["s1.jpeg", "s2.jpeg", "s3.jpeg"].map(Self.stillURL)
+        let gridByPath = [
+            stills[0].path: [0.0],
+            stills[1].path: [3.0],
+            stills[2].path: [7.0],
+        ]
+        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
+                              stillGridByPath: gridByPath, dims: (1920, 1080, 30))
+
+        let result = try await VideoTimestampDeriver.derive(
+            encoder: enc, videoURL: Self.video, stillURLs: stills, fps: 30)
+
+        #expect(result.slideCount == 3)
+        #expect(result.frames == [0, 3, 7])
+        #expect(zip(result.frames, result.frames.dropFirst()).allSatisfy { $0 < $1 })  // strictly monotonic
+        #expect(result.timestamps == result.frames.map { round((Double($0) / 30.0) * 1000) / 1000 })
+        #expect(result.timestamps == [0.0, 0.1, 0.233])
+        #expect(result.width == 1920)
+        #expect(result.height == 1080)
+        #expect(result.fps == 30)
+    }
+
+    @Test("A5: progress handler fires during sampling and finishes ~1.0")
+    func derive_reportsProgress() async throws {
+        let frameGrids = (0..<6).map { [Double($0)] }
+        let stills = ["a.jpeg", "b.jpeg"].map(Self.stillURL)
+        let gridByPath = [stills[0].path: [0.0], stills[1].path: [4.0]]
+        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
+                              stillGridByPath: gridByPath, dims: (1280, 720, 24))
+        let sink = ProgressSink()
+
+        _ = try await VideoTimestampDeriver.derive(
+            encoder: enc, videoURL: Self.video, stillURLs: stills, fps: 24,
+            onProgress: { sink.record($0) })
+
+        let v = sink.values
+        #expect(v.count >= 1)
+        #expect(abs((v.last ?? 0) - 1.0) < 0.0001)
+        #expect(v.allSatisfy { $0 >= 0 && $0 <= 1.0001 })
+    }
+
+    @Test("stills are natural-sorted before matching")
+    func derive_naturalSortsStills() async throws {
+        let frameGrids = (0..<10).map { [Double($0)] }
+        // Slides keyed to increasing frames; supplied OUT OF natural order.
+        let s010 = Self.stillURL("slide-010.jpeg")
+        let s001 = Self.stillURL("slide-001.jpeg")
+        let s002 = Self.stillURL("slide-002.jpeg")
+        let gridByPath = [
+            s001.path: [0.0],
+            s002.path: [4.0],
+            s010.path: [9.0],
+        ]
+        let enc = FakeEncoder(videoURL: Self.video, frameGrids: frameGrids,
+                              stillGridByPath: gridByPath, dims: (1920, 1080, 30))
+
+        // Input order is 010, 001, 002 — only natural-sorting yields increasing frames.
+        let result = try await VideoTimestampDeriver.derive(
+            encoder: enc, videoURL: Self.video, stillURLs: [s010, s001, s002], fps: 30)
+
+        #expect(result.frames == [0, 4, 9])
+        #expect(zip(result.frames, result.frames.dropFirst()).allSatisfy { $0 < $1 })
+    }
+
+    @Test("empty stills → empty analysis")
+    func derive_emptyStills() async throws {
+        let enc = FakeEncoder(videoURL: Self.video, frameGrids: [[0.0], [1.0]],
+                              stillGridByPath: [:], dims: (1920, 1080, 30))
+        let result = try await VideoTimestampDeriver.derive(
+            encoder: enc, videoURL: Self.video, stillURLs: [], fps: 30)
+        #expect(result.slideCount == 0)
+        #expect(result.frames == [])
+        #expect(result.timestamps == [])
+    }
+}
