# Section 06 — GifDeployer: staged diff

```diff
diff --git a/swift-app/Sources/Services/GifDeployer.swift b/swift-app/Sources/Services/GifDeployer.swift
new file mode 100644
index 0000000..238e511
--- /dev/null
+++ b/swift-app/Sources/Services/GifDeployer.swift
@@ -0,0 +1,143 @@
+import Foundation
+
+/// Sendable payload returned by `GifDeployer.deploy`. The view (Section 07) does
+/// the `modelContext.insert` of a `HistoryEntry` from this — keeping `GifDeployer`
+/// off the main actor (it has no `modelContext`). The two GIF-path-distinguishing
+/// fields are `folderPath == request.gifPath` and `fixesApplied == 0`.
+struct GifDeployResult: Sendable {
+    let url: String          // resolved production URL
+    let projectName: String
+    let title: String
+    let slideCount: Int      // == request.slides.count
+    let folderPath: String   // == request.gifPath  (history's folderPath)
+    let fixesApplied: Int    // always 0 for the GIF path
+}
+
+/// Injectable network seams for `GifDeployer.deploy`. Production passes `nil`
+/// (→ `.live(settings:)`, which talks to the real Vercel backend unchanged).
+/// Tests inject stubs so the offline suite is deterministic and never hits the
+/// network or the `vercel` CLI.
+struct GifDeployerSeams: Sendable {
+    var ensureProject: @Sendable (_ name: String) async throws -> VercelProject
+    var deploy: @Sendable (
+        _ folderPath: String,
+        _ projectId: String,
+        _ secureEmbed: Bool,
+        _ embedAllowedDomains: String,
+        _ onProgress: @Sendable (ProcessingStep) -> Void
+    ) async throws -> VercelDeployer.DeployResult
+    var resolveProductionUrl: @Sendable (_ projectId: String) async throws -> String?
+
+    /// Real backend wired from settings (the production seam).
+    static func live(settings: AppSettings) -> GifDeployerSeams {
+        let api = VercelAPI(token: settings.vercelToken, teamId: settings.vercelTeamId)
+        return GifDeployerSeams(
+            ensureProject: { name in try await api.ensureProject(name: name) },
+            deploy: { folderPath, projectId, secureEmbed, embedAllowedDomains, onProgress in
+                try await VercelDeployer.deploy(
+                    folderPath: folderPath,
+                    projectId: projectId,
+                    token: settings.vercelToken,
+                    teamId: settings.vercelTeamId,
+                    secureEmbed: secureEmbed,
+                    embedAllowedDomains: embedAllowedDomains,
+                    onProgress: onProgress
+                )
+            },
+            resolveProductionUrl: { projectId in try await api.resolveProductionUrl(projectId: projectId) }
+        )
+    }
+}
+
+/// Orchestrator for the GIF-deploy path: temp dir → copy GIF → write the
+/// Section-05 viewer `index.html` → ensure Vercel project → deploy → resolve URL.
+/// Mirrors the Electron `deploy-gif` IPC step order and reuses the existing Vercel
+/// backend unchanged. Runs entirely off the main actor; all progress flows through
+/// `onProgress`; never touches the UI.
+enum GifDeployer {
+    static func deploy(
+        _ request: GifDeployRequest,
+        settings: AppSettings,
+        seams: GifDeployerSeams? = nil,
+        onProgress: @Sendable (ProcessingStep) -> Void
+    ) async throws -> GifDeployResult {
+        let backend = seams ?? .live(settings: settings)
+
+        // 1. Validate input before any network/CLI work.
+        let gifURL = URL(fileURLWithPath: request.gifPath)
+        guard FileManager.default.fileExists(atPath: request.gifPath) else {
+            throw GifDeployError.fileNotFound(path: request.gifPath)
+        }
+        guard !settings.vercelToken.isEmpty else {
+            throw GifDeployError.vercelDeployFailed(
+                underlying: VercelError.fetchFailed("No Vercel token configured")
+            )
+        }
+
+        // 2. Securely-named unique temp dir (no predictable /tmp path; avoids TOCTOU).
+        let tempDir = try FileManager.default.url(
+            for: .itemReplacementDirectory,
+            in: .userDomainMask,
+            appropriateFor: gifURL,
+            create: true
+        )
+        defer { try? FileManager.default.removeItem(at: tempDir) }   // cleanup on EVERY exit path
+
+        // 3. Copy the GIF in, preserving filename (viewer fetches it relatively).
+        let gifFilename = gifURL.lastPathComponent
+        let destGif = tempDir.appendingPathComponent(gifFilename)
+        if FileManager.default.fileExists(atPath: destGif.path) {
+            try FileManager.default.removeItem(at: destGif)   // copyItem throws if dest exists
+        }
+        try FileManager.default.copyItem(at: gifURL, to: destGif)
+
+        // 4. Write index.html from the Section-05 generator.
+        let html = GifViewerGenerator.generate(
+            gifFilename: gifFilename,
+            secureEmbed: request.secureEmbed,
+            slides: request.slides
+        )
+        let indexURL = tempDir.appendingPathComponent("index.html")
+        try html.write(to: indexURL, atomically: true, encoding: .utf8)
+
+        // 5. Ensure the Vercel project.
+        onProgress(ProcessingStep(id: 12, label: "Vercel project", detail: "Creating or finding project...", status: .active))
+        let project = try await backend.ensureProject(request.projectName)
+        onProgress(ProcessingStep(id: 12, label: "Vercel project", detail: "Project: \(project.name)", status: .completed))
+
+        // 6. Deploy via the existing CLI deployer (it writes vercel.json for the CSP itself).
+        let deployResult: VercelDeployer.DeployResult
+        do {
+            deployResult = try await backend.deploy(
+                tempDir.path,
+                project.id,
+                request.secureEmbed,
+                settings.embedAllowedDomains,
+                onProgress
+            )
+        } catch {
+            throw GifDeployError.vercelDeployFailed(underlying: error)
+        }
+        guard deployResult.success else {
+            throw GifDeployError.vercelDeployFailed(
+                underlying: VercelError.fetchFailed(deployResult.error ?? "Deployment failed")
+            )
+        }
+
+        // 7. Resolve the real production URL (Vercel truncates long subdomains —
+        //    never construct \(name).vercel.app as the primary source).
+        let prodUrl = (try? await backend.resolveProductionUrl(project.id))
+            ?? "https://\(request.projectName).vercel.app"
+        onProgress(ProcessingStep(id: 16, label: "Complete", detail: prodUrl, status: .completed))
+
+        // 8. Return the history payload (temp dir cleaned by the defer above).
+        return GifDeployResult(
+            url: prodUrl,
+            projectName: request.projectName,
+            title: request.title,
+            slideCount: request.slides.count,
+            folderPath: request.gifPath,
+            fixesApplied: 0
+        )
+    }
+}
diff --git a/swift-app/Tests/GifDeployerTests.swift b/swift-app/Tests/GifDeployerTests.swift
new file mode 100644
index 0000000..d9e81d2
--- /dev/null
+++ b/swift-app/Tests/GifDeployerTests.swift
@@ -0,0 +1,241 @@
+import Testing
+import Foundation
+@testable import KeynoteDeployer
+
+@Suite("GifDeployer")
+struct GifDeployerTests {
+
+    // MARK: - Helpers
+
+    static let slides: [DetectedSlide] = [
+        DetectedSlide(restFrame: 10, holdStart: 8, holdEnd: 14, transitionFrames: TransitionRange(start: 15, end: 18)),
+        DetectedSlide(restFrame: 30, holdStart: 28, holdEnd: 34, transitionFrames: nil),
+    ]
+
+    /// Write a tiny placeholder .gif to a unique temp path and return it.
+    /// (copyItem copies bytes — it does not validate GIF structure — so any
+    /// bytes suffice for the offline temp-dir/HTML tests.)
+    static func makeTempGif(_ name: String = "deck.gif") throws -> URL {
+        let dir = FileManager.default.temporaryDirectory
+            .appendingPathComponent("gifdeployer-test-\(UUID().uuidString)", isDirectory: true)
+        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
+        let gif = dir.appendingPathComponent(name)
+        try Data("GIF89a-fake".utf8).write(to: gif)
+        return gif
+    }
+
+    static func dummyProject(id: String = "prj_test", name: String = "deck") -> VercelProject {
+        VercelProject(id: id, name: name, accountId: "acc", createdAt: nil, updatedAt: nil,
+                      productionUrl: nil, latestDeployment: nil)
+    }
+
+    static func request(gifPath: String, secureEmbed: Bool = false, slides: [DetectedSlide] = GifDeployerTests.slides) -> GifDeployRequest {
+        GifDeployRequest(gifPath: gifPath, projectName: "deck", slideCount: slides.count,
+                         title: "Deck", secureEmbed: secureEmbed, slides: slides)
+    }
+
+    static let settings: AppSettings = {
+        var s = AppSettings.default
+        s.vercelToken = "test-token"
+        return s
+    }()
+
+    // MARK: - Input validation
+
+    @Test("missing GIF throws fileNotFound before any network call")
+    func missingGifThrowsFileNotFound() async {
+        let req = Self.request(gifPath: "/definitely/not/here-\(UUID().uuidString).gif")
+        await #expect(throws: GifDeployError.self) {
+            // seams that would crash if reached — proves we throw before touching them
+            let seams = GifDeployerSeams(
+                ensureProject: { _ in Issue.record("ensureProject must not run"); return Self.dummyProject() },
+                deploy: { _, _, _, _, _ in Issue.record("deploy must not run"); return .init(success: true, url: "", error: nil) },
+                resolveProductionUrl: { _ in nil }
+            )
+            _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+        }
+    }
+
+    // MARK: - Temp-dir hygiene
+
+    @Test("creates a unique temp dir containing GIF + index.html, then cleans it up")
+    func createsAndCleansUniqueTempDirectory() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path)
+
+        // Capture the folderPath the deployer hands to the backend.
+        final class Box: @unchecked Sendable { var folder: String? }
+        let box = Box()
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { folderPath, _, _, _, _ in
+                box.folder = folderPath
+                // While inside deploy the temp dir must hold exactly the GIF + index.html.
+                let contents = try FileManager.default.contentsOfDirectory(atPath: folderPath).sorted()
+                #expect(contents == ["deck.gif", "index.html"])
+                return .init(success: true, url: "", error: nil)
+            },
+            resolveProductionUrl: { _ in "https://deck.vercel.app" }
+        )
+
+        _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+
+        let folder = try #require(box.folder)
+        // Not a predictable /tmp/...-<timestamp> path; and removed after return.
+        #expect(!FileManager.default.fileExists(atPath: folder))
+    }
+
+    @Test("index.html written into the temp dir equals GifViewerGenerator output")
+    func writesViewerHtmlMatchingGenerator() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path, secureEmbed: true)
+
+        final class Box: @unchecked Sendable { var html: String? }
+        let box = Box()
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { folderPath, _, _, _, _ in
+                let indexPath = (folderPath as NSString).appendingPathComponent("index.html")
+                box.html = try String(contentsOfFile: indexPath, encoding: .utf8)
+                return .init(success: true, url: "", error: nil)
+            },
+            resolveProductionUrl: { _ in "https://deck.vercel.app" }
+        )
+
+        _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+
+        let written = try #require(box.html)
+        let expected = GifViewerGenerator.generate(gifFilename: "deck.gif", secureEmbed: true, slides: Self.slides)
+        #expect(written == expected)
+    }
+
+    // MARK: - Failure mapping
+
+    @Test("deploy returning success=false maps to GifDeployError.vercelDeployFailed")
+    func deployFailureMapsToVercelDeployFailed() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path)
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { _, _, _, _, _ in .init(success: false, url: "", error: "boom") },
+            resolveProductionUrl: { _ in nil }
+        )
+
+        await #expect(throws: GifDeployError.self) {
+            _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+        }
+    }
+
+    @Test("a thrown deploy error is wrapped as vercelDeployFailed")
+    func deployThrowMapsToVercelDeployFailed() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path)
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { _, _, _, _, _ in throw VercelError.fetchFailed("cli exploded") },
+            resolveProductionUrl: { _ in nil }
+        )
+
+        var caught: GifDeployError?
+        do {
+            _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+        } catch let e as GifDeployError {
+            caught = e
+        }
+        if case .vercelDeployFailed = try #require(caught) {} else {
+            Issue.record("expected .vercelDeployFailed, got \(String(describing: caught))")
+        }
+    }
+
+    // MARK: - Success payload
+
+    @Test("success returns history fields: folderPath==gifPath, fixesApplied==0, slideCount==slides.count")
+    func successProvidesHistoryFields() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path)
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { _, _, _, _, _ in .init(success: true, url: "", error: nil) },
+            resolveProductionUrl: { _ in "https://deck-abc.vercel.app" }
+        )
+
+        let result = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+        #expect(result.url == "https://deck-abc.vercel.app")
+        #expect(result.folderPath == gif.path)
+        #expect(result.fixesApplied == 0)
+        #expect(result.slideCount == Self.slides.count)
+        #expect(result.projectName == "deck")
+    }
+
+    @Test("empty slides deploys without crashing (zero-slide guard)")
+    func emptySlidesDoesNotCrash() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path, slides: [])
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { _, _, _, _, _ in .init(success: true, url: "", error: nil) },
+            resolveProductionUrl: { _ in "https://deck.vercel.app" }
+        )
+
+        let result = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { _ in })
+        #expect(result.slideCount == 0)
+    }
+
+    @Test("progress steps are emitted (project → complete)")
+    func emitsProgressSteps() async throws {
+        let gif = try Self.makeTempGif()
+        defer { try? FileManager.default.removeItem(at: gif.deletingLastPathComponent()) }
+        let req = Self.request(gifPath: gif.path)
+
+        final class Box: @unchecked Sendable { var ids: [Int] = [] }
+        let box = Box()
+
+        let seams = GifDeployerSeams(
+            ensureProject: { _ in Self.dummyProject() },
+            deploy: { _, _, _, _, onProgress in
+                onProgress(ProcessingStep(id: 13, label: "Deploy", detail: "", status: .active))
+                return .init(success: true, url: "", error: nil)
+            },
+            resolveProductionUrl: { _ in "https://deck.vercel.app" }
+        )
+
+        _ = try await GifDeployer.deploy(req, settings: Self.settings, seams: seams, onProgress: { step in box.ids.append(step.id) })
+        // 12 (ensure project, x2), 13 (deploy), 16 (complete)
+        #expect(box.ids.contains(12))
+        #expect(box.ids.contains(16))
+        #expect(box.ids.last == 16)
+    }
+
+    // MARK: - GATE-2 (LIVE — skipped without TEST_GIF + real Vercel token)
+
+    @Test("GATE-2: live deploy of TEST_GIF produces a reachable Vercel URL")
+    func gate2LiveDeployProducesReachableUrl() async throws {
+        guard let gifPath = ProcessInfo.processInfo.environment["TEST_GIF"] else { return }
+        let settings = try FileOperations.loadSettings()
+        guard !settings.vercelToken.isEmpty else { return }
+
+        let req = Self.request(gifPath: gifPath)
+        let result = try await GifDeployer.deploy(req, settings: settings, onProgress: { _ in })
+
+        #expect(result.url.hasPrefix("https://"))
+        #expect(result.fixesApplied == 0)
+        #expect(result.folderPath == gifPath)
+        // Reachability check.
+        let url = try #require(URL(string: result.url))
+        let (_, response) = try await URLSession.shared.data(from: url)
+        let http = try #require(response as? HTTPURLResponse)
+        #expect((200..<400).contains(http.statusCode))
+    }
+}
```

(pbxproj delta omitted — just adds the two new file refs.)
