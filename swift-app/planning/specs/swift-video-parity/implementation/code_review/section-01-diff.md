diff --git a/swift-app/Sources/Models/VideoAnalysis.swift b/swift-app/Sources/Models/VideoAnalysis.swift
new file mode 100644
index 0000000..0c1abe3
--- /dev/null
+++ b/swift-app/Sources/Models/VideoAnalysis.swift
@@ -0,0 +1,17 @@
+import Foundation
+
+/// Result of matching per-slide stills to video frames (produced by
+/// `VideoTimestampDeriver`, consumed by `VideoViewerGenerator` + `VideoDeployer`).
+///
+/// Invariants:
+/// - `frames.count == timestamps.count == slideCount`
+/// - `timestamps[i] == round((Double(frames[i]) / fps) * 1000) / 1000` (3dp)
+/// - `frames` is strictly increasing (monotonic by DP-match construction)
+struct VideoAnalysis: Sendable {
+    let frames: [Int]          // matched video-frame index per slide
+    let timestamps: [Double]   // frame/fps, rounded 3dp
+    let slideCount: Int        // == stillPaths.count
+    let width: Int
+    let height: Int
+    let fps: Double
+}
diff --git a/swift-app/Sources/Models/VideoDeployRequest.swift b/swift-app/Sources/Models/VideoDeployRequest.swift
new file mode 100644
index 0000000..191c0c5
--- /dev/null
+++ b/swift-app/Sources/Models/VideoDeployRequest.swift
@@ -0,0 +1,13 @@
+import Foundation
+
+/// User inputs for a video deck deploy. The per-slide stills are the slide-count +
+/// boundary source of truth (build-time input only — never inserted into the video,
+/// never deployed). See docs/VIDEO_DECK_VIEWER.md.
+struct VideoDeployRequest: Sendable {
+    let videoPath: String      // H.264 .mp4/.mov/.m4v
+    let stillPaths: [String]   // one image per slide, natural-sorted (boundary/count source)
+    let fps: Double            // constant export frame rate (default 30)
+    let projectName: String
+    let title: String
+    let secureEmbed: Bool
+}
diff --git a/swift-app/Sources/Resources/.gitkeep b/swift-app/Sources/Resources/.gitkeep
new file mode 100644
index 0000000..f2b38a9
--- /dev/null
+++ b/swift-app/Sources/Resources/.gitkeep
@@ -0,0 +1 @@
+Bundled video viewer template lands here (section-03).
diff --git a/swift-app/Tests/ModelsAndProjectTests.swift b/swift-app/Tests/ModelsAndProjectTests.swift
new file mode 100644
index 0000000..4660013
--- /dev/null
+++ b/swift-app/Tests/ModelsAndProjectTests.swift
@@ -0,0 +1,52 @@
+import Testing
+@testable import KeynoteDeployer
+
+@Suite("Section 1 — Models + project wiring")
+struct ModelsAndProjectTests {
+
+    // Proves the xcodegen test-target wiring works end-to-end:
+    // this test compiling + running green IS the wiring acceptance gate.
+    @Test func testTargetRunsAnEmptyTest() {
+        #expect(true)
+    }
+
+    @Test func videoDeployRequestIsConstructible() {
+        let req = VideoDeployRequest(
+            videoPath: "/tmp/deck.mp4",
+            stillPaths: ["/tmp/s001.jpeg", "/tmp/s002.jpeg"],
+            fps: 30,
+            projectName: "my-deck",
+            title: "My Deck",
+            secureEmbed: true
+        )
+        #expect(req.videoPath == "/tmp/deck.mp4")
+        #expect(req.stillPaths.count == 2)
+        #expect(req.fps == 30)
+        #expect(req.projectName == "my-deck")
+        #expect(req.title == "My Deck")
+        #expect(req.secureEmbed)
+    }
+
+    @Test func videoAnalysisIsConstructible() {
+        let a = VideoAnalysis(
+            frames: [0, 45, 90],
+            timestamps: [0.0, 1.5, 3.0],
+            slideCount: 3,
+            width: 1920, height: 1080, fps: 30
+        )
+        #expect(a.frames.count == a.slideCount)
+        #expect(a.slideCount == a.timestamps.count)
+        #expect(a.width == 1920)
+        #expect(a.height == 1080)
+        #expect(a.fps == 30)
+    }
+
+    // Self-documenting compile-time witness that both models are Sendable
+    // (they cross actor boundaries in the async video pipeline).
+    @Test func modelsAreSendable() {
+        func requireSendable<T: Sendable>(_: T.Type) {}
+        requireSendable(VideoDeployRequest.self)
+        requireSendable(VideoAnalysis.self)
+        #expect(true)
+    }
+}
diff --git a/swift-app/project.yml b/swift-app/project.yml
index 8acddc9..14811b6 100644
--- a/swift-app/project.yml
+++ b/swift-app/project.yml
@@ -43,7 +43,7 @@ targets:
       base:
         PRODUCT_BUNDLE_IDENTIFIER: com.imaginelabstudios.keynote-deployer
         MARKETING_VERSION: "1.0.4"
-        CURRENT_PROJECT_VERSION: "1.0.4"
+        CURRENT_PROJECT_VERSION: "1.0.5"
         LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/../Frameworks"
       configs:
         Debug:
@@ -58,3 +58,19 @@ targets:
           CODE_SIGNING_ALLOWED: "YES"
           ENABLE_HARDENED_RUNTIME: "YES"
           CODE_SIGN_ENTITLEMENTS: "Sources/KeynoteDeployer.entitlements"
+
+  KeynoteDeployerTests:
+    type: bundle.unit-test
+    platform: macOS
+    sources:
+      - path: Tests
+    dependencies:
+      - target: KeynoteDeployer
+    settings:
+      base:
+        PRODUCT_BUNDLE_IDENTIFIER: com.imaginelabstudios.keynote-deployer.tests
+        GENERATE_INFOPLIST_FILE: "YES"
+        CODE_SIGN_STYLE: Automatic
+    # XcodeGen derives TEST_HOST + BUNDLE_LOADER automatically from the app-target
+    # dependency above (a hosted unit-test bundle), and attaches this target to the
+    # KeynoteDeployer scheme's test action. Do NOT set TEST_HOST manually.
