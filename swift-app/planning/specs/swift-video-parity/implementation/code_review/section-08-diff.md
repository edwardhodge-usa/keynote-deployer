swift-app/Sources/Models/NavigationTab.swift  |   3 +
 swift-app/Sources/Views/ContentView.swift     |   2 +
 swift-app/Sources/Views/VideoDeployView.swift | 504 ++++++++++++++++++++++++++
 swift-app/Tests/VideoDeployViewTests.swift    |  56 +++
 4 files changed, 565 insertions(+)

--- Changes ---

swift-app/Sources/Models/NavigationTab.swift
  @@ -2,6 +2,7 @@ import Foundation
  +    case video
       case projects
       case history
       case settings
  @@ -11,6 +12,7 @@ enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
  +        case .video: "Deploy Video"
           case .projects: "Projects"
           case .history: "History"
           case .settings: "Settings"
  @@ -20,6 +22,7 @@ enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
  +        case .video: "film.stack"
           case .projects: "rectangle.grid.1x2"
           case .history: "clock"
           case .settings: "gearshape"
  +3 -0

swift-app/Sources/Views/ContentView.swift
  @@ -14,6 +14,8 @@ struct ContentView: View {
  +            case .video:
  +                VideoDeployView()
               case .projects:
                   ProjectsView(onSelectProject: { name in
                       selectedProject = name
  +2 -0

swift-app/Sources/Views/VideoDeployView.swift
  @@ -0,0 +1,504 @@
  +import SwiftUI
  +import SwiftData
  +import AVKit
  +import UniformTypeIdentifiers
  +
  +/// Pure, SwiftUI-free logic for `VideoDeployView` — extracted so it's unit-testable
  +/// offline (section-08 tests call these directly).
  +enum VideoDeployLogic {
  +    /// Project name = prefix + kebab(filename without extension). Reuses the same
  +    /// `AppConfig.toKebabCase` the HTML path uses — no new normalization rules.
  +    static func projectName(prefix: String, filename: String) -> String {
  +        let base = (filename as NSString).lastPathComponent
  +        let noExt = (base as NSString).deletingPathExtension
  +        return prefix + AppConfig.toKebabCase(noExt)
  +    }
  +
  +    /// A8: keep only entries whose UTType conforms to `.image`, natural-sorted
  +    /// (section-02). Drops `.DS_Store`, `Icon\r`, `.txt`, etc.
  +    static func filterImages(_ urls: [URL]) -> [String] {
  +        let images = urls.filter { url in
  +            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
  +            return type.conforms(to: .image)
  +        }
  +        return StillsMatch.naturalSort(images.map(\.path))
  +    }
  +
  +    /// Deploy enabled only with a video, at least one still, and a non-blank name.
  +    static func canDeploy(videoPath: String?, stillCount: Int, projectName: String) -> Bool {
  +        videoPath != nil && stillCount > 0 &&
  +            !projectName.trimmingCharacters(in: .whitespaces).isEmpty
  +    }
  +
  +    /// Responsive Framer embed using the PROBED aspect ratio — mirrors the Electron
  +    /// GifViewer.tsx embed (`aspect-ratio:${w}/${h}`, not a hardcoded 16/9).
  +    static func framerEmbed(url: String, width: Int, height: Int) -> String {
  +        "<div style=\"position:relative;width:100%;aspect-ratio:\(width)/\(height)\">"
  +        + "<iframe src=\"\(url)\" style=\"position:absolute;inset:0;width:100%;height:100%;border:none\""
  +        + " loading=\"lazy\" allowfullscreen></iframe></div>"
  +    }
  +
  +    static func humanSize(_ bytes: Int64) -> String {
  +        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  +    }
  +}
  +
  +/// The video-deck deploy front door: drop an H.264 video + a per-slide stills
  +/// folder → deploy an interactive video viewer to Vercel. Mirrors the Electron
  +/// video path and the existing Swift `DeployView` conventions (drop zone,
  +/// NSOpenPanel, settings reads, HistoryEntry persistence, NSPasteboard auto-copy).
  +struct VideoDeployView: View {
  +    @Environment(\.modelContext) private var modelContext
  +
  +    enum Phase { case drop, confirm, deploying, complete, error }
  +
  +    // Build the 4 video-pipeline steps (ids 1–4) the deployer emits.
  +    private static func freshSteps() -> [ProcessingStep] {
  +        [
  +            ProcessingStep(id: 1, label: "Analyze video", detail: "", status: .pending),
  +            ProcessingStep(id: 2, label: "Encode video", detail: "", status: .pending),
  +            ProcessingStep(id: 3, label: "Generate viewer", detail: "", status: .pending),
  +            ProcessingStep(id: 4, label: "Deploy to Vercel", detail: "", status: .pending),
  +        ]
  +    }
  +
  +    @State private var phase: Phase = .drop
  +    @State private var videoPath: String?
  +    @State private var videoSizeBytes: Int64?
  +    @State private var videoWidth: Int?
  +    @State private var videoHeight: Int?
  +    @State private var stillPaths: [String] = []
  +    @State private var fps: Double = 30
  +    @State private var projectName = ""
  +    @State private var secureEmbed = true
  +    @State private var steps = freshSteps()
  +    @State private var result: VideoDeployResult?
  +    @State private var errorMessage = ""
  +    @State private var probeError: String?
  +    @State private var isProbing = false
  +    @State private var isDropTargeted = false
  +    @State private var copied: String?
  +    @State private var deployTask: Task<Void, Never>?
  +
  +    private var slideCount: Int { stillPaths.count }
  +    private var canDeploy: Bool {
  +        VideoDeployLogic.canDeploy(videoPath: videoPath, stillCount: slideCount, projectName: projectName)
  +            && probeError == nil
  +    }
  +
  +    var body: some View {
  +        ScrollView {
  +            VStack(spacing: 0) {
  +                switch phase {
  +                case .drop: dropPhase
  +                case .confirm: confirmPhase
  +                case .deploying: deployingPhase
  +                case .complete: completePhase
  +                case .error: errorPhase
  +                }
  +            }
  +            .padding(32)
  ... (404 lines truncated)
  +504 -0

swift-app/Tests/VideoDeployViewTests.swift
  @@ -0,0 +1,56 @@
  +import Testing
  +import Foundation
  +@testable import KeynoteDeployer
  +
  +/// Section 8 — VideoDeployView pure logic. The View's UI is verified live; the
  +/// logic it relies on is extracted into `VideoDeployLogic` (free static funcs, no
  +/// SwiftUI) so these stay offline + synchronous.
  +@Suite("Section 8 — VideoDeployView logic")
  +struct VideoDeployViewTests {
  +
  +    // Project name = settings prefix + kebab(filename without extension), reusing
  +    // AppConfig.toKebabCase (the same helper the HTML path uses — no new rules).
  +    @Test func projectNameIsPrefixPlusKebabOfFilename() {
  +        #expect(VideoDeployLogic.projectName(prefix: "ils-", filename: "ILS Quals Deck.mp4") == "ils-ils-quals-deck")
  +        // No prefix, mixed separators/punctuation collapse to single hyphens.
  +        #expect(VideoDeployLogic.projectName(prefix: "", filename: "My  Deck (v2).mov") == "my-deck-v2")
  +        // Path, not just a name, still keys off the last component.
  +        #expect(VideoDeployLogic.projectName(prefix: "p-", filename: "/tmp/decks/Final.m4v") == "p-final")
  +    }
  +
  +    // UTType.image filter (A8): images only, natural-sorted, count == images.
  +    @Test func stillsPickerFiltersToImagesAndCountsSlides() {
  +        let urls = [
  +            URL(fileURLWithPath: "/d/slide-2.png"),
  +            URL(fileURLWithPath: "/d/slide-10.jpeg"),
  +            URL(fileURLWithPath: "/d/slide-1.png"),
  +            URL(fileURLWithPath: "/d/.DS_Store"),
  +            URL(fileURLWithPath: "/d/Icon\r"),
  +            URL(fileURLWithPath: "/d/notes.txt"),
  +        ]
  +        let out = VideoDeployLogic.filterImages(urls)
  +        #expect(out.count == 3)                                   // slideCount == image count
  +        #expect(out == ["/d/slide-1.png", "/d/slide-2.png", "/d/slide-10.jpeg"])  // natural-sorted
  +    }
  +
  +    // Deploy disabled until video AND stills.count > 0 AND non-empty name.
  +    @Test func deployDisabledUntilVideoAndStillsAndName() {
  +        #expect(VideoDeployLogic.canDeploy(videoPath: nil, stillCount: 3, projectName: "x") == false)
  +        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 0, projectName: "x") == false)
  +        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "") == false)
  +        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "   ") == false)  // whitespace only
  +        #expect(VideoDeployLogic.canDeploy(videoPath: "/v.mp4", stillCount: 3, projectName: "deck") == true)
  +    }
  +
  +    // Framer embed uses the PROBED aspect ratio (raw width/height), mirroring the
  +    // Electron GifViewer.tsx embed: `aspect-ratio:${w}/${h}` (NOT a hardcoded 16/9).
  +    @Test func framerEmbedUsesProbedAspectRatio() {
  +        let wide = VideoDeployLogic.framerEmbed(url: "https://x.vercel.app", width: 1920, height: 1080)
  +        #expect(wide.contains("aspect-ratio:1920/1080"))
  +        #expect(wide.contains("src=\"https://x.vercel.app\""))
  +
  +        let tall = VideoDeployLogic.framerEmbed(url: "https://y.vercel.app", width: 1600, height: 1200)
  +        #expect(tall.contains("aspect-ratio:1600/1200"))
  +        #expect(!tall.contains("16/9"))  // not hardcoded
  +    }
  +}
  +56 -0
[full diff: rtk git diff --no-compact]
